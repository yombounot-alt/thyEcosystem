import {
  createRootRoute,
  createRoute,
  createRouter,
  type RouterHistory,
} from "@tanstack/react-router";
import type { ReactElement } from "react";
import { Layout } from "./components/Layout";
import { AuditPage } from "./pages/AuditPage";
import { BusinessDetailPage } from "./pages/BusinessDetailPage";
import { BusinessesPage } from "./pages/BusinessesPage";
import { DashboardPage } from "./pages/DashboardPage";
import { FlagsPage } from "./pages/FlagsPage";
import { NotFoundPage } from "./pages/NotFoundPage";
import { UserDetailPage } from "./pages/UserDetailPage";
import { UsersPage } from "./pages/UsersPage";

/**
 * Lit un paramètre de chemin. L'inférence de TanStack Router (1.170) retombe par endroits sur `any`
 * pour cet arbre : on vérifie donc la valeur plutôt que de faire confiance au type.
 */
function pathParam(params: unknown, key: string): string {
  const value = (params as Record<string, unknown> | null)?.[key];
  if (typeof value !== "string") throw new Error(`Paramètre de route manquant : ${key}`);
  return value;
}

const rootRoute = createRootRoute({ component: Layout, notFoundComponent: NotFoundPage });

const userRoute = createRoute({ getParentRoute: () => rootRoute, path: "/users/$userId" });
userRoute.update({
  component: function UserRoute(): ReactElement {
    return <UserDetailPage userId={pathParam(userRoute.useParams(), "userId")} />;
  },
});

const businessRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: "/businesses/$businessId",
});
businessRoute.update({
  component: function BusinessRoute(): ReactElement {
    return <BusinessDetailPage businessId={pathParam(businessRoute.useParams(), "businessId")} />;
  },
});

// Forme objet d'`addChildren` : avec un tableau, TypeScript perd le typage des paramètres de route.
const routeTree = rootRoute.addChildren({
  dashboard: createRoute({ getParentRoute: () => rootRoute, path: "/", component: DashboardPage }),
  users: createRoute({ getParentRoute: () => rootRoute, path: "/users", component: UsersPage }),
  userRoute,
  businesses: createRoute({
    getParentRoute: () => rootRoute,
    path: "/businesses",
    component: BusinessesPage,
  }),
  businessRoute,
  audit: createRoute({ getParentRoute: () => rootRoute, path: "/audit", component: AuditPage }),
  flags: createRoute({
    getParentRoute: () => rootRoute,
    path: "/settings/flags",
    component: FlagsPage,
  }),
});

/** Routeur de l'application (historique du navigateur). */
export const router = createRouter({ routeTree });

/** Routeur sur un autre historique (tests : historique en mémoire). */
export function createAppRouter(history: RouterHistory): typeof router {
  return createRouter({ routeTree, history });
}

declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
