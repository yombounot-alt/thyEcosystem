import { useInfiniteQuery } from "@tanstack/react-query";
import { useState, type SyntheticEvent, type ReactElement } from "react";
import { api, query } from "../api/client";
import type { AuditEntry, Page } from "../api/types";
import { PageHeader, RequirePermission } from "../components/Layout";
import { Badge, EmptyState, ErrorMessage, LoadMore, Spinner } from "../components/ui";
import { AUDIT_ACTION_LABELS, formatDateTime, label } from "../format";

interface Filters {
  action: string;
  actorType: string;
  actorId: string;
  targetId: string;
  from: string;
  to: string;
}

const EMPTY: Filters = { action: "", actorType: "", actorId: "", targetId: "", from: "", to: "" };

const ACTOR_LABELS: Record<string, string> = {
  user: "Utilisateur",
  staff: "Staff",
  system: "Système",
};

export function AuditPage(): ReactElement {
  return (
    <RequirePermission permission="admin:audit.read">
      <AuditLog />
    </RequirePermission>
  );
}

/** Dates du formulaire (jour local) → bornes ISO : `to` inclut toute la journée choisie. */
function toParams(f: Filters) {
  const day = (value: string, endOfDay: boolean) => {
    if (!value) return undefined;
    const date = new Date(`${value}T00:00:00`);
    if (endOfDay) date.setDate(date.getDate() + 1);
    return date.toISOString();
  };
  return {
    action: f.action.trim(),
    actorType: f.actorType,
    actorId: f.actorId.trim(),
    targetId: f.targetId.trim(),
    from: day(f.from, false),
    to: day(f.to, true),
  };
}

function AuditLog() {
  const [draft, setDraft] = useState<Filters>(EMPTY);
  const [filters, setFilters] = useState<Filters>(EMPTY);
  const log = useInfiniteQuery({
    queryKey: ["audit", filters],
    queryFn: ({ pageParam }) =>
      api<Page<AuditEntry>>("GET", `/audit${query({ ...toParams(filters), cursor: pageParam })}`),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });

  const set = (key: keyof Filters) => (e: { target: { value: string } }) => {
    setDraft((d) => ({ ...d, [key]: e.target.value }));
  };

  function submit(event: SyntheticEvent) {
    event.preventDefault();
    setFilters(draft);
  }

  const items = log.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <>
      <PageHeader title="Journal d'audit" />
      <form className="filters" onSubmit={submit}>
        <label className="field">
          <span>Action (préfixe)</span>
          <input value={draft.action} onChange={set("action")} placeholder="admin.user" />
        </label>
        <label className="field">
          <span>Auteur</span>
          <select value={draft.actorType} onChange={set("actorType")}>
            <option value="">Tous</option>
            <option value="staff">Staff</option>
            <option value="user">Utilisateur</option>
            <option value="system">Système</option>
          </select>
        </label>
        <label className="field">
          <span>Identifiant de l'auteur</span>
          <input value={draft.actorId} onChange={set("actorId")} />
        </label>
        <label className="field">
          <span>Identifiant de la cible</span>
          <input value={draft.targetId} onChange={set("targetId")} />
        </label>
        <label className="field">
          <span>Du</span>
          <input type="date" value={draft.from} onChange={set("from")} />
        </label>
        <label className="field">
          <span>Au</span>
          <input type="date" value={draft.to} onChange={set("to")} />
        </label>
        <div className="filters-actions">
          <button type="submit" className="btn btn-primary">
            Filtrer
          </button>
          <button
            type="button"
            className="btn"
            onClick={() => {
              setDraft(EMPTY);
              setFilters(EMPTY);
            }}
          >
            Réinitialiser
          </button>
        </div>
      </form>

      {log.isPending ? (
        <Spinner />
      ) : log.isError ? (
        <ErrorMessage error={log.error} />
      ) : items.length === 0 ? (
        <EmptyState>Aucune entrée ne correspond à ces filtres.</EmptyState>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Date</th>
                <th scope="col">Auteur</th>
                <th scope="col">Action</th>
                <th scope="col">Cible</th>
                <th scope="col">Détails</th>
              </tr>
            </thead>
            <tbody>
              {items.map((entry) => (
                <tr key={entry.id}>
                  <td className="nowrap">{formatDateTime(entry.createdAt)}</td>
                  <td>
                    <Badge tone={entry.actorType === "staff" ? "info" : "neutral"}>
                      {label(ACTOR_LABELS, entry.actorType)}
                    </Badge>{" "}
                    {entry.actorLabel ?? <span className="mono small">{entry.actorId ?? "—"}</span>}
                  </td>
                  <td>
                    {label(AUDIT_ACTION_LABELS, entry.action)}
                    <div className="mono muted small">{entry.action}</div>
                  </td>
                  <td>
                    {entry.targetType ? <span className="muted">{entry.targetType} </span> : null}
                    <span className="mono small">{entry.targetId ?? "—"}</span>
                  </td>
                  <td>
                    <Metadata value={entry.metadata} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <LoadMore
        hasMore={log.hasNextPage}
        loading={log.isFetchingNextPage}
        onClick={() => void log.fetchNextPage()}
      />
    </>
  );
}

function Metadata({ value }: { value: Record<string, unknown> }) {
  const keys = Object.keys(value);
  if (keys.length === 0) return <span className="muted">—</span>;
  const reason = typeof value.reason === "string" ? value.reason : null;
  return (
    <>
      {reason ? <p className="reason">« {reason} »</p> : null}
      <details>
        <summary>Données</summary>
        <pre>{JSON.stringify(value, null, 2)}</pre>
      </details>
    </>
  );
}
