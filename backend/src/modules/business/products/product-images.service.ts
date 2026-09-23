import { BadRequestException, Inject, Injectable, Logger, NotFoundException } from "@nestjs/common";
import { randomUUID } from "node:crypto";
import path from "node:path";
import { STORAGE_PROVIDER, type StoragePort } from "../../../kernel/storage/storage.port.js";
import { BizPrisma } from "../biz-prisma.service.js";

/** Photos are resized by the app before upload; this is the server-side safety net. */
export const PRODUCT_IMAGE_MAX_BYTES = 2 * 1024 * 1024;

const CONTENT_TYPES: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
};

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** Identifies JPEG / PNG / WebP from the first bytes — never from the client's file name or MIME type. */
export function sniffImageExtension(buffer: Buffer): ".jpg" | ".png" | ".webp" | null {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return ".jpg";
  }
  if (buffer.length >= PNG_SIGNATURE.length && buffer.subarray(0, 8).equals(PNG_SIGNATURE)) {
    return ".png";
  }
  if (
    buffer.length >= 12 &&
    buffer.subarray(0, 4).toString("ascii") === "RIFF" &&
    buffer.subarray(8, 12).toString("ascii") === "WEBP"
  ) {
    return ".webp";
  }
  return null;
}

const WITH_CATEGORY = { category: { select: { id: true, name: true } } } as const;

@Injectable()
export class ProductImagesService {
  private readonly logger = new Logger(ProductImagesService.name);

  constructor(
    private readonly biz: BizPrisma,
    @Inject(STORAGE_PROVIDER) private readonly storage: StoragePort,
  ) {}

  /** Sets (or replaces) the photo. The storage key is generated here and changes on every upload. */
  async set(businessId: string, productId: string, file: Buffer) {
    const product = await this.find(businessId, productId);

    const extension = sniffImageExtension(file);
    if (!extension) {
      throw new BadRequestException("Format de photo non pris en charge (JPEG, PNG ou WebP).");
    }

    const key = `${businessId}/products/${productId}/${randomUUID()}${extension}`;
    await this.storage.put(key, file);

    let updated;
    try {
      updated = await this.biz.run(businessId, (tx) =>
        tx.product.update({
          where: { id: productId },
          data: { imageKey: key },
          include: WITH_CATEGORY,
        }),
      );
    } catch (error) {
      await this.discard(key);
      throw error;
    }

    if (product.imageKey) await this.discard(product.imageKey);
    return updated;
  }

  async read(businessId: string, productId: string) {
    const product = await this.find(businessId, productId);
    if (!product.imageKey) {
      throw new NotFoundException("Ce produit n'a pas de photo.");
    }

    const body = await this.storage.get(product.imageKey);
    if (!body) {
      throw new NotFoundException("Ce produit n'a pas de photo.");
    }

    const contentType = CONTENT_TYPES[path.extname(product.imageKey)] ?? "application/octet-stream";
    return { body, contentType };
  }

  async remove(businessId: string, productId: string) {
    const product = await this.find(businessId, productId);
    if (!product.imageKey) return this.withCategory(businessId, productId);

    await this.biz.run(businessId, (tx) =>
      tx.product.update({ where: { id: productId }, data: { imageKey: null } }),
    );
    await this.discard(product.imageKey);
    return this.withCategory(businessId, productId);
  }

  /** Tenant-scoped lookup: another business's product is a 404, exactly like everywhere else. */
  private async find(businessId: string, productId: string) {
    const product = await this.biz.run(businessId, (tx) =>
      tx.product.findFirst({ where: { id: productId, businessId } }),
    );
    if (!product) {
      throw new NotFoundException("Produit introuvable.");
    }
    return product;
  }

  private withCategory(businessId: string, productId: string) {
    return this.biz.run(businessId, (tx) =>
      tx.product.findUniqueOrThrow({ where: { id: productId }, include: WITH_CATEGORY }),
    );
  }

  /** A leftover file is harmless, so a failed cleanup must never fail the request. */
  private async discard(key: string) {
    try {
      await this.storage.delete(key);
    } catch (error) {
      this.logger.warn(`Impossible de supprimer ${key} : ${(error as Error).message}`);
    }
  }
}
