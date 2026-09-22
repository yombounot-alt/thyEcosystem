import { Controller, Get, ServiceUnavailableException } from "@nestjs/common";
import { Public } from "../kernel/auth/auth-types.js";
import { Db } from "../kernel/db/db.service.js";
import { RedisService } from "../kernel/redis/redis.service.js";

@Controller("health")
export class HealthController {
  constructor(
    private readonly db: Db,
    private readonly redis: RedisService,
  ) {}

  @Get("live")
  @Public()
  live() {
    return { status: "ok" };
  }

  /** Prêt = base ET Redis joignables. Aucun détail interne dans la réponse. */
  @Get("ready")
  @Public()
  async ready() {
    const [dbOk, redisOk] = await Promise.all([
      this.db.query("SELECT 1").then(
        () => true,
        () => false,
      ),
      this.redis.ping(),
    ]);
    if (!dbOk || !redisOk)
      throw new ServiceUnavailableException({ status: "unavailable", db: dbOk, redis: redisOk });
    return { status: "ok" };
  }
}
