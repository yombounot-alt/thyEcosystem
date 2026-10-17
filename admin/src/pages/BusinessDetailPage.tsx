import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Link } from "@tanstack/react-router";
import { useState, type ReactElement } from "react";
import { api } from "../api/client";
import type { BusinessEntitlements, EntitlementRow } from "../api/types";
import { useCan } from "../auth/session";
import { PageHeader, RequirePermission } from "../components/Layout";
import { Badge, ErrorMessage, ReasonDialog, Spinner } from "../components/ui";
import { entitlementValue, formatDate } from "../format";

export function BusinessDetailPage({ businessId }: { businessId: string }): ReactElement {
  return (
    <RequirePermission permission="admin:businesses.read">
      <BusinessDetailView businessId={businessId} />
    </RequirePermission>
  );
}

function BusinessDetailView({ businessId }: { businessId: string }) {
  const can = useCan();
  const client = useQueryClient();
  const [editing, setEditing] = useState<EntitlementRow | null>(null);
  const [removing, setRemoving] = useState<EntitlementRow | null>(null);
  const key = ["business-entitlements", businessId];
  const data = useQuery({
    queryKey: key,
    queryFn: () => api<BusinessEntitlements>("GET", `/businesses/${businessId}/entitlements`),
  });

  if (data.isPending) return <Spinner />;
  if (data.isError) return <ErrorMessage error={data.error} />;
  const { business, entitlements } = data.data;
  const manage = can("admin:settings.manage");

  return (
    <>
      <p className="breadcrumb">
        <Link to="/businesses">Entreprises</Link> / {business.name}
      </p>
      <PageHeader title={business.name}>
        <Badge tone="info">Offre {business.planCode}</Badge>
      </PageHeader>
      <section className="panel">
        <h2>Droits de l'offre</h2>
        <p className="muted">
          Une dérogation remplace la valeur de l'offre pour cette entreprise seulement (pilote,
          geste commercial). Elle s'applique immédiatement et est inscrite à l'historique.
        </p>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Droit</th>
                <th scope="col">Offre {business.planCode}</th>
                <th scope="col">Dérogation</th>
                <th scope="col">Effectif</th>
                {manage ? (
                  <th scope="col">
                    <span className="sr-only">Actions</span>
                  </th>
                ) : null}
              </tr>
            </thead>
            <tbody>
              {entitlements.map((e) => {
                const effective = e.overrideActive ? e.overrideValue : e.planValue;
                return (
                  <tr key={e.code}>
                    <td>
                      {e.description}
                      <div className="mono muted small">{e.code}</div>
                    </td>
                    <td>{entitlementValue(e.kind, e.planValue)}</td>
                    <td>
                      {e.hasOverride ? (
                        <>
                          {entitlementValue(e.kind, e.overrideValue)}
                          {e.overrideActive ? null : <Badge tone="warning">expirée</Badge>}
                          <div className="muted small">
                            {e.overrideExpiresAt
                              ? `jusqu'au ${formatDate(e.overrideExpiresAt)}`
                              : "sans échéance"}
                            {e.overrideReason ? ` — ${e.overrideReason}` : ""}
                          </div>
                        </>
                      ) : (
                        <span className="muted">—</span>
                      )}
                    </td>
                    <td>
                      <strong>{entitlementValue(e.kind, effective)}</strong>
                    </td>
                    {manage ? (
                      <td className="row-actions">
                        <button
                          type="button"
                          className="btn btn-small"
                          onClick={() => {
                            setEditing(e);
                          }}
                        >
                          {e.hasOverride ? "Modifier" : "Déroger"}
                        </button>
                        {e.hasOverride ? (
                          <button
                            type="button"
                            className="btn btn-small"
                            onClick={() => {
                              setRemoving(e);
                            }}
                          >
                            Retirer
                          </button>
                        ) : null}
                      </td>
                    ) : null}
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      {editing ? (
        <OverrideDialog
          row={editing}
          onClose={() => {
            setEditing(null);
          }}
          onSave={async (body) => {
            const res = await api<BusinessEntitlements>(
              "PUT",
              `/businesses/${businessId}/entitlements/${editing.code}`,
              body,
            );
            client.setQueryData(key, res);
          }}
        />
      ) : null}
      {removing ? (
        <ReasonDialog
          title="Retirer la dérogation"
          description={`« ${removing.description} » reviendra à la valeur de l'offre ${business.planCode}.`}
          confirmLabel="Retirer"
          danger
          onClose={() => {
            setRemoving(null);
          }}
          onConfirm={async (reason) => {
            const res = await api<BusinessEntitlements>(
              "DELETE",
              `/businesses/${businessId}/entitlements/${removing.code}`,
              { reason },
            );
            client.setQueryData(key, res);
          }}
        />
      ) : null}
    </>
  );
}

interface OverrideBody {
  value: number | null;
  expiresAt?: string;
  reason: string;
}

function OverrideDialog({
  row,
  onClose,
  onSave,
}: {
  row: EntitlementRow;
  onClose: () => void;
  onSave: (body: OverrideBody) => Promise<void>;
}) {
  const boolean = row.kind === "BOOLEAN";
  const initial = row.hasOverride ? row.overrideValue : row.planValue;
  const [unlimited, setUnlimited] = useState(!boolean && initial === null);
  const [value, setValue] = useState(String(initial ?? (boolean ? 1 : "")));
  const [expiresAt, setExpiresAt] = useState(row.overrideExpiresAt?.slice(0, 10) ?? "");
  const parsed = Number(value);
  const valueValid = unlimited || (value !== "" && Number.isInteger(parsed) && parsed >= 0);
  const today = new Date().toISOString().slice(0, 10);

  return (
    <ReasonDialog
      title={`Dérogation : ${row.description}`}
      description={`Valeur de l'offre : ${entitlementValue(row.kind, row.planValue)}.`}
      confirmLabel="Enregistrer"
      canConfirm={valueValid}
      onClose={onClose}
      onConfirm={(reason) =>
        onSave({
          value: unlimited ? null : parsed,
          reason,
          // Fin de journée : la dérogation vaut pendant tout le dernier jour choisi.
          ...(expiresAt ? { expiresAt: new Date(`${expiresAt}T23:59:59`).toISOString() } : {}),
        })
      }
    >
      {boolean ? (
        <label className="field">
          <span>Valeur</span>
          <select
            value={value}
            onChange={(e) => {
              setValue(e.target.value);
            }}
          >
            <option value="1">Oui (activé)</option>
            <option value="0">Non (désactivé)</option>
          </select>
        </label>
      ) : (
        <>
          <label className="checkbox">
            <input
              type="checkbox"
              checked={unlimited}
              onChange={(e) => {
                setUnlimited(e.target.checked);
              }}
            />
            Illimité
          </label>
          {unlimited ? null : (
            <label className="field">
              <span>Nouvelle limite</span>
              <input
                type="number"
                min={0}
                step={1}
                value={value}
                onChange={(e) => {
                  setValue(e.target.value);
                }}
                required
                autoFocus
              />
            </label>
          )}
        </>
      )}
      <label className="field">
        <span>Échéance (facultative)</span>
        <input
          type="date"
          min={today}
          value={expiresAt}
          onChange={(e) => {
            setExpiresAt(e.target.value);
          }}
        />
      </label>
    </ReasonDialog>
  );
}
