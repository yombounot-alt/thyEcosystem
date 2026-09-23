import { BadRequestException } from "@nestjs/common";

export const PERIODS = ["today", "week", "month", "custom"] as const;
export type Period = (typeof PERIODS)[number];

export interface DateRange {
  from: Date;
  to: Date;
}

/** 'today'/'week'/'month' are computed server-side; 'custom' requires from/to in the query. */
export function resolvePeriod(period: Period | undefined, from?: Date, to?: Date): DateRange {
  const now = new Date();

  if (period === "custom") {
    if (!from || !to) {
      throw new BadRequestException("from et to sont requis pour period=custom.");
    }
    return { from, to };
  }

  if (period === "week") {
    const start = new Date(now);
    start.setDate(start.getDate() - 6);
    start.setHours(0, 0, 0, 0);
    return { from: start, to: now };
  }

  if (period === "month") {
    const start = new Date(now.getFullYear(), now.getMonth(), 1);
    return { from: start, to: now };
  }

  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  return { from: start, to: now };
}
