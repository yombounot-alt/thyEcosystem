import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma, Product } from "@prisma/client";
import { BizPrisma, type BizTx } from "../biz-prisma.service.js";
import { isUniqueViolation } from "../common/db-errors.js";
import { round2 } from "../common/money.js";
import { CreditsService } from "../credits/credits.service.js";
import { InventoryService } from "../inventory/inventory.service.js";
import { CreateSaleDto } from "./dto/create-sale.dto.js";
import { ListSalesQuery } from "./dto/list-sales.query.js";

const MAX_SALE_NUMBER_RETRIES = 3;

/** An offline sale can wait a long time for a network, but not forever. */
const MAX_OFFLINE_SALE_AGE_MS = 60 * 24 * 60 * 60 * 1000;

/** Everything a receipt screen needs, in one query. */
const RECEIPT_INCLUDE = {
  items: true,
  payments: true,
  customer: { select: { id: true, fullName: true, phone: true } },
} satisfies Prisma.SaleInclude;

/** What is needed to price a basket. */
type CartInput = Pick<CreateSaleDto, "items" | "discountTotal" | "customerId">;

export interface PricedLine {
  product: Product;
  quantity: number;
  unitPrice: number;
  lineTotal: number;
}

export interface CartQuote {
  lines: PricedLine[];
  subtotal: number;
  discountTotal: number;
  total: number;
}

export interface CheckoutOptions {
  /**
   * Unit prices (by product id) already agreed with the customer, used instead of the current
   * catalogue price. A mobile-money payment fixes the price when the customer is shown the amount,
   * so a price edited during the payment must not change what was charged.
   */
  unitPrices?: Record<string, number>;
}

@Injectable()
export class SalesService {
  constructor(
    private readonly biz: BizPrisma,
    private readonly inventory: InventoryService,
    private readonly credits: CreditsService,
  ) {}

  /**
   * Idempotent when the client sends a clientRequestId: replaying the same checkout (network
   * retry, double tap) returns the original sale and never sells or debits stock twice.
   */
  async checkout(
    businessId: string,
    dto: CreateSaleDto,
    soldBy: string,
    options?: CheckoutOptions,
  ) {
    const requestId = dto.clientRequestId;
    if (requestId) {
      const existing = await this.findByClientRequestId(businessId, requestId);
      if (existing) return existing;
    }

    for (let attempt = 1; attempt <= MAX_SALE_NUMBER_RETRIES; attempt++) {
      try {
        return await this.attemptCheckout(businessId, dto, soldBy, options);
      } catch (error) {
        const numberCollision = isUniqueViolation(error, "sale_number");

        // Two identical requests racing each other: the unique indexes let only one through,
        // and the loser fails on either index (same request id, or same computed sale number).
        if (requestId && (numberCollision || isUniqueViolation(error, "client_request_id"))) {
          const existing = await this.findByClientRequestId(businessId, requestId);
          if (existing) return existing;
        }
        if (!numberCollision || attempt === MAX_SALE_NUMBER_RETRIES) {
          throw error;
        }
      }
    }
    throw new Error("unreachable");
  }

  private findByClientRequestId(businessId: string, clientRequestId: string) {
    return this.biz.run(businessId, (tx) =>
      tx.sale.findFirst({
        where: { businessId, clientRequestId },
        include: RECEIPT_INCLUDE,
      }),
    );
  }

  /**
   * The moment the sale really happened when it was rung up offline, otherwise undefined ("now").
   * A phone clock running ahead must not make a legitimate sale unsendable, so a future date is
   * simply brought back to now; a date far in the past is refused.
   */
  private resolveSoldAt(dto: CreateSaleDto): Date | undefined {
    if (!dto.soldAt) return undefined;

    const now = Date.now();
    const soldAt = new Date(dto.soldAt).getTime();
    if (soldAt < now - MAX_OFFLINE_SALE_AGE_MS) {
      throw new BadRequestException(
        "La date de la vente est trop ancienne (60 jours maximum). Enregistrez-la à nouveau manuellement.",
      );
    }
    return new Date(Math.min(soldAt, now));
  }

