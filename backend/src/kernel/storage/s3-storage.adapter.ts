import { Inject, Injectable, type OnModuleDestroy } from "@nestjs/common";
import {
  DeleteObjectCommand,
  GetObjectCommand,
  NoSuchKey,
  PutObjectCommand,
  S3Client,
  S3ServiceException,
} from "@aws-sdk/client-s3";
import { CONFIG, type AppConfig } from "../config/config.js";
import type { StoragePort } from "./storage.port.js";

/** Clés générées côté serveur uniquement ; on refuse quand même ce qui ressemble à une évasion. */
function assertSafeKey(key: string): void {
  if (!key || key.startsWith("/") || key.split("/").some((part) => part === ".." || part === ""))
    throw new Error(`Clé de stockage invalide : ${key}`);
}

/**
 * Stockage objet compatible S3 (ADR-012) : RustFS en développement, Cloud Storage en staging et en
 * production via son API d'interopérabilité S3 (clé HMAC d'un compte de service dédié, voir
 * infra/terraform/modules/storage). Le bucket est privé : les fichiers ne sont jamais servis
 * directement, toujours à travers l'API (qui vérifie l'entreprise et les droits).
 */
@Injectable()
export class S3StorageAdapter implements StoragePort, OnModuleDestroy {
  private readonly client: S3Client;
  private readonly bucket: string;

  constructor(@Inject(CONFIG) cfg: AppConfig) {
    const s3 = cfg.storage.s3;
    if (cfg.storage.driver !== "s3" || !s3)
      throw new Error("S3StorageAdapter instancié sans configuration S3 (STORAGE_DRIVER=s3)");
    this.bucket = s3.bucket;
    this.client = new S3Client({
      endpoint: s3.endpoint,
      region: s3.region,
      forcePathStyle: s3.forcePathStyle,
      credentials: { accessKeyId: s3.accessKeyId, secretAccessKey: s3.secretAccessKey },
      // Cloud Storage (interop S3) ne connaît pas les sommes de contrôle CRC que le SDK ajoute par
      // défaut depuis 2025 : on ne les envoie que lorsqu'une opération les exige.
      requestChecksumCalculation: "WHEN_REQUIRED",
      responseChecksumValidation: "WHEN_REQUIRED",
      maxAttempts: 3,
    });
  }

  async put(key: string, body: Buffer): Promise<void> {
    assertSafeKey(key);
    await this.client.send(
      new PutObjectCommand({
        Bucket: this.bucket,
        Key: key,
        Body: body,
        ContentLength: body.length,
        // Le type réel est déterminé par l'API à la lecture (octets inspectés à l'envoi) : le
        // bucket n'est jamais servi tel quel, ce type n'est qu'indicatif.
        ContentType: "application/octet-stream",
      }),
    );
  }

  async get(key: string): Promise<Buffer | null> {
    assertSafeKey(key);
    try {
      const res = await this.client.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
      if (!res.Body) return null;
      return Buffer.from(await res.Body.transformToByteArray());
    } catch (error) {
      if (error instanceof NoSuchKey) return null;
      if (error instanceof S3ServiceException && error.$metadata.httpStatusCode === 404)
        return null;
      throw error;
    }
  }

  /** Supprimer une clé absente n'est pas une erreur (S3 répond 204 dans les deux cas). */
  async delete(key: string): Promise<void> {
    assertSafeKey(key);
    await this.client.send(new DeleteObjectCommand({ Bucket: this.bucket, Key: key }));
  }

  onModuleDestroy(): void {
    this.client.destroy();
  }
}
