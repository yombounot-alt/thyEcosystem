import { useQueryClient } from "@tanstack/react-query";
import { useState, type SyntheticEvent } from "react";
import { api, setCsrfToken } from "../api/client";
import type { LoginResponse } from "../api/types";
import { ErrorMessage } from "../components/ui";
import { SESSION_KEY } from "./session";

export function LoginPage({ expired = false }: { expired?: boolean }) {
  const client = useQueryClient();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<unknown>(null);
  const [pending, setPending] = useState(false);

  async function submit(event: SyntheticEvent) {
    event.preventDefault();
    setPending(true);
    setError(null);
    try {
      const res = await api<LoginResponse>("POST", "/auth/login", { email, password });
      setCsrfToken(res.csrfToken);
      await client.invalidateQueries({ queryKey: SESSION_KEY });
    } catch (e) {
      setError(e);
      setPending(false);
    }
  }

  return (
    <main className="auth-screen">
      <form className="auth-card" onSubmit={submit}>
        <p className="brand">THY Admin</p>
        <h1>Connexion</h1>
        <p className="muted">Espace réservé à l'équipe THY.</p>
        {expired ? (
          <div className="alert alert-info" role="status">
            Votre session a expiré. Reconnectez-vous.
          </div>
        ) : null}
        <label className="field">
          <span>Adresse e-mail</span>
          <input
            type="email"
            autoComplete="username"
            value={email}
            onChange={(e) => {
              setEmail(e.target.value);
            }}
            required
            autoFocus
          />
        </label>
        <label className="field">
          <span>Mot de passe</span>
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => {
              setPassword(e.target.value);
            }}
            required
          />
        </label>
        <ErrorMessage error={error} />
        <button type="submit" className="btn btn-primary btn-block" disabled={pending}>
          {pending ? "Connexion…" : "Continuer"}
        </button>
      </form>
    </main>
  );
}
