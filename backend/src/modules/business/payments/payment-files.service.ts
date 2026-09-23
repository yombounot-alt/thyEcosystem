import { BadRequestException, Inject, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { randomUUID } from "crypto";
import * as path from "path";
import { sniffImageExtension } from "../products/product-images.service.js";
import { STORAGE_PROVIDER, type StoragePort } from "../../../kernel/storage/storage.port.js";

/** Size ceilings (also enforced while uploading, by multer). Phones shrink pictures before sending. */
export const LOGO_MAX_BYTES = 1024 * 1024;
export const PROOF_MAX_BYTES = 3 * 1024 * 1024;

const CONTENT_TYPES: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
};

/**
 * Logos and payment proofs. The storage key is generated here (never taken from the client), and the
 * type is read from the bytes — a ".png" that holds HTML is refused, like product photos.
 */
@Injectable()
export class PaymentFilesService {
  private readonly logger = new Logger(PaymentFilesService.name);

  constructor(@Inject(STORAGE_PROVIDER) private readonly storage: StoragePort) {}

  /** Stores the picture under `prefix` and returns its key. */
  async store(prefix: string, file: Buffer, maxBytes: number): Promise<string> {
    if (file.length === 0 || file.length > maxBytes) {
      throw new BadRequestException(
        `Image trop volumineuse (${Math.round(maxBytes / 1024 / 1024)} Mo maximum).`,
      );
    }
    const extension = sniffImageExtension(file);
    if (!extension) {
      throw new BadRequestException("Format non pris en charge (JPEG, PNG ou WebP).");
    }
    const key = `${prefix}/${randomUUID()}${extension}`;
    await this.storage.put(key, file);
    return key;
  }

  async read(key: string) {
    const body = await this.storage.get(key);
    if (!body) throw new NotFoundException("Fichier introuvable.");
    return { body, contentType: CONTENT_TYPES[path.extname(key)] ?? "application/octet-stream" };
  }

  /** A leftover file is harmless, so a failed cleanup must never fail the request. */
  async discard(key: string | null | undefined) {
    if (!key) return;
    try {
      await this.storage.delete(key);
    } catch (error) {
      this.logger.warn(`Impossible de supprimer ${key} : ${(error as Error).message}`);
    }
  }
}
