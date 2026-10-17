import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState, type ReactElement } from "react";
import { api } from "../api/client";
import type { FeatureFlag } from "../api/types";
import { PageHeader, RequirePermission } from "../components/Layout";
import { Badge, EmptyState, ErrorMessage, ReasonDialog, Spinner } from "../components/ui";
import { formatDateTime } from "../format";

const FLAG_KEY = /^[a-z0-9_.]+$/;
const COUNTRY = /^[A-Z]{2}$/;

export function FlagsPage(): ReactElement {
  return (
    <RequirePermission permission="admin:settings.manage">
      <FlagsList />
    </RequirePermission>
  );
}

function FlagsList() {
  const client = useQueryClient();
  const [editing, setEditing] = useState<FeatureFlag | "new" | null>(null);
  const flags = useQuery({
    queryKey: ["flags"],
    queryFn: () => api<FeatureFlag[]>("GET", "/settings/flags"),
  });

  return (
    <>
      <PageHeader title="Feature flags">
        <button
          type="button"
          className="btn btn-primary"
          onClick={() => {
            setEditing("new");
          }}
        >
          Nouveau flag
        </button>
      </PageHeader>
      <p className="muted">
        Un flag active une fonctionnalité pour une part des utilisateurs (répartition stable par
        utilisateur), éventuellement limitée à certains pays. Les applications le lisent à leur
        prochain rafraîchissement.
      </p>
      {flags.isPending ? (
        <Spinner />
      ) : flags.isError ? (
        <ErrorMessage error={flags.error} />
      ) : flags.data.length === 0 ? (
        <EmptyState>Aucun flag défini.</EmptyState>
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th scope="col">Flag</th>
                <th scope="col">État</th>
                <th scope="col">Déploiement</th>
                <th scope="col">Pays</th>
                <th scope="col">Modifié le</th>
                <th scope="col">
                  <span className="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
              {flags.data.map((f) => (
                <tr key={f.key}>
                  <td>
                    <span className="mono">{f.key}</span>
                    <div className="muted small">{f.description}</div>
                  </td>
                  <td>
                    <Badge tone={f.enabled ? "success" : "neutral"}>
                      {f.enabled ? "Activé" : "Désactivé"}
                    </Badge>
                  </td>
                  <td>{f.rolloutPercent} %</td>
                  <td>{f.countries?.join(", ") ?? "Tous"}</td>
                  <td>{formatDateTime(f.updatedAt)}</td>
                  <td className="row-actions">
                    <button
                      type="button"
                      className="btn btn-small"
                      onClick={() => {
                        setEditing(f);
                      }}
                    >
                      Modifier
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {editing ? (
        <FlagDialog
          flag={editing === "new" ? null : editing}
          onClose={() => {
            setEditing(null);
          }}
          onSaved={() => client.invalidateQueries({ queryKey: ["flags"] })}
        />
      ) : null}
    </>
  );
}

function FlagDialog({
  flag,
  onClose,
  onSaved,
}: {
  flag: FeatureFlag | null;
  onClose: () => void;
  onSaved: () => Promise<void>;
}) {
  const [key, setKey] = useState(flag?.key ?? "");
  const [description, setDescription] = useState(flag?.description ?? "");
  const [enabled, setEnabled] = useState(flag?.enabled ?? false);
  const [rollout, setRollout] = useState(String(flag?.rolloutPercent ?? 0));
  const [countries, setCountries] = useState(flag?.countries?.join(", ") ?? "");

  const countryList = countries
    .split(/[\s,;]+/)
    .map((c) => c.trim().toUpperCase())
    .filter(Boolean);
  const percent = Number(rollout);
  const errors = [
    !FLAG_KEY.test(key) ? "Clé : minuscules, chiffres, « . » et « _ » uniquement." : null,
    description.trim().length === 0 ? "Description requise." : null,
    !Number.isInteger(percent) || percent < 0 || percent > 100
      ? "Déploiement : un entier de 0 à 100."
      : null,
    countryList.some((c) => !COUNTRY.test(c)) ? "Pays : codes ISO à 2 lettres (ex. GN, SN)." : null,
  ].filter((e): e is string => e !== null);

  return (
    <ReasonDialog
      title={flag ? `Modifier ${flag.key}` : "Nouveau flag"}
      description="La modification s'applique immédiatement ; l'ancienne et la nouvelle valeur sont conservées au journal d'audit."
      confirmLabel="Enregistrer"
      canConfirm={errors.length === 0}
      onClose={onClose}
      onConfirm={async (reason) => {
        await api("PUT", `/settings/flags/${encodeURIComponent(key)}`, {
          description: description.trim(),
          enabled,
          rolloutPercent: percent,
          ...(countryList.length ? { countries: countryList } : {}),
          reason,
        });
        await onSaved();
      }}
    >
      <label className="field">
        <span>Clé</span>
        <input
          className="mono"
          value={key}
          onChange={(e) => {
            setKey(e.target.value.trim());
          }}
          readOnly={flag !== null}
          placeholder="module.fonctionnalite"
          autoFocus={flag === null}
        />
      </label>
      <label className="field">
        <span>Description</span>
        <input
          value={description}
          maxLength={300}
          onChange={(e) => {
            setDescription(e.target.value);
          }}
        />
      </label>
      <label className="checkbox">
        <input
          type="checkbox"
          checked={enabled}
          onChange={(e) => {
            setEnabled(e.target.checked);
          }}
        />
        Activé
      </label>
      <label className="field">
        <span>Déploiement (% des utilisateurs)</span>
        <input
          type="number"
          min={0}
          max={100}
          step={1}
          value={rollout}
          onChange={(e) => {
            setRollout(e.target.value);
          }}
        />
      </label>
      <label className="field">
        <span>Pays (vide = tous)</span>
        <input
          value={countries}
          onChange={(e) => {
            setCountries(e.target.value);
          }}
          placeholder="GN, SN"
        />
      </label>
      {errors.length > 0 && (key || description) ? (
        <ul className="form-errors">
          {errors.map((e) => (
            <li key={e}>{e}</li>
          ))}
        </ul>
      ) : null}
    </ReasonDialog>
  );
}
