export type InventoryMovementType =
  "initial" | "purchase_in" | "sale_out" | "adjustment_in" | "adjustment_out";

/** Types a client may request directly via POST /inventory/movements ("Entrées / Sorties / Ajustements"). */
export const MANUAL_MOVEMENT_TYPES = ["purchase_in", "adjustment_in", "adjustment_out"] as const;

const INCREASE_TYPES: InventoryMovementType[] = ["initial", "purchase_in", "adjustment_in"];

/** 'initial'/'sale_out' are only ever created internally (product creation, POS checkout), never accepted from a client DTO. */
export function movementSign(type: InventoryMovementType): 1 | -1 {
  return INCREASE_TYPES.includes(type) ? 1 : -1;
}
