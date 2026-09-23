/** Rounds to 2 decimal places, matching the numeric(14,2) columns storing money amounts. */
export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}
