import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { createMemoryHistory } from "@tanstack/react-router";
import { render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { setCsrfToken } from "./api/client";
import { App } from "./App";
import { createAppRouter } from "./router";
import { fakeApi, session, unauthenticated } from "./test/fake-api";

function renderApp(path = "/") {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createAppRouter(createMemoryHistory({ initialEntries: [path] }));
  return render(
    <QueryClientProvider client={client}>
      <App router={router} />
    </QueryClientProvider>,
  );
}

describe("portail de connexion", () => {
  afterEach(() => {
    setCsrfToken(null);
  });

  it("sans session : écran de connexion, puis double authentification", async () => {
    let signedIn = false;
    const { calls } = fakeApi({
      "GET /auth/session": () =>
        signedIn
          ? {
              body: session([], {
                mfaVerified: false,
                mfaEnrollmentRequired: false,
                csrfToken: "c2",
              }),
            }
          : unauthenticated,
      "POST /auth/login": () => {
        signedIn = true;
        return { body: { csrfToken: "c1", next: "verify_totp" } };
      },
    });
    const user = userEvent.setup();
    renderApp();

    await screen.findByRole("heading", { name: "Connexion" });
    await user.type(screen.getByLabelText("Adresse e-mail"), "awa@thy.test");
    await user.type(screen.getByLabelText("Mot de passe"), "secret");
    await user.click(screen.getByRole("button", { name: "Continuer" }));

    await screen.findByRole("heading", { name: "Double authentification" });
    expect(calls.find((c) => c.path === "/auth/login")?.body).toEqual({
      email: "awa@thy.test",
      password: "secret",
    });
    expect(screen.getByRole("button", { name: "Valider" })).toBeDisabled();
  });

  it("affiche l'erreur du serveur quand les identifiants sont refusés", async () => {
    fakeApi({
      "GET /auth/session": unauthenticated,
      "POST /auth/login": {
        status: 401,
        body: { error: { code: "STAFF_INVALID_CREDENTIALS", message: "Identifiants invalides" } },
      },
    });
    const user = userEvent.setup();
    renderApp();
    await user.type(await screen.findByLabelText("Adresse e-mail"), "awa@thy.test");
    await user.type(screen.getByLabelText("Mot de passe"), "faux");
    await user.click(screen.getByRole("button", { name: "Continuer" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Identifiants invalides");
  });

  it("premier accès : enrôlement TOTP avec QR code et clé manuelle", async () => {
    fakeApi({
      "GET /auth/session": {
        body: session([], { mfaVerified: false, mfaEnrollmentRequired: true }),
      },
      "POST /auth/totp/setup": {
        body: {
          otpauthUri: "otpauth://totp/THY%20Admin:awa?secret=JBSWY3DPEHPK3PXP",
          secret: "JBSWY3DPEHPK3PXP",
        },
      },
    });
    const user = userEvent.setup();
    renderApp();
    await user.click(await screen.findByRole("button", { name: "Configurer l'application" }));
    expect(await screen.findByLabelText("Clé secrète")).toHaveTextContent("JBSW Y3DP EHPK 3PXP");
    expect(screen.getByLabelText("Code à 6 chiffres")).toBeInTheDocument();
  });

  it("session expirée : message explicite sur l'écran de connexion", async () => {
    fakeApi({
      "GET /auth/session": {
        status: 401,
        body: { error: { code: "STAFF_SESSION_EXPIRED", message: "Session expirée" } },
      },
    });
    renderApp();
    expect(
      await screen.findByText("Votre session a expiré. Reconnectez-vous."),
    ).toBeInTheDocument();
  });
});

describe("console selon le rôle", () => {
  it("un agent support ne voit que les rubriques de ses droits", async () => {
    fakeApi({
      "GET /auth/session": { body: session(["admin:users.read", "admin:users.reveal"]) },
    });
    renderApp();
    const nav = await screen.findByRole("navigation", { name: "Navigation principale" });
    expect(within(nav).getByRole("link", { name: "Utilisateurs" })).toBeInTheDocument();
    expect(within(nav).queryByRole("link", { name: "Journal d'audit" })).toBeNull();
    expect(within(nav).queryByRole("link", { name: "Feature flags" })).toBeNull();
  });

  it("une page hors de ses droits affiche un refus, sans appeler l'API", async () => {
    const { calls } = fakeApi({ "GET /auth/session": { body: session(["admin:users.read"]) } });
    renderApp("/audit");
    expect(
      await screen.findByText("Votre rôle ne donne pas accès à cette page."),
    ).toBeInTheDocument();
    expect(calls.some((c) => c.path.startsWith("/audit"))).toBe(false);
  });

  it("recherche d'utilisateurs : numéros masqués, lien vers la fiche", async () => {
    const { calls } = fakeApi({
      "GET /auth/session": { body: session(["admin:users.read"]) },
      "GET /users": {
        body: {
          items: [
            {
              id: "u1",
              fullName: "Mamadou Diallo",
              phoneMasked: "+224••••••12",
              status: "SUSPENDED",
              createdAt: "2026-09-01T10:00:00Z",
              lastLoginAt: null,
            },
          ],
          nextCursor: null,
        },
      },
    });
    const user = userEvent.setup();
    renderApp("/users");
    expect(await screen.findByRole("link", { name: "Mamadou Diallo" })).toHaveAttribute(
      "href",
      "/users/u1",
    );
    expect(screen.getByText("+224••••••12")).toBeInTheDocument();
    expect(screen.getByText("Suspendu")).toBeInTheDocument();

    await user.type(screen.getByRole("searchbox"), "+224 62");
    await user.click(screen.getByRole("button", { name: "Rechercher" }));
    await waitFor(() => {
      expect(calls.some((c) => c.path === "/users?q=%2B224+62")).toBe(true);
    });
  });

  it("fiche utilisateur : afficher le numéro exige un motif, envoyé à l'API", async () => {
    const { calls } = fakeApi({
      "GET /auth/session": { body: session(["admin:users.read", "admin:users.reveal"]) },
      "GET /users/u1": {
        body: {
          id: "u1",
          fullName: "Mamadou Diallo",
          phoneMasked: "+224••••••12",
          status: "ACTIVE",
          locale: "fr",
          phoneVerifiedAt: null,
          createdAt: "2026-09-01T10:00:00Z",
          lastLoginAt: null,
          businesses: [],
          activeSessions: [],
          recentLogins: [],
        },
      },
      "POST /users/u1/reveal-phone": { body: { phone: "+224620000012" } },
    });
    const user = userEvent.setup();
    renderApp("/users/u1");

    await user.click(await screen.findByRole("button", { name: "Afficher en clair" }));
    const dialog = screen.getByRole("dialog", { name: "Afficher le numéro en clair" });
    const confirm = within(dialog).getByRole("button", { name: "Afficher" });
    expect(confirm).toBeDisabled();
    await user.type(within(dialog).getByRole("textbox"), "rap "); // moins de 5 caractères utiles
    expect(confirm).toBeDisabled();
    await user.type(within(dialog).getByRole("textbox"), "client");
    expect(confirm).toBeEnabled();
    await user.click(confirm);

    expect(await screen.findByText("+224620000012")).toBeInTheDocument();
    expect(calls.find((c) => c.path === "/users/u1/reveal-phone")).toMatchObject({
      body: { reason: "rap client" },
      headers: { "X-CSRF-Token": "csrf-1" },
    });
    // Sans le droit « suspendre », aucune action de restriction n'est proposée.
    expect(screen.queryByRole("button", { name: "Suspendre le compte" })).toBeNull();
  });
});
