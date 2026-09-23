export const STORAGE_PROVIDER = Symbol("STORAGE_PROVIDER");

/**
 * Où vivent les fichiers téléversés (photos de produits, logos, preuves de paiement…).
 * Port du kernel (docs/blueprint/02-architecture.md, tier 1) : les modules ne manipulent que des
 * clés opaques. Seul l'adaptateur disque local existe pour l'instant (développement) ; l'adaptateur
 * S3/GCS (ADR-012) le remplacera sans toucher au code métier — la configuration de production
 * REFUSE le disque local (voir config.ts).
 */
export interface StoragePort {
  /** Stocke [body] sous [key], en remplaçant l'existant. */
  put(key: string, body: Buffer): Promise<void>;
  /** Les octets stockés, ou null si rien n'existe sous [key]. */
  get(key: string): Promise<Buffer | null>;
  /** Supprime [key] ; une clé absente n'est pas une erreur. */
  delete(key: string): Promise<void>;
}
