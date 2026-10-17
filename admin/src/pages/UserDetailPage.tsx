import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { useState, type ReactElement } from "react";
import { api } from "../api/client";
import type { UserDetail } from "../api/types";
import { useCan } from "../auth/session";
import { PageHeader, RequirePermission } from "../components/Layout";
import { Badge, EmptyState, ErrorMessage, ReasonDialog, Spinner } from "../components/ui";
import { formatDate, formatDateTime, label, ROLE_LABELS, USER_STATUS_LABELS } from "../format";

type Action = "reveal" | "suspend" | "reactivate" | "revoke";

export function UserDetailPage({ userId }: { userId: string }): ReactElement {
  return (
    <RequirePermission permission="admin:users.read">
      <UserDetailView userId={userId} />
    </RequirePermission>
  );
}

function UserDetailView({ userId }: { userId: string }) {
  const can = useCan();
  const client = useQueryClient();
  const [action, setAction] = useState<Action | null>(null);
  const [revealed, setRevealed] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const user = useQuery({
    queryKey: ["user", userId],
    queryFn: () => api<UserDetail>("GET", `/users/${userId}`),
  });

  if (user.isPending) return <Spinner />;
  if (user.isError) return <ErrorMessage error={user.error} />;
  const u = user.data;
  const suspended = u.status === "SUSPENDED";
  const close = () => {
    setAction(null);
  };

  async function refresh(message: string) {
    setNotice(message);
    await client.invalidateQueries({ queryKey: ["user", userId] });
    await client.invalidateQueries({ queryKey: ["users"] });
  }

  return (
    <>
      <p className="breadcrumb">
        <Link to="/users">Utilisateurs</Link> / {u.fullName ?? "Sans nom"}
      </p>
      <PageHeader title={u.fullName ?? "Sans nom"}>
        <Badge tone={u.status === "ACTIVE" ? "success" : suspended ? "warning" : "danger"}>
          {label(USER_STATUS_LABELS, u.status)}
        </Badge>
      </PageHeader>

      {notice ? (
        <div className="alert alert-success" role="status">
          {notice}
        </div>
      ) : null}

      <section className="panel">
        <dl className="facts">
          <dt>Numéro</dt>
          <dd className="mono">
            {revealed ?? u.phoneMasked}
            {!revealed && can("admin:users.reveal") ? (
              <button
                type="button"
                className="btn btn-link"
                onClick={() => {
                  setAction("reveal");
                }}
              >
                Afficher en clair
              </button>
            ) : null}
          </dd>
          <dt>Identifiant</dt>
          <dd className="mono">{u.id}</dd>
          <dt>Langue</dt>
          <dd>{u.locale}</dd>
          <dt>Numéro vérifié le</dt>
          <dd>{formatDateTime(u.phoneVerifiedAt)}</dd>
          <dt>Inscrit le</dt>
          <dd>{formatDateTime(u.createdAt)}</dd>
          <dt>Dernière connexion</dt>
          <dd>{formatDateTime(u.lastLoginAt)}</dd>
        </dl>
        {can("admin:users.restrict") ? (
          <div className="actions">
            {u.status === "BANNED" ? null : suspended ? (
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => {
                  setAction("reactivate");
                }}
              >
                Réactiver le compte
              </button>
            ) : (
              <button
                type="button"
                className="btn btn-danger"
                onClick={() => {
                  setAction("suspend");
                }}
              >
                Suspendre le compte
              </button>
            )}
            <button
              type="button"
              className="btn"
              onClick={() => {
                setAction("revoke");
              }}
              disabled={u.activeSessions.length === 0}
            >
              Déconnecter tous les appareils
            </button>
          </div>
        ) : null}
      </section>

      <section className="panel">
        <h2>Entreprises</h2>
        {u.businesses.length === 0 ? (
          <EmptyState>Membre d'aucune entreprise.</EmptyState>
        ) : (
          <ul className="list">
            {u.businesses.map((b) => (
              <li key={b.id}>
                {can("admin:businesses.read") ? (
                  <Link to="/businesses/$businessId" params={{ businessId: b.id }}>
                    {b.name}
                  </Link>
                ) : (
                  b.name
                )}{" "}
                <span className="muted">
                  — {label(ROLE_LABELS, b.roleCode)}, depuis le {formatDate(b.joinedAt)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="panel">
        <h2>Appareils connectés ({u.activeSessions.length})</h2>
        {u.activeSessions.length === 0 ? (
          <EmptyState>Aucune session active.</EmptyState>
        ) : (
          <ul className="list">
            {u.activeSessions.map((s) => (
              <li key={s.id}>
                {s.userAgent ?? "Appareil inconnu"}{" "}
                <span className="muted">
                  — connecté le {formatDateTime(s.startedAt)}, actif le{" "}
                  {formatDateTime(s.lastRefreshAt)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="panel">
        <h2>Connexions récentes</h2>
        {u.recentLogins.length === 0 ? (
          <EmptyState>Aucune connexion enregistrée.</EmptyState>
        ) : (
          <ul className="list">
            {u.recentLogins.map((l) => (
              <li key={l.at}>
                {formatDateTime(l.at)}{" "}
                <Badge tone={l.success ? "success" : "danger"}>
                  {l.success ? "Réussie" : "Échouée"}
                </Badge>
              </li>
            ))}
          </ul>
        )}
      </section>

      {action === "reveal" ? (
        <ReasonDialog
          title="Afficher le numéro en clair"
          description="Le numéro complet s'affichera sur cet écran. Cette consultation est inscrite au journal d'audit avec votre motif."
          confirmLabel="Afficher"
          onClose={close}
          onConfirm={async (reason) => {
            const res = await api<{ phone: string }>("POST", `/users/${userId}/reveal-phone`, {
              reason,
            });
            setRevealed(res.phone);
          }}
        />
      ) : null}
      {action === "suspend" ? (
        <ReasonDialog
          title="Suspendre le compte"
          description="L'utilisateur garde l'accès en lecture mais ne peut plus rien modifier, jusqu'à réactivation."
          confirmLabel="Suspendre"
          danger
          onClose={close}
          onConfirm={async (reason) => {
            await api("POST", `/users/${userId}/suspend`, { reason });
            await refresh("Compte suspendu.");
          }}
        />
      ) : null}
      {action === "reactivate" ? (
        <ReasonDialog
          title="Réactiver le compte"
          description="L'utilisateur retrouve l'usage normal de l'application."
          confirmLabel="Réactiver"
          onClose={close}
          onConfirm={async (reason) => {
            await api("POST", `/users/${userId}/reactivate`, { reason });
            await refresh("Compte réactivé.");
          }}
        />
      ) : null}
      {action === "revoke" ? (
        <ReasonDialog
          title="Déconnecter tous les appareils"
          description="Toutes les sessions sont fermées immédiatement ; l'utilisateur devra se reconnecter par SMS."
          confirmLabel="Déconnecter"
          danger
          onClose={close}
          onConfirm={async (reason) => {
            const res = await api<{ revokedTokens: number }>(
              "POST",
              `/users/${userId}/revoke-sessions`,
              { reason },
            );
            await refresh(
              `Appareils déconnectés (${String(res.revokedTokens)} jeton(s) révoqué(s)).`,
            );
          }}
        />
      ) : null}
    </>
  );
}
