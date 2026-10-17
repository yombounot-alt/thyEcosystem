import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect } from "react";
import { api, onUnauthorized, setCsrfToken } from "../api/client";
import type { Permission, StaffSession } from "../api/types";

export const SESSION_KEY = ["session"] as const;

/**
 * Session staff courante. Chaque lecture renouvelle le jeton anti-CSRF côté serveur : on ne la
 * relit donc jamais en tâche de fond (une action en cours porterait sinon un jeton périmé).
 */
export function useSession() {
  const client = useQueryClient();
  const query = useQuery({
    queryKey: SESSION_KEY,
    queryFn: async () => {
      const session = await api<StaffSession>("GET", "/auth/session");
      setCsrfToken(session.csrfToken);
      return session;
    },
    retry: false,
    staleTime: Infinity,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  });

  // Une requête qui découvre une session expirée renvoie tout le monde à l'écran de connexion.
  useEffect(
    () =>
      onUnauthorized(() => {
        setCsrfToken(null);
        void client.invalidateQueries({ queryKey: SESSION_KEY });
      }),
    [client],
  );

  return query;
}

/** Session établie (double authentification faite) — n'appeler que sous le portail. */
export function useStaff(): StaffSession["staff"] {
  const client = useQueryClient();
  const session = client.getQueryData<StaffSession>(SESSION_KEY);
  if (!session) throw new Error("useStaff() hors d'une session établie");
  return session.staff;
}

export function useCan(): (permission: Permission) => boolean {
  const staff = useStaff();
  return (permission) => staff.permissions.includes(permission);
}
