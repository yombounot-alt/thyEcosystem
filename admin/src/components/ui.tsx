import { useEffect, useId, useRef, useState, type SyntheticEvent, type ReactNode } from "react";
import { ApiError } from "../api/client";

export function Spinner({ label = "Chargement…" }: { label?: string }) {
  return (
    <div className="spinner" role="status">
      <span className="spinner-dot" aria-hidden="true" />
      {label}
    </div>
  );
}

/** Message d'erreur lisible, avec la référence de requête pour le support technique. */
export function ErrorMessage({ error }: { error: unknown }) {
  if (!error) return null;
  const message = error instanceof Error ? error.message : "Une erreur inattendue est survenue.";
  const requestId = error instanceof ApiError ? error.requestId : undefined;
  return (
    <div className="alert alert-danger" role="alert">
      {message}
      {requestId ? <span className="alert-ref">Réf. {requestId}</span> : null}
    </div>
  );
}

export function Badge({
  tone = "neutral",
  children,
}: {
  tone?: "neutral" | "success" | "warning" | "danger" | "info";
  children: ReactNode;
}) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <p className="empty">{children}</p>;
}

interface ReasonDialogProps {
  title: string;
  description: ReactNode;
  confirmLabel: string;
  danger?: boolean;
  /** Champs supplémentaires affichés au-dessus du motif. */
  children?: ReactNode;
  /** Désactive la confirmation tant que les champs supplémentaires sont invalides. */
  canConfirm?: boolean;
  onConfirm: (reason: string) => Promise<unknown>;
  onClose: () => void;
}

/**
 * Toute action qui modifie quelque chose exige un motif (5 à 500 caractères), conservé dans le
 * journal d'audit (docs/blueprint/09-admin.md §5).
 */
export function ReasonDialog({
  title,
  description,
  confirmLabel,
  danger = false,
  children,
  canConfirm = true,
  onConfirm,
  onClose,
}: ReasonDialogProps) {
  const id = useId();
  const [reason, setReason] = useState("");
  const [error, setError] = useState<unknown>(null);
  const [pending, setPending] = useState(false);
  const textarea = useRef<HTMLTextAreaElement>(null);
  const valid = reason.trim().length >= 5 && canConfirm;

  const hasExtraFields = Boolean(children);
  const closeRef = useRef(onClose);
  useEffect(() => {
    closeRef.current = onClose;
  });

  useEffect(() => {
    if (!hasExtraFields) textarea.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") closeRef.current();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
    };
  }, [hasExtraFields]);

  async function submit(event: SyntheticEvent) {
    event.preventDefault();
    if (!valid || pending) return;
    setPending(true);
    setError(null);
    try {
      await onConfirm(reason.trim());
      onClose();
    } catch (e) {
      setError(e);
      setPending(false);
    }
  }

  return (
    <div className="dialog-backdrop">
      <form
        className="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={`${id}-title`}
        onSubmit={submit}
      >
        <h2 id={`${id}-title`}>{title}</h2>
        <div className="dialog-body">{description}</div>
        {children}
        <label className="field">
          <span>Motif (conservé dans le journal d'audit)</span>
          <textarea
            ref={textarea}
            value={reason}
            onChange={(e) => {
              setReason(e.target.value);
            }}
            minLength={5}
            maxLength={500}
            rows={3}
            required
          />
          <small className="hint">5 caractères minimum.</small>
        </label>
        <ErrorMessage error={error} />
        <div className="dialog-actions">
          <button type="button" className="btn" onClick={onClose} disabled={pending}>
            Annuler
          </button>
          <button
            type="submit"
            className={danger ? "btn btn-danger" : "btn btn-primary"}
            disabled={!valid || pending}
          >
            {pending ? "En cours…" : confirmLabel}
          </button>
        </div>
      </form>
    </div>
  );
}

/** Bouton « Charger plus » des listes paginées par curseur. */
export function LoadMore({
  hasMore,
  loading,
  onClick,
}: {
  hasMore: boolean;
  loading: boolean;
  onClick: () => void;
}) {
  if (!hasMore) return null;
  return (
    <div className="load-more">
      <button type="button" className="btn" onClick={onClick} disabled={loading}>
        {loading ? "Chargement…" : "Charger plus"}
      </button>
    </div>
  );
}
