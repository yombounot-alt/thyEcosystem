/**
 * Filtre de confidentialité appliqué à CHAQUE événement avant envoi à Sentry (`beforeSend`).
 * Liste blanche plutôt que liste noire : seul ce qui est explicitement sûr repart.
 *   - requête : méthode seulement (ni URL réelle, ni en-têtes, ni corps, ni cookies, ni query) ;
 *   - utilisateur : identifiant technique seulement (ni téléphone, ni IP, ni e-mail) ;
 *   - fils d'Ariane et données « extra » : supprimés (URLs, logs console, valeurs quelconques).
 * Référence : docs/blueprint/11-security.md §7 (« aucune PII dans les journaux »).
 */
export interface ScrubbableEvent {
  request?: object;
  user?: object;
  breadcrumbs?: unknown;
  extra?: unknown;
  server_name?: unknown;
}

export function scrubEvent<T extends ScrubbableEvent>(event: T): T {
  const method = (event.request as { method?: unknown } | undefined)?.method;
  const userId = (event.user as { id?: unknown } | undefined)?.id;
  const clean: T = { ...event };
  if (event.request) clean.request = typeof method === "string" ? { method } : {};
  if (event.user) clean.user = typeof userId === "string" ? { id: userId } : {};
  delete clean.breadcrumbs;
  delete clean.extra;
  delete clean.server_name; // nom d'hôte de l'instance : sans intérêt, parfois révélateur
  return clean;
}
