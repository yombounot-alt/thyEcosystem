import { Injectable, NotFoundException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { BizPrisma } from "../biz-prisma.service.js";
import { CreateExpenseDto } from "./dto/create-expense.dto.js";
import { ListExpensesQuery } from "./dto/list-expenses.query.js";
import { UpdateExpenseDto } from "./dto/update-expense.dto.js";

@Injectable()
export class ExpensesService {
  constructor(private readonly biz: BizPrisma) {}

  create(businessId: string, dto: CreateExpenseDto, recordedBy: string) {
    return this.biz.run(businessId, (tx) =>
      tx.expense.create({
        data: {
          businessId,
          category: dto.category,
          amount: dto.amount,
          description: dto.description,
          expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : undefined,
          recordedBy,
        },
      }),
    );
  }

  async findAll(businessId: string, query: ListExpensesQuery) {
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? Math.min(query.pageSize, 100) : 20;

    const where: Prisma.ExpenseWhereInput = {
      businessId,
      ...(query.from || query.to
        ? {
            expenseDate: {
              ...(query.from ? { gte: query.from } : {}),
              ...(query.to ? { lte: query.to } : {}),
            },
          }
        : {}),
    };

    return this.biz.run(businessId, async (tx) => {
      const [items, total, sum] = await Promise.all([
        tx.expense.findMany({
          where,
          orderBy: [{ expenseDate: "desc" }, { createdAt: "desc" }],
          skip: (page - 1) * pageSize,
          take: pageSize,
        }),
        tx.expense.count({ where }),
        tx.expense.aggregate({ where, _sum: { amount: true } }),
      ]);

      // Somme sur toute la période filtrée, pas seulement la page renvoyée.
      return { items, total, page, pageSize, totalAmount: Number(sum._sum.amount ?? 0) };
    });
  }

  async findOne(businessId: string, id: string) {
    const expense = await this.biz.run(businessId, (tx) =>
      tx.expense.findFirst({ where: { id, businessId } }),
    );
    if (!expense) {
      throw new NotFoundException("Dépense introuvable.");
    }
    return expense;
  }

  async update(businessId: string, id: string, dto: UpdateExpenseDto) {
    await this.findOne(businessId, id);
    return this.biz.run(businessId, (tx) =>
      tx.expense.update({
        where: { id },
        data: {
          ...dto,
          expenseDate: dto.expenseDate ? new Date(dto.expenseDate) : undefined,
        },
      }),
    );
  }

  async remove(businessId: string, id: string): Promise<void> {
    await this.findOne(businessId, id);
    await this.biz.run(businessId, (tx) => tx.expense.delete({ where: { id } }));
  }
}