  /**
   * Prices a basket exactly as a checkout would (same products, same rounding, same checks)
   * without recording anything. Used by mobile-money payments to know the amount to charge.
   */
  quote(businessId: string, dto: CartInput): Promise<CartQuote> {
    return this.biz.run(businessId, (tx) => this.quoteIn(tx, businessId, dto));
  }

  /** Variante à utiliser dans une transaction déjà ouverte (évite d'emprunter une 2ᵉ connexion). */
  async quoteIn(tx: BizTx, businessId: string, dto: CartInput): Promise<CartQuote> {
    const quote = await this.priceCart(tx, businessId, dto, { offline: false });
    if (dto.customerId) {
      await this.assertCustomerExists(tx, businessId, dto.customerId);
    }
    return quote;
  }

  private async priceCart(
    db: BizTx,
    businessId: string,
    dto: CartInput,
    opts: { offline: boolean; unitPrices?: Record<string, number> },
  ): Promise<CartQuote> {
    const productIds = dto.items.map((i) => i.productId);
    const products = await db.product.findMany({ where: { id: { in: productIds }, businessId } });
    const productById = new Map(products.map((p) => [p.id, p]));

    let subtotal = 0;
    const lines = dto.items.map((item) => {
      const product = productById.get(item.productId);
      if (!product) {
        throw new NotFoundException(`Produit introuvable : ${item.productId}`);
      }
      // An offline sale already happened: the product left the shelf even if it was
      // deactivated in the meantime, so it must still be recorded.
      if (!product.isActive && !opts.offline) {
        throw new BadRequestException(`Produit inactif : ${product.name}`);
      }
      const unitPrice = opts.unitPrices?.[item.productId] ?? Number(product.salePrice);
      const lineTotal = round2(unitPrice * item.quantity);
      subtotal = round2(subtotal + lineTotal);
      return { product, quantity: item.quantity, unitPrice, lineTotal };
    });

    const discountTotal = dto.discountTotal ?? 0;
    if (discountTotal > subtotal) {
      throw new BadRequestException("La réduction ne peut pas dépasser le sous-total.");
    }
    return { lines, subtotal, discountTotal, total: round2(subtotal - discountTotal) };
  }

  private async assertCustomerExists(db: BizTx, businessId: string, customerId: string) {
    const customer = await db.customer.findFirst({ where: { id: customerId, businessId } });
    if (!customer) {
      throw new NotFoundException("Client introuvable.");
    }
  }

  private async attemptCheckout(
    businessId: string,
    dto: CreateSaleDto,
    soldBy: string,
    options?: CheckoutOptions,
  ) {
    const soldAt = this.resolveSoldAt(dto);
    const offline = dto.offline === true;

    return this.biz.run(businessId, async (tx) => {
      const {
        lines: lineInputs,
        subtotal,
        discountTotal,
        total,
      } = await this.priceCart(tx, businessId, dto, { offline, unitPrices: options?.unitPrices });

      const payments = dto.payments ?? [];
      const amountPaid = round2(payments.reduce((sum, p) => sum + p.amount, 0));
      const amountDue = round2(Math.max(total - amountPaid, 0));

      if (amountDue > 0 && !dto.customerId) {
        throw new BadRequestException(
          "Le paiement ne couvre pas le total de la vente. Sélectionnez un client pour vendre à crédit.",
        );
      }
      if (dto.customerId) {
        await this.assertCustomerExists(tx, businessId, dto.customerId);
      }

      const saleCount = await tx.sale.count({ where: { businessId } });
      const saleNumber = `VTE-${String(saleCount + 1).padStart(4, "0")}`;

      const sale = await tx.sale.create({
        data: {
          businessId,
          customerId: dto.customerId,
          clientRequestId: dto.clientRequestId,
          saleNumber,
          subtotal,
          discountTotal,
          total,
          amountPaid,
          amountDue,
          soldBy,
          ...(soldAt ? { soldAt } : {}),
        },
      });

      for (const line of lineInputs) {
        await tx.saleItem.create({
          data: {
            businessId,
            saleId: sale.id,
            productId: line.product.id,
            productNameSnapshot: line.product.name,
            unitPrice: line.unitPrice,
            unitCostSnapshot: line.product.purchasePrice,
            quantity: line.quantity,
            lineTotal: line.lineTotal,
          },
        });

        await this.inventory.applyMovement(tx, {
          businessId,
          productId: line.product.id,
          type: "sale_out",
          quantity: line.quantity,
          referenceType: "sale",
          referenceId: sale.id,
          createdBy: soldBy,
          allowNegativeStock: offline,
          occurredAt: soldAt,
        });
      }

      for (const payment of payments) {
        await tx.payment.create({
          data: {
            businessId,
            saleId: sale.id,
            method: payment.method,
            amount: payment.amount,
            providerReference: payment.providerReference,
            receivedBy: soldBy,
          },
        });
      }

      if (amountDue > 0) {
        await this.credits.createCredit(tx, {
          businessId,
          customerId: dto.customerId!,
          saleId: sale.id,
          amount: amountDue,
          note: `Solde restant sur la vente ${saleNumber}`,
          createdBy: soldBy,
        });
      }

      return this.loadReceipt(tx, sale.id);
    });
  }

