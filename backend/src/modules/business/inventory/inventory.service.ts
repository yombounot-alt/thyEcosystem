import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { BizPrisma, type BizTx } from "../biz-prisma.service.js";
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
    const newStock = Number(product.currentStock) + delta;
    if (newStock < 0 && !params.allowNegativeStock) {
      throw new BadRequestException(
        `Stock insuffisant pour ${product.name} (disponible : ${product.currentStock}).`,
      );
    }

    await tx.product.update({ where: { id: product.id }, data: { currentStock: newStock } });

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
