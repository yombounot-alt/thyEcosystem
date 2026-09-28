import { Injectable } from "@nestjs/common";
import { createHash } from "node:crypto";
import { Db } from "../../kernel/db/db.service.js";

/**
 * Seau stable 0–99 d'un utilisateur pour un flag : le même utilisateur reste du même côté d'un
 * déploiement progressif (10 % → 50 % → 100 %), et chaque flag a son propre tirage.
 */
export function rolloutBucket(flagKey: string, userId: string): number {
  return createHash("sha256").update(`${flagKey}:${userId}`).digest().readUInt32BE(0) % 100;
}

/**
 * Feature flags (docs/blueprint/04-identity-access.md §6.2 règle 4) : pilotent le DÉPLOIEMENT
 * (kill-switch, pourcentage, pays), jamais le droit commercial (→ SubscriptionsService).
 */
@Injectable()
export class FeatureFlagsService {
  constructor(private readonly db: Db) {}

  /** Clés des flags actifs pour cet utilisateur (pays = celui de son entreprise active, si connu). */
  async enabledFor(userId: string, country: string | null): Promise<string[]> {
    const flags = await this.db.query<{
      key: string;
      rolloutPercent: number;
      countries: string[] | null;
    }>("SELECT key, rollout_percent, countries FROM ops.feature_flags WHERE enabled ORDER BY key");
    return flags.rows
      .filter((f) => !f.countries || (country !== null && f.countries.includes(country)))
      .filter((f) => rolloutBucket(f.key, userId) < f.rolloutPercent)
      .map((f) => f.key);
  }
}