  async findAll(businessId: string, query: ListSalesQuery) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? Math.min(query.pageSize, 100) : 20;

    const where: Prisma.SaleWhereInput = {
      businessId,
      ...(query.from || query.to
        ? {
            soldAt: {
              ...(query.from ? { gte: query.from } : {}),
              ...(query.to ? { lte: query.to } : {}),
            },
          }
        : {}),
    };

    return this.biz.run(businessId, async (tx) => {
      const [items, total] = await Promise.all([
        tx.sale.findMany({
          where,
          orderBy: { soldAt: "desc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: {
            _count: { select: { items: true } },
            customer: { select: { id: true, fullName: true } },
          },
        }),
        tx.sale.count({ where }),
      ]);
      return { items, total, page, pageSize };
    });
  }

  async findOne(businessId: string, id: string) {
    const sale = await this.biz.run(businessId, (tx) =>
      tx.sale.findFirst({
        where: { id, businessId },
        include: RECEIPT_INCLUDE,
      }),
    );
    if (!sale) {
      throw new NotFoundException("Vente introuvable.");
    }
    return sale;
  }

  async void(businessId: string, id: string, voidedBy: string) {
    const sale = await this.findOne(businessId, id);
    if (sale.status !== "completed") {
      throw new BadRequestException("Seule une vente terminée peut être annulée.");
    }

    return this.biz.run(businessId, async (tx) => {
      for (const item of sale.items) {
        await this.inventory.applyMovement(tx, {
          businessId,
          productId: item.productId,
          type: "adjustment_in",
          quantity: item.quantity,
          referenceType: "sale_void",
          referenceId: sale.id,
          note: `Annulation de la vente ${sale.saleNumber}`,
          createdBy: voidedBy,
        });
      }

      const openCredits = await tx.customerCredit.findMany({
        where: { saleId: sale.id, status: { in: ["open", "partially_paid"] } },
      });
      for (const credit of openCredits) {
        if (Number(credit.remainingAmount) > 0) {
          await tx.customer.update({
            where: { id: credit.customerId },
            data: { currentBalance: { decrement: credit.remainingAmount } },
          });
        }
        await tx.customerCredit.update({
          where: { id: credit.id },
          data: { remainingAmount: 0, status: "void" },
        });
      }

      await tx.sale.update({ where: { id: sale.id }, data: { status: "void" } });
      return this.loadReceipt(tx, sale.id);
    });
  }

  private loadReceipt(tx: BizTx, saleId: string) {
    return tx.sale.findUniqueOrThrow({
      where: { id: saleId },
      include: RECEIPT_INCLUDE,
    });
  }
}
