import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { BizPrisma, type BizTx } from "../biz-prisma.service.js";
import { round2 } from "../common/money.js";
import { GrantCreditDto } from "./dto/grant-credit.dto.js";
import { ListCreditsQuery } from "./dto/list-credits.query.js";
import { RecordCreditPaymentDto } from "./dto/record-credit-payment.dto.js";

export interface CreateCreditParams {
  businessId: string;
  customerId: string;
  amount: number;
  saleId?: string;
  dueDate?: Date;
  note?: string;
  createdBy: string;
}

@Injectable()
export class CreditsService {
  constructor(private readonly biz: BizPrisma) {}

  private async assertCustomerExists(tx: BizTx, businessId: string, customerId: string) {
    const customer = await tx.customer.findFirst({ where: { id: customerId, businessId } });
    if (!customer) {
      throw new NotFoundException("Client introuvable.");
    }
    return customer;
  }

  /** Runs inside a caller-supplied transaction — used by SalesService to credit an underpaid sale atomically. */
  async createCredit(tx: BizTx, params: CreateCreditParams) {
    const credit = await tx.customerCredit.create({
      data: {
        businessId: params.businessId,
        customerId: params.customerId,
        saleId: params.saleId,
        originalAmount: params.amount,
        remainingAmount: params.amount,
        dueDate: params.dueDate,
        note: params.note,
        createdBy: params.createdBy,
      },
    });

    await tx.customer.update({
      where: { id: params.customerId },
      data: { currentBalance: { increment: params.amount } },
    });

    return credit;
  }

  async grantManual(
    businessId: string,
    customerId: string,
    dto: GrantCreditDto,
    createdBy: string,
  ) {
    return this.biz.run(businessId, async (tx) => {
      await this.assertCustomerExists(tx, businessId, customerId);
      return this.createCredit(tx, {
        businessId,
        customerId,
        amount: dto.amount,
        dueDate: dto.dueDate ? new Date(dto.dueDate) : undefined,
        note: dto.note,
        createdBy,
      });
    });
  }

  async recordPayment(
    businessId: string,
    customerId: string,
    dto: RecordCreditPaymentDto,
    receivedBy: string,
  ) {
    return this.biz.run(businessId, async (tx) => {
      await this.assertCustomerExists(tx, businessId, customerId);

      const openCredits = await tx.customerCredit.findMany({
        where: { businessId, customerId, status: { in: ["open", "partially_paid"] } },
        orderBy: { createdAt: "asc" },
      });

      const totalOutstanding = round2(
        openCredits.reduce((sum, c) => sum + Number(c.remainingAmount), 0),
      );
      if (totalOutstanding <= 0) {
        throw new BadRequestException("Ce client n'a aucune dette en cours.");
      }
      if (dto.amount > totalOutstanding) {
        throw new BadRequestException(
          `Le montant dépasse la dette totale du client (${totalOutstanding}).`,
        );
      }

      let remaining = dto.amount;
      const paymentsCreated = [];

      for (const credit of openCredits) {
        if (remaining <= 0) break;

        const applied = Math.min(remaining, Number(credit.remainingAmount));
        remaining = round2(remaining - applied);
        const newRemaining = round2(Number(credit.remainingAmount) - applied);

        await tx.customerCredit.update({
          where: { id: credit.id },
          data: {
            remainingAmount: newRemaining,
            status: newRemaining <= 0 ? "paid" : "partially_paid",
          },
        });

        const payment = await tx.creditPayment.create({
          data: {
            businessId,
            customerId,
            customerCreditId: credit.id,
            amount: applied,
            method: dto.method,
            note: dto.note,
            receivedBy,
          },
        });
        paymentsCreated.push(payment);
      }

      await tx.customer.update({
        where: { id: customerId },
        data: { currentBalance: { decrement: dto.amount } },
      });

      return paymentsCreated;
    });
  }

  async listForCustomer(businessId: string, customerId: string) {
    return this.biz.run(businessId, async (tx) => {
      await this.assertCustomerExists(tx, businessId, customerId);
      return tx.customerCredit.findMany({
        where: { businessId, customerId },
        orderBy: { createdAt: "desc" },
      });
    });
  }

  async getStatement(businessId: string, customerId: string) {
    return this.biz.run(businessId, async (tx) => {
      await this.assertCustomerExists(tx, businessId, customerId);

      const [credits, payments] = await Promise.all([
        tx.customerCredit.findMany({ where: { businessId, customerId } }),
        tx.creditPayment.findMany({ where: { businessId, customerId } }),
      ]);

      const entries = [
        ...credits.map((c) => ({ kind: "credit" as const, date: c.createdAt, ...c })),
        ...payments.map((p) => ({ kind: "payment" as const, date: p.paidAt, ...p })),
      ].sort((a, b) => a.date.getTime() - b.date.getTime());

      return entries;
    });
  }

  async listBusinessWide(businessId: string, query: ListCreditsQuery) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? Math.min(query.pageSize, 100) : 20;

    const outstandingOnly = query.status === "outstanding";
    const where: Prisma.CustomerCreditWhereInput = {
      businessId,
      ...(outstandingOnly
        ? { status: { in: ["open", "partially_paid"] } }
        : query.status
          ? { status: query.status }
          : {}),
    };

    return this.biz.run(businessId, async (tx) => {
      const [items, total] = await Promise.all([
        tx.customerCredit.findMany({
          where,
          // Still-owed credits: earliest due date first (undated last) so late ones surface on top.
          orderBy: outstandingOnly
            ? [{ dueDate: { sort: "asc", nulls: "last" } }, { createdAt: "asc" }]
            : { createdAt: "desc" },
          skip: (page - 1) * pageSize,
          take: pageSize,
          include: { customer: { select: { id: true, fullName: true, phone: true } } },
        }),
        tx.customerCredit.count({ where }),
      ]);
      return { items, total, page, pageSize };
    });
  }
}
