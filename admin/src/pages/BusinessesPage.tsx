import { useQuery } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { useState, type SyntheticEvent, type ReactElement } from "react";
import { api, query } from "../api/client";
import type { BusinessListItem } from "../api/types";
import { PageHeader, RequirePermission } from "../components/Layout";
import { Badge, EmptyState, ErrorMessage, Spinner } from "../components/ui";
import { formatDate, label, SUBSCRIPTION_STATUS_LABELS } from "../format";

export function BusinessesPage(): ReactElement {
  return (
    <RequirePermission permission="admin:businesses.read">
      <BusinessesList />
    </RequirePermission>
  );
}

function BusinessesList() {
  const [input, setInput] = useState("");
  const [term, setTerm] = useState("");
  const businesses = useQuery({
    queryKey: ["businesses", term],
    queryFn: () => api<BusinessListItem[]>("GET", `/businesses${query({ q: term })}`),
  });

  function submit(event: SyntheticEvent) {
    event.preventDefault();
    setTerm(input.trim());
  }

  return (
    <>
      <PageHeader title="Entreprises" />
      <form className="toolbar" role="search" onSubmit={submit}>
        <label className="field field-grow">
          <span>Nom ou identifiant</span>
          <input
            type="search"
            value={input}
            onChange={(e) => {
              setInput(e.target.value);
            }}
          />
        </label>
        <button type="submit" className="btn btn-primary">
          Rechercher
        </button>
      </form>
      {businesses.isPending ? (
        <Spinner />
      ) : businesses.isError ? (
        <ErrorMessage error={businesses.error} />
      ) : businesses.data.length === 0 ? (
        <EmptyState>Aucune entreprise ne correspond à cette recherche.</EmptyState>
      ) : (
        <>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th scope="col">Nom</th>
                  <th scope="col">Pays</th>
                  <th scope="col">Offre</th>
                  <th scope="col">Membres</th>
                  <th scope="col">Créée le</th>
                </tr>
              </thead>
              <tbody>
                {businesses.data.map((b) => (
                  <tr key={b.id}>
                    <td>
                      <Link to="/businesses/$businessId" params={{ businessId: b.id }}>
                        {b.name}
                      </Link>
                    </td>
                    <td>{b.country}</td>
                    <td>
                      <Badge tone={b.planCode === "FREE" || !b.planCode ? "neutral" : "info"}>
                        {b.planCode ?? "FREE"}
                      </Badge>{" "}
                      {b.subscriptionStatus && b.subscriptionStatus !== "ACTIVE" ? (
                        <span className="muted">
                          {label(SUBSCRIPTION_STATUS_LABELS, b.subscriptionStatus)}
                        </span>
                      ) : null}
                    </td>
                    <td>{b.members}</td>
                    <td>{formatDate(b.createdAt)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {businesses.data.length === 30 ? (
            <p className="hint">
              Seules les 30 plus récentes sont affichées : affinez la recherche.
            </p>
          ) : null}
        </>
      )}
    </>
  );
}
