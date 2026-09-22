import { Injectable } from "@nestjs/common";
import { Db } from "../db/db.service.js";
import { RedisService } from "../redis/redis.service.js";

export interface UserState {
  id: string;
  status: "ACTIVE" | "SUSPENDED" | "BANNED" | "DELETED";
  tokenVersion: number;
  phoneVerified: boolean;
}

const TTL_SEC = 30;

/**
 * État courant d'un compte (statut, version de jeton, téléphone confirmé). Relu depuis Redis
 * (TTL 30 s) puis la base ; `invalidate` est appelé à chaque changement (bannissement, changement
 * de mot de passe, vérification du téléphone…) pour un effet quasi immédiat.
 * Référence : docs/blueprint/04-identity-access.md §2.3.
 */
@Injectable()
export class UserStateService {
  constructor(
    private readonly db: Db,
    private readonly redis: RedisService,
  ) {}

  private key(id: string) {
    return `ustate:${id}`;
  }

  async get(userId: string): Promise<UserState | null> {
    const cached = await this.redis.getJson<UserState>(this.key(userId));
    if (cached) return cached;
    const row = await this.db.one<{
      id: string;
      status: UserState["status"];
      tokenVersion: number;
      phoneVerified: boolean;
    }>(
      `SELECT id, status, token_version, (phone_verified_at IS NOT NULL) AS phone_verified
         FROM core.users WHERE id = $1`,
      [userId],
    );
    if (!row) return null;
    await this.redis.setJson(this.key(userId), row, TTL_SEC);
    return row;
  }

  async invalidate(userId: string): Promise<void> {
    await this.redis.del(this.key(userId));
  }
}
