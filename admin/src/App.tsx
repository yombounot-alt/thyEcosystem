import { RouterProvider } from "@tanstack/react-router";
import { ApiError } from "./api/client";
import { LoginPage } from "./auth/LoginPage";
import { useSession } from "./auth/session";
import { TotpPage } from "./auth/TotpPage";
import { ErrorMessage, Spinner } from "./components/ui";
import { router as defaultRouter } from "./router";

/**
 * Portail : tant que la session n'est pas établie (mot de passe + code TOTP), aucun écran de la
 * console n'est monté. L'URL demandée est conservée et s'ouvre une fois connecté.
 */
export function App({ router = defaultRouter }: { router?: typeof defaultRouter }) {
  const session = useSession();

  if (session.isPending) {
    return (
      <main className="auth-screen">
        <Spinner />
      </main>
    );
  }

  if (session.isError) {
    const error = session.error;
    if (error instanceof ApiError && error.status === 401) {
      return <LoginPage expired={error.code === "STAFF_SESSION_EXPIRED"} />;
    }
    return (
      <main className="auth-screen">
        <div className="auth-card">
          <ErrorMessage error={error} />
          <button type="button" className="btn btn-primary" onClick={() => void session.refetch()}>
            Réessayer
          </button>
        </div>
      </main>
    );
  }

  if (!session.data.mfaVerified) return <TotpPage session={session.data} />;

  return <RouterProvider router={router} />;
}
