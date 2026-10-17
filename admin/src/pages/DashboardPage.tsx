import type { ReactElement } from "react";
import { Link } from "@tanstack/react-router";
import type { Permission } from "../api/types";
import { useCan, useStaff } from "../auth/session";
import { PageHeader } from "../components/Layout";
import { label, ROLE_LABELS } from "../format";

const PERMISSION_LABELS: Record<Permission, string> = {
  "admin:users.read": "Consulter les utilisateurs (numéros masqués)",
  "admin:users.reveal": "Afficher un numéro en clair (motivé, audité)",
  "admin:users.restrict": "Suspendre, réactiver, déconnecter un utilisateur",
  "admin:audit.read": "Consulter le journal d'audit",
  "admin:settings.manage": "Modifier les feature flags et les dérogations d'offre",
  "admin:businesses.read": "Consulter les entreprises et leur offre",
};

const SHORTCUTS: { to: string; title: string; text: string; permission: Permission }[] = [
  {
    to: "/users",
    title: "Utilisateurs",
    text: "Retrouver un compte par numéro, nom ou identifiant.",
    permission: "admin:users.read",
  },
  {
    to: "/businesses",
    title: "Entreprises",
    text: "Voir l'offre d'une entreprise et accorder une dérogation.",
    permission: "admin:businesses.read",
  },
  {
    to: "/audit",
    title: "Journal d'audit",
    text: "Qui a fait quoi, quand, et pourquoi.",
    permission: "admin:audit.read",
  },
  {
    to: "/settings/flags",
    title: "Feature flags",
    text: "Activer progressivement une fonctionnalité.",
    permission: "admin:settings.manage",
  },
];

/**
 * Accueil : ce que le rôle permet, et les raccourcis correspondants. Pas d'indicateurs chiffrés
 * tant qu'aucune source d'agrégats fiable n'existe (pas de chiffres inventés).
 */
export function DashboardPage(): ReactElement {
  const staff = useStaff();
  const can = useCan();
  const shortcuts = SHORTCUTS.filter((s) => can(s.permission));
  return (
    <>
      <PageHeader title={`Bonjour ${staff.fullName}`} />
      <section className="cards">
        {shortcuts.map((s) => (
          <Link key={s.to} to={s.to} className="card card-link">
            <h2>{s.title}</h2>
            <p className="muted">{s.text}</p>
          </Link>
        ))}
      </section>
      <section className="panel">
        <h2>Vos droits</h2>
        <p className="muted">
          Rôle : {staff.roles.map((r) => label(ROLE_LABELS, r)).join(", ") || "aucun"}
        </p>
        {staff.permissions.length === 0 ? (
          <p>Aucun droit n'est attribué à votre compte. Contactez un super-administrateur.</p>
        ) : (
          <ul className="check-list">
            {staff.permissions.map((p) => (
              <li key={p}>{PERMISSION_LABELS[p]}</li>
            ))}
          </ul>
        )}
        <p className="hint">
          Chaque action sensible demande un motif et est inscrite au journal d'audit.
        </p>
      </section>
    </>
  );
}
