import { Inject, Injectable, OnModuleDestroy } from "@nestjs/common";
import { Redis } from "ioredis";
import { randomUUID } from "node:crypto";
import { CONFIG, type AppConfig } from "../config/config.js";

const RELEASE_LUA = `if redis.call('get', KEYS[1]) == ARGV[1] then return redis.call('del', KEYS[1]) else return 0 end`;

@Injectable()
export class RedisService implements OnModuleDestroy {
  readonly client: Redis;

  constructor(@Inject(CONFIG) private readonly cfg: AppConfig) {
    this.client = new Redis(cfg.redisUrl, {
      maxRetriesPerRequest: 2,
      enableOfflineQueue: false,
      lazyConnect: false,
    });
    this.client.on("error", () => undefined); // l'indisponibilité est gérée par les appelants (fail-open / fail-closed)
  }

  duplicate(): Redis {
    const c = this.client.duplicate();
    c.on("error", () => undefined);
    return c;
  }

  async ping(): Promise<boolean> {
    try {
      return (await this.client.ping()) === "PONG";
    } catch {
      return false;
    }
  }

  /** Compteur à fenêtre fixe. Retourne la valeur et le TTL restant (s). */
  async incrWindow(key: string, windowSec: number): Promise<{ count: number; ttl: number }> {
    const res = await this.client.multi().incr(key).expire(key, windowSec, "NX").ttl(key).exec();
    if (!res) throw new Error("redis multi failed");
    return { count: Number(res[0]![1]), ttl: Math.max(1, Number(res[2]![1])) };
  }

  async getJson<T>(key: string): Promise<T | null> {
    try {
      const v = await this.client.get(key);
      return v ? (JSON.parse(v) as T) : null;
    } catch {
      return null;
    }
  }

  async setJson(key: string, value: unknown, ttlSec: number): Promise<void> {
    try {
      await this.client.set(key, JSON.stringify(value), "EX", ttlSec);
    } catch {
      /* cache : best effort */
    }
  }

  async del(...keys: string[]): Promise<void> {
    try {
      if (keys.length) await this.client.del(...keys);
    } catch {
      /* best effort */
    }
  }

  /** Verrou distribué (jobs planifiés : une seule instance exécute). Retourne une fonction de libération, ou null. */
  async lock(name: string, ttlMs: number): Promise<(() => Promise<void>) | null> {
    const token = randomUUID();
    const key = `lock:${name}`;
    try {
      const ok = await this.client.set(key, token, "PX", ttlMs, "NX");
      if (ok !== "OK") return null;
      return async () => {
        await this.client.eval(RELEASE_LUA, 1, key, token).catch(() => undefined);
      };
    } catch {
      return null;
    }
  }

  async onModuleDestroy(): Promise<void> {
    await this.client.quit().catch(() => this.client.disconnect());
  }
}
