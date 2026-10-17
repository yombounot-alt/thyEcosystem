import { useInfiniteQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { useState, type SyntheticEvent, type ReactElement } from "react";
import { api, query } from "../api/client";
import type { Page, UserListItem } from "../api/types";
import { PageHeader, RequirePermission } from "../components/Layout";
import { Badge, EmptyState, ErrorMessage, LoadMore, Spinner } from "../components/ui";
import { formatDate, formatDateTime, label, USER_STATUS_LABELS } from "../format";

export function UsersPage(): ReactElement {
  return (
    <RequirePermission permission="admin:users.read">
      <UsersList />
    </RequirePermission>
  );
}

function UsersList() {
  const [input, setInput] = useState("");
  const [term, setTerm] = useState("");
  const users = useInfiniteQuery({
    queryKey: ["users", term],
    queryFn: ({ pageParam }) =>
      api<Page<UserListItem>>("GET", `/users${query({ q: term, cursor: pageParam })}`),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });

  function submit(event: SyntheticEvent) {
    event.preventDefault();
    setTerm(input.trim());
  }

  const items = users.data?.pages.flatMap((p) => p.items) ?? [];

  return (
    <>
      <PageHeader title="Utilisateurs" />
      <form className="toolbar" role="search" onSubmit={submit}>
        <label className="field field-grow">
          <span>Numéro (ou début), nom, ou identifiant</span>
          <input
            type="search"
            value={input}
            onChange={(e) => {
              setInput(e.target.value);
            }}
            placeholder="+224 62…"
          />
        </label>
        <button type="submit" className="btn btn-primary">
          Rechercher
        </button>
      </form>

      {users.isPending ? (
        <Spinner />
      ) : users.isError ? (
        <ErrorMessage error={users.error} />
      ) : items.length === 0 ? (
        <EmptyState>Aucun utilisateur ne correspond à cette recherche.</EmptyState>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Nom</th>
                <th scope="col">Numéro</th>
                <th scope="col">Statut</th>
                <th scope="col">Inscrit le</th>
                <th scope="col">Dernière connexion</th>
              </tr>
            </thead>
            <tbody>
              {items.map((u) => (
                <tr key={u.id}>
                  <td>
                    <Link to="/users/$userId" params={{ userId: u.id }}>
                      {u.fullName ?? "Sans nom"}
                    </Link>
                  </td>
                  <td className="mono">{u.phoneMasked}</td>
                  <td>
                    <Badge tone={u.status === "ACTIVE" ? "success" : "warning"}>
                      {label(USER_STATUS_LABELS, u.status)}
                    </Badge>
                  </td>
                  <td>{formatDate(u.createdAt)}</td>
                  <td>{formatDateTime(u.lastLoginAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <LoadMore
        hasMore={users.hasNextPage}
        loading={users.isFetchingNextPage}
        onClick={() => void users.fetchNextPage()}
      />
    </>
  );
}
