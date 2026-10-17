import { useQueryClient } from "@tanstack/react-query";
import { Link, Outlet } from "@tanstack/react-router";
import { useState, type ReactElement, type ReactNode } from "react";
import { api, setCsrfToken } from "../api/client";
import type { Permission } from "../api/types";
import { SESSION_KEY, useCan, useStaff } from "../auth/session";
import { label, ROLE_LABELS } from "../format";
import { applyTheme, readTheme, type ThemePreference } from "./theme";

const NAV: { to: string; label: string; permission?: Permission }[] = [
  { to: "/", label: "Tableau de bord" },
  { to: "/users", label: "Utilisateurs", permission: "admin:users.read" },
  { to: "/businesses", label: "Entreprises", permission: "admin:businesses.read" },
  { to: "/audit", label: "Journal d'audit", permission: "admin:audit.read" },
  { to: "/settings/flags", label: "Feature flags", permission: "admin:settings.manage" },
];

export function Layout(): ReactElement {
  const staff = useStaff();
  const can = useCan();
  const client = useQueryClient();
  const [theme, setTheme] = useState<ThemePreference>(readTheme);

  async function logout() {
    await api("POST", "/auth/logout").catch(() => undefined);
    setCsrfToken(null);
    client.clear();
    await client.invalidateQueries({ queryKey: SESSION_KEY });
  }

  return (
    <div className="shell">
      <a className="skip-link" href="#main">
        Aller au contenu
      </a>
      <aside className="sidebar">
        <p className="brand">THY Admin</p>
        <nav aria-label="Navigation principale">
          <ul>
            {NAV.filter((item) => !item.permission || can(item.permission)).map((item) => (
              <li key={item.to}>
                <Link
                  to={item.to}
                  activeOptions={{ exact: item.to === "/" }}
                  activeProps={{ className: "active", "aria-current": "page" }}
                >
                  {item.label}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </aside>
      <div className="content">
        <header className="topbar">
          <div>
            <strong>{staff.fullName}</strong>
            <span className="muted">
              {" "}
              · {staff.roles.map((r) => label(ROLE_LABELS, r)).join(", ")}
            </span>
          </div>
          <div className="topbar-actions">
            <label className="theme-select">
              <span className="sr-only">Thème</span>
              <select
                value={theme}
                onChange={(e) => {
                  const value = e.target.value as ThemePreference;
                  setTheme(value);
                  applyTheme(value);
                }}
              >
                <option value="system">Thème du système</option>
                <option value="light">Clair</option>
                <option value="dark">Sombre</option>
              </select>
            </label>
            <button type="button" className="btn" onClick={logout}>
              Se déconnecter
            </button>
          </div>
        </header>
        <main id="main" className="page">
          <Outlet />
        </main>
      </div>
    </div>
  );
}

/** Garde d'écran : le serveur refuse de toute façon (403), ceci évite d'afficher un écran vide. */
export function RequirePermission({
  permission,
  children,
}: {
  permission: Permission;
  children: ReactNode;
}) {
  const can = useCan();
  if (can(permission)) return children;
  return (
    <div className="alert alert-warning" role="alert">
      Votre rôle ne donne pas accès à cette page.
    </div>
  );
}

export function PageHeader({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="page-header">
      <h1>{title}</h1>
      {children}
    </div>
  );
}
