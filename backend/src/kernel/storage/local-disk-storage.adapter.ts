import { Inject, Injectable } from "@nestjs/common";
import { promises as fs } from "node:fs";
import path from "node:path";
import { CONFIG, type AppConfig } from "../config/config.js";
import type { StoragePort } from "./storage.port.js";

@Injectable()
export class LocalDiskStorageAdapter implements StoragePort {
  private readonly root: string;

  constructor(@Inject(CONFIG) cfg: AppConfig) {
    this.root = path.resolve(cfg.storage.localPath);
  }

  async put(key: string, body: Buffer): Promise<void> {
    const file = this.resolve(key);
    await fs.mkdir(path.dirname(file), { recursive: true });
    await fs.writeFile(file, body);
  }

  async get(key: string): Promise<Buffer | null> {
    try {
      return await fs.readFile(this.resolve(key));
    } catch (error) {
      if ((error as NodeJS.ErrnoException).code === "ENOENT") return null;
      throw error;
    }
  }

  async delete(key: string): Promise<void> {
    await fs.rm(this.resolve(key), { force: true });
  }

  /** Les clés sont générées côté serveur, mais l'adaptateur refuse quand même toute clé qui sort de sa racine. */
  private resolve(key: string): string {
    const file = path.resolve(this.root, key);
    if (file !== this.root && !file.startsWith(this.root + path.sep)) {
      throw new Error(`Clé de stockage invalide : ${key}`);
    }
    return file;
  }
}
