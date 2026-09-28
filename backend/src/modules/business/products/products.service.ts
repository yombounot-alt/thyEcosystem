import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { SubscriptionsService } from "../../subscriptions/subscriptions.service.js";
import { BizPrisma, type BizTx } from "../biz-prisma.service.js";
import { InventoryService } from "../inventory/inventory.service.js";
import { CreateProductDto } from "./dto/create-product.dto.js";
import { ListProductsQuery } from "./dto/list-products.query.js";
import { UpdateProductDto } from "./dto/update-product.dto.js";

const DUPLICATE_PRODUCT = "Un produit avec ce SKU ou ce code-barres existe déjà.";

@Injectable()
export class ProductsService {
  constructor(
    private readonly biz: BizPrisma,
    private readonly inventory: InventoryService,
    private readonly subscriptions: SubscriptionsService,
  ) {}

  /** Limite de l'offre sur les produits ACTIFS (un produit désactivé libère sa place). */
  private async assertProductRoom(tx: BizTx, businessId: string, limit: number | null) {
    if (limit === null) return;
    const active = await tx.product.count({ where: { businessId, isActive: true } });
    this.subscriptions.assertRoomFor("products.max", limit, active);
  }

  async create(businessId: string, dto: CreateProductDto, createdBy: string) {
    const limit = await this.subscriptions.limit(businessId, "products.max");
    try {
      return await this.biz.run(businessId, async (tx) => {
        await this.assertProductRoom(tx, businessId, limit);
        const product = await tx.product.create({
          data: {
            businessId,
            categoryId: dto.categoryId,
            name: dto.name,
            sku: dto.sku,
            barcode: dto.barcode,
            unit: dto.unit ?? "unite",
            purchasePrice: dto.purchasePrice ?? 0,
            salePrice: dto.salePrice,
            lowStockThreshold: dto.lowStockThreshold,
            description: dto.description,
          },
        });

        if (dto.initialStock && dto.initialStock > 0) {
          await this.inventory.applyMovement(tx, {
            businessId,
            productId: product.id,
            type: "initial",
            quantity: dto.initialStock,
            createdBy,
          });
        }

        return tx.product.findUniqueOrThrow({ where: { id: product.id } });
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        throw new ConflictException(DUPLICATE_PRODUCT);
      }
      throw error;
    }
  }

  async findAll(businessId: string, query: ListProductsQuery) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? Math.min(query.pageSize, 100) : 20;

    const where: Prisma.ProductWhereInput = {
      businessId,
      isActive: query.isActive ?? true,
      ...(query.categoryId ? { categoryId: query.categoryId } : {}),
      ...(query.search
        ? {
            OR: [
              { name: { contains: query.search, mode: "insensitive" } },
              { sku: { contains: query.search, mode: "insensitive" } },
              { barcode: { contains: query.search, mode: "insensitive" } },
            ],
          }
        : {}),
    };

    return this.biz.run(businessId, async (tx) => {
      const [items, total] = await Promise.all([
        tx.product.findMany({
          where,
          orderBy: { name: "asc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: { category: { select: { id: true, name: true } } },
        }),
        tx.product.count({ where }),
      ]);
      return { items, total, page, pageSize };
    });
  }

  async findOne(businessId: string, id: string) {
    const product = await this.biz.run(businessId, (tx) =>
      tx.product.findFirst({
        where: { id, businessId },
        include: { category: { select: { id: true, name: true } } },
      }),
    );
    if (!product) {
      throw new NotFoundException("Produit introuvable.");
    }
    return product;
  }

  async update(businessId: string, id: string, dto: UpdateProductDto) {
    const existing = await this.findOne(businessId, id);
    // Réactiver un produit reprend une place de l'offre.
    const reactivating = dto.isActive === true && !existing.isActive;
    const limit = reactivating ? await this.subscriptions.limit(businessId, "products.max") : null;
    try {
      return await this.biz.run(businessId, async (tx) => {
        if (reactivating) await this.assertProductRoom(tx, businessId, limit);
        return tx.product.update({ where: { id }, data: dto });
      });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        throw new ConflictException(DUPLICATE_PRODUCT);
      }
      throw error;
    }
  }

  /** Soft delete: keeps historical sale_items/inventory_movements referencing this product intact. */
  async deactivate(businessId: string, id: string) {
    await this.findOne(businessId, id);
    return this.biz.run(businessId, (tx) =>
      tx.product.update({ where: { id }, data: { isActive: false } }),
    );
  }

  async lowStock(businessId: string) {
    return this.biz.run(businessId, (tx) => this.lowStockIn(tx, businessId));
  }

  /** Variante à utiliser dans une transaction déjà ouverte (tableau de bord). */
  async lowStockIn(tx: BizTx, businessId: string) {
    const candidates = await tx.product.findMany({
      where: { businessId, isActive: true, lowStockThreshold: { not: null } },
      orderBy: { name: "asc" },
    });
    return candidates.filter((p) => Number(p.currentStock) <= Number(p.lowStockThreshold));
  }
}
