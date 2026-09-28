import { Module } from "@nestjs/common";
import { CONFIG, type AppConfig } from "../config/config.js";
import { LocalDiskStorageAdapter } from "./local-disk-storage.adapter.js";
import { S3StorageAdapter } from "./s3-storage.adapter.js";
import { STORAGE_PROVIDER } from "./storage.port.js";

/** Adaptateur choisi par configuration (`STORAGE_DRIVER`) : disque local (dev) ou S3/GCS. */
@Module({
  providers: [
    {
      provide: STORAGE_PROVIDER,
      inject: [CONFIG],
      useFactory: (cfg: AppConfig) =>
        cfg.storage.driver === "s3" ? new S3StorageAdapter(cfg) : new LocalDiskStorageAdapter(cfg),
    },
  ],
  exports: [STORAGE_PROVIDER],
})
export class StorageModule {}
