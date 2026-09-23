import { Prisma } from "@prisma/client";

/**
 * Violation d'unicité (P2002), éventuellement limitée à une colonne.
 *
 * Sous RLS, PostgreSQL retire le détail « Key (colonnes)=(valeurs) » de l'erreur pour ne rien
 * divulguer d'une ligne que l'appelant ne verrait pas : Prisma a alors `meta.target` absent ou null.
 * Quand la cible est inconnue on répond donc « peut-être cette colonne » (true) ; l'appelant ne doit
 * jamais s'y fier seul, mais revérifier par une lecture (ex. retrouver la vente par son
 * clientRequestId) — ce que font déjà les deux usages.
 */
export function isUniqueViolation(error: unknown, column?: string): boolean {
  if (!(error instanceof Prisma.PrismaClientKnownRequestError) || error.code !== "P2002") {
    return false;
  }
  const target = error.meta?.target as string[] | string | null | undefined;
  if (!column || target == null) return true;
  return target.includes(column);
}
