import { Injectable } from "@nestjs/common";
import { BizPrisma } from "../biz-prisma.service.js";
import { round2 } from "../common/money.js";
import { ProductsService } from "../products/products.service.js";
import { resolvePeriod } from "./dashboard-period.js";
import { DashboardPeriodQuery } from "./dto/dashboard-period.query.js";
import { SalesChartQuery } from "./dto/sales-chart.query.js";
import { TopProductsQuery } from "./dto/top-products.query.js";

@Injectable()
export class DashboardService {
  constructor(
    private readonly biz: BizPrisma,
    private readonly products: ProductsService,
  ) {}

  /**
   * `canSeeProfit` (permission `finance:view_profit`) : sans elle, le coût des marchandises et le
   * bénéfice ne sont pas renvoyés (`null`) — le chiffre d'affaires reste visible (`reports:view`).
   */
  async getSummary(businessId: string, query: DashboardPeriodQuery, canSeeProfit = true) {
    const { from, to } = resolvePeriod(query.period, query.from, query.to);

    return this.biz.run(businessId, async (tx) => {
      const sales = await tx.sale.findMany({
        where: { businessId, status: "completed", soldAt: { gte: from, lte: to } },
        include: { items: true },
      });

      const revenue = round2(sales.reduce((sum, sale) => sum + Number(sale.total), 0));
      const cogs = round2(
        sales.reduce(
          (sum, sale) =>
            sum +
            sale.items.reduce(
              (itemSum, item) => itemSum + Number(item.unitCostSnapshot) * Number(item.quantity),
              0,
            ),
          0,
        ),
      );
      const ordersCount = sales.length;

      const expensesAgg = await tx.expense.aggregate({
        where: { businessId, expenseDate: { gte: from, lte: to } },
        _sum: { amount: true },
      });
      const expensesTotal = Number(expensesAgg._sum.amount ?? 0);

      const profit = round2(revenue - cogs - expensesTotal);

      const lowStockCount = (await this.products.lowStockIn(tx, businessId)).length;

      const outstandingAgg = await tx.customerCredit.aggregate({
        where: { businessId, status: { in: ["open", "partially_paid"] } },
        _sum: { remainingAmount: true },
      });
      const outstandingCredits = Number(outstandingAgg._sum.remainingAmount ?? 0);

      // Due dates are calendar dates: a credit due today is not late until the day is over.
      // (Guinea is UTC+0, so UTC midnight is the business's midnight.)
      const startOfToday = new Date();
      startOfToday.setUTCHours(0, 0, 0, 0);
      const overdueCreditsCount = await tx.customerCredit.count({
        where: {
          businessId,
          status: { in: ["open", "partially_paid"] },
          dueDate: { lt: startOfToday },
        },
      });

      return {
        period: { from, to },
        revenue,
        cogs: canSeeProfit ? cogs : null,
        expensesTotal,
        profit: canSeeProfit ? profit : null,
        ordersCount,
        lowStockCount,
        outstandingCredits,
        overdueCreditsCount,
      };
    });
  }

  async getSalesChart(businessId: string, query: SalesChartQuery) {
    const days = query.days && query.days > 0 ? query.days : 7;

    const start = new Date();
    start.setDate(start.getDate() - (days - 1));
    start.setHours(0, 0, 0, 0);

    const sales = await this.biz.run(businessId, (tx) =>
      tx.sale.findMany({
        where: { businessId, status: "completed", soldAt: { gte: start } },
        select: { total: true, soldAt: true },
      }),
    );

    const buckets = new Map<string, number>();
    for (let i = 0; i < days; i++) {
      const day = new Date(start);
      day.setDate(day.getDate() + i);
      buckets.set(day.toISOString().slice(0, 10), 0);
    }

    for (const sale of sales) {
      const key = sale.soldAt.toISOString().slice(0, 10);
      buckets.set(key, round2((buckets.get(key) ?? 0) + Number(sale.total)));
    }

    return Array.from(buckets.entries()).map(([date, revenue]) => ({ date, revenue }));
  }

  async getTopProducts(businessId: string, query: TopProductsQuery) {
    const { from, to } = resolvePeriod(query.period, query.from, query.to);
    const limit = query.limit && query.limit > 0 ? Math.min(query.limit, 50) : 5;

    const items = await this.biz.run(businessId, (tx) =>
      tx.saleItem.findMany({
        where: { sale: { businessId, status: "completed", soldAt: { gte: from, lte: to } } },
        select: { productId: true, productNameSnapshot: true, quantity: true, lineTotal: true },
      }),
    );

    const byProduct = new Map<
      string,
      { productId: string; name: string; quantity: number; revenue: number }
    >();
    for (const item of items) {
      const entry = byProduct.get(item.productId) ?? {
        productId: item.productId,
        name: item.productNameSnapshot,
        quantity: 0,
        revenue: 0,
      };
      entry.quantity = round2(entry.quantity + Number(item.quantity));
      entry.revenue = round2(entry.revenue + Number(item.lineTotal));
      byProduct.set(item.productId, entry);
    }

    return Array.from(byProduct.values())
      .sort((a, b) => b.revenue - a.revenue)
      .slice(0, limit);
  }
}
