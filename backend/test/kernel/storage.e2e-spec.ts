import { randomUUID } from "node:crypto";
import { loadConfig, type AppConfig } from "../../src/kernel/config/config.js";
import { LocalDiskStorageAdapter } from "../../src/kernel/storage/local-disk-storage.adapter.js";
import { S3StorageAdapter } from "../../src/kernel/storage/s3-storage.adapter.js";
import type { StoragePort } from "../../src/kernel/storage/storage.port.js";

/**
 * Contrat du port de stockage, exécuté à l'identique sur chaque adaptateur : ce que les modules
 * métier attendent (photos, logos, preuves) doit se comporter pareil en local et sur S3/GCS.
 * S3 vise le stockage de la pile de dev (RustFS, bucket `thy-test` créé par le service `s3-init`) ;
 * surcharger S3_TEST_* pour viser un autre point d'accès.
 */
function s3Config(): AppConfig {
  return loadConfig({
    NODE_ENV: "test",
    STORAGE_DRIVER: "s3",
    S3_ENDPOINT: process.env.S3_TEST_ENDPOINT ?? "http://localhost:9002",
    S3_BUCKET: process.env.S3_TEST_BUCKET ?? "thy-test",
    S3_ACCESS_KEY_ID: process.env.S3_TEST_ACCESS_KEY_ID ?? "thy_s3",
    S3_SECRET_ACCESS_KEY: process.env.S3_TEST_SECRET_ACCESS_KEY ?? "changeme123",
  });
}

const adapters: [string, () => StoragePort][] = [
  [
    "disque local",
    () =>
      new LocalDiskStorageAdapter(
        loadConfig({ NODE_ENV: "test", STORAGE_LOCAL_PATH: "./uploads-test" }),
      ),
  ],
  ["S3", () => new S3StorageAdapter(s3Config())],
];

describe.each(adapters)("StoragePort — %s", (_name, make) => {
  let storage: StoragePort;
  const prefix = `contract/${randomUUID()}`;

  beforeAll(() => {
    storage = make();
  });
  afterAll(() => {
    (storage as Partial<{ onModuleDestroy(): void }>).onModuleDestroy?.();
  });

  it("restitue exactement les octets stockés (binaire compris)", async () => {
    const key = `${prefix}/photo.jpg`;
    const body = Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x01, 0x80, 0xfe, 0x0a, 0x0d]);
    await storage.put(key, body);
    const read = await storage.get(key);
    expect(read).not.toBeNull();
    expect(read!.equals(body)).toBe(true);
  });

  it("remplace un objet existant", async () => {
    const key = `${prefix}/logo.png`;
    await storage.put(key, Buffer.from("v1"));
    await storage.put(key, Buffer.from("version-2"));
    expect((await storage.get(key))!.toString()).toBe("version-2");
  });

  it("une clé absente renvoie null (pas d'erreur)", async () => {
    expect(await storage.get(`${prefix}/nope.webp`)).toBeNull();
  });

  it("supprime ; supprimer deux fois ou une clé absente n'est pas une erreur", async () => {
    const key = `${prefix}/proof.webp`;
    await storage.put(key, Buffer.from("x"));
    await storage.delete(key);
    expect(await storage.get(key)).toBeNull();
    await expect(storage.delete(key)).resolves.toBeUndefined();
  });

  it("gère un fichier de la taille maximale acceptée (3 Mo)", async () => {
    const key = `${prefix}/big.jpg`;
    const body = Buffer.alloc(3 * 1024 * 1024, 7);
    await storage.put(key, body);
    expect((await storage.get(key))!.length).toBe(body.length);
    await storage.delete(key);
  });

  it("refuse une clé qui tenterait de sortir de son espace", async () => {
    await expect(storage.put("../escape.txt", Buffer.from("x"))).rejects.toThrow(/invalide/);
  });
});
