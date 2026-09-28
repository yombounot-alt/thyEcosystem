import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { BizPrisma, type BizTx } from "../biz-prisma.service.js";
import { emitBizEvent } from "../common/outbox.js";
import { CreateMovementDto } from "./dto/create-movement.dto.js";
import { InventoryMovementType, movementSign } from "./inventory-movement.types.js";

export interface ApplyMovementParams {
  businessId: string;
  productId: string;
  type: InventoryMovementType;
  quantity: number | Prisma.Decimal;
  unitCost?: number;
  note?: string;
  referenceType?: string;
  referenceId?: string;
  createdBy: string;
  /** Lets a movement that already happened in the real world (an offline sale) go below zero. */
  allowNegativeStock?: boolean;
  /** When the movement really happened, if that is not "now" (an offline sale synced later). */
  occurredAt?: Date;
}

@Injectable()
export class InventoryService {
  constructor(private readonly biz: BizPrisma) {}

  /**
   * Core stock-mutation logic, meant to run inside a caller-supplied transaction so it composes
   * with e.g. product creation (initial stock) or a POS checkout (sale_out) atomically.
   */
  async applyMovement(tx: BizTx, params: ApplyMovementParams) {
    const product = await tx.product.findFirst({
      where: { id: params.productId, businessId: params.businessId },
    });
    if (!product) {
      throw new NotFoundException("Produit introuvable.");
    }

    const delta = movementSign(params.type) * Number(params.quantity);
    // Mise à jour ATOMIQUE (incrément en base, pas « lire puis réécrire une valeur ») : deux ventes
    // simultanées du même produit décrémentent bien deux fois, et la condition `gte` rend le refus
    // « stock insuffisant » exact même en concurrence (la ligne est verrouillée par l'UPDATE).
    const guarded = delta < 0 && !params.allowNegativeStock;
    const updated = await tx.product.updateMany({
      where: {
        id: product.id,
        businessId: params.businessId,
        ...(guarded ? { currentStock: { gte: -delta } } : {}),
      },
      data: { currentStock: { increment: delta } },
    });
    if (updated.count === 0) {
      const fresh = await tx.product.findUnique({ where: { id: product.id } });
      throw new BadRequestException(
        `Stock insuffisant pour ${product.name} (disponible : ${(fresh ?? product).currentStock.toString()}).`,
      );
    }
    const after = await tx.product.findUniqueOrThrow({ where: { id: product.id } });
    await this.alertOnThreshold(tx, params.businessId, after, delta);

    return tx.inventoryMovement.create({
      data: {
        businessId: params.businessId,
        productId: product.id,
        type: params.type,
        quantity: params.quantity,
        unitCost: params.unitCost,
        note: params.note,
        referenceType: params.referenceType,
        referenceId: params.referenceId,
        createdBy: params.createdBy,
        ...(params.occurredAt ? { createdAt: params.occurredAt } : {}),
      },
    });
  }

  /**
   * Prévient les responsables du stock quand un mouvement de SORTIE fait franchir le seuil d'alerte
   * (une seule fois, au franchissement — pas à chaque vente sous le seuil) ou passer sous zéro
   * (vente hors ligne). Les notifications partent via l'outbox, donc seulement si la transaction réussit.
   */
  private async alertOnThreshold(
    tx: BizTx,
    businessId: string,
    product: {
      id: string;
      name: string;
      currentStock: Prisma.Decimal;
      lowStockThreshold: Prisma.Decimal | null;
    },
    delta: number,
  ) {
    if (delta >= 0) return;
    const stock = Number(product.currentStock);
    const before = stock - delta;
    const payload = { productId: product.id, productName: product.name, stock: String(stock) };
    if (stock < 0 && before >= 0) {
      await emitBizEvent(tx, businessId, "STOCK_NEGATIVE", "product", product.id, payload);
      return;
    }
    if (product.lowStockThreshold === null) return;
    const threshold = Number(product.lowStockThreshold);
    if (stock <= threshold && before > threshold)
      await emitBizEvent(tx, businessId, "STOCK_LOW", "product", product.id, {
        ...payload,
        threshold: String(threshold),
      });
  }

  recordManualMovement(businessId: string, dto: CreateMovementDto, createdBy: string) {
    return this.biz.run(businessId, (tx) =>
      this.applyMovement(tx, {
        businessId,
        productId: dto.productId,
        type: dto.type,
        quantity: dto.quantity,
        unitCost: dto.unitCost,
        note: dto.note,
        createdBy,
      }),
    );
  }

  async findAll(
    businessId: string,
    filters: { productId?: string; from?: Date; to?: Date; page?: number; pageSize?: number },
  ) {
    const page = filters.page && filters.page > 0 ? filters.page : 1;
    const pageSize =
      filters.pageSize && filters.pageSize > 0 ? Math.min(filters.pageSize, 100) : 20;

    const where: Prisma.InventoryMovementWhereInput = {
      businessId,
      ...(filters.productId ? { productId: filters.productId } : {}),
      ...(filters.from || filters.to
        ? {
            createdAt: {
              ...(filters.from ? { gte: filters.from } : {}),
              ...(filters.to ? { lte: filters.to } : {}),
            },
          }
        : {}),
    };

    return this.biz.run(businessId, async (tx) => {
      const [items, total] = await Promise.all([
        tx.inventoryMovement.findMany({
          where,
          orderBy: { createdAt: "desc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: { product: { select: { id: true, name: true } } },
        }),
        tx.inventoryMovement.count({ where }),
      ]);
      return { items, total, page, pageSize };
    });
  }
}
