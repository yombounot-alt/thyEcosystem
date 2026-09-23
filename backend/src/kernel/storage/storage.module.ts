import { Module } from "@nestjs/common";
import { LocalDiskStorageAdapter } from "./local-disk-storage.adapter.js";
import { STORAGE_PROVIDER } from "./storage.port.js";

@Module({
  providers: [{ provide: STORAGE_PROVIDER, useClass: LocalDiskStorageAdapter }],
  exports: [STORAGE_PROVIDER],
})
export class StorageModule {}
