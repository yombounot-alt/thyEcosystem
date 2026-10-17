import { useQueryClient } from "@tanstack/react-query";
import QRCode from "qrcode";
import { useEffect, useState, type SyntheticEvent } from "react";
import { api, setCsrfToken } from "../api/client";
import type { StaffSession, TotpSetup } from "../api/types";
import { ErrorMessage } from "../components/ui";
import { SESSION_KEY } from "./session";

/**
 * Seconde étape de connexion : enrôlement de l'application d'authentification à la première
 * connexion (QR code + clé à saisir à la main), puis saisie du code à 6 chiffres.
 */
export function TotpPage({ session }: { session: StaffSession }) {
  const client = useQueryClient();
  const enrolling = session.mfaEnrollmentRequired;
  const [setup, setSetup] = useState<TotpSetup | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [error, setError] = useState<unknown>(null);
  const [pending, setPending] = useState(false);

  useEffect(() => {
    if (!setup) return;
    let cancelled = false;
    QRCode.toDataURL(setup.otpauthUri, { margin: 1, width: 220 })
      .then((url) => {
        if (!cancelled) setQr(url);
      })
      .catch(() => {
        // Sans QR code, la clé affichée en clair suffit pour l'enrôlement manuel.
      });
    return () => {
      cancelled = true;
    };
  }, [setup]);

  async function startSetup() {
    setPending(true);
    setError(null);
    try {
      setSetup(await api<TotpSetup>("POST", "/auth/totp/setup"));
    } catch (e) {
      setError(e);
    } finally {
      setPending(false);
    }
  }

  async function confirm(event: SyntheticEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    try {
      await api("POST", "/auth/totp/confirm", { code });
      await client.invalidateQueries({ queryKey: SESSION_KEY });
    } catch (e) {
      setError(e);
      setCode("");
      setPending(false);
    }
  }

  async function cancel() {
    await api("POST", "/auth/logout").catch(() => undefined);
    setCsrfToken(null);
    await client.invalidateQueries({ queryKey: SESSION_KEY });
  }

  const codeForm = (
    <form onSubmit={confirm} className="stack">
      <label className="field">
        <span>Code à 6 chiffres</span>
        <input
          className="code-input"
          inputMode="numeric"
          autoComplete="one-time-code"
          pattern="\d{6}"
          maxLength={6}
          value={code}
          onChange={(e) => {
            setCode(e.target.value.replace(/\D/g, ""));
          }}
          required
          autoFocus
        />
      </label>
      <ErrorMessage error={error} />
      <button
        type="submit"
        className="btn btn-primary btn-block"
        disabled={pending || code.length !== 6}
      >
        {pending ? "Vérification…" : "Valider"}
      </button>
    </form>
  );

  return (
    <main className="auth-screen">
      <div className="auth-card">
        <p className="brand">THY Admin</p>
        <h1>Double authentification</h1>
        <p className="muted">Connecté en tant que {session.staff.email}</p>

        {!enrolling ? (
          <>
            <p>Saisissez le code affiché par votre application d'authentification.</p>
            {codeForm}
          </>
        ) : !setup ? (
          <>
            <p>
              La double authentification est obligatoire. Installez une application
              d'authentification (Google Authenticator, Microsoft Authenticator, 1Password…) sur
              votre téléphone, puis continuez.
            </p>
            <ErrorMessage error={error} />
            <button
              type="button"
              className="btn btn-primary btn-block"
              onClick={startSetup}
              disabled={pending}
            >
              {pending ? "Préparation…" : "Configurer l'application"}
            </button>
          </>
        ) : (
          <>
            <ol className="steps">
              <li>Dans l'application, ajoutez un compte en scannant ce QR code.</li>
              <li>Saisissez ensuite le code à 6 chiffres qu'elle affiche.</li>
            </ol>
            <div className="qr">
              {qr ? <img src={qr} alt="QR code d'enrôlement" width={220} height={220} /> : null}
            </div>
            <details className="manual-key">
              <summary>Impossible de scanner ? Saisir la clé à la main</summary>
              <code aria-label="Clé secrète">{setup.secret.replace(/(.{4})/g, "$1 ").trim()}</code>
            </details>
            {codeForm}
          </>
        )}
        <button type="button" className="btn btn-link" onClick={cancel}>
          Changer de compte
        </button>
      </div>
    </main>
  );
}
