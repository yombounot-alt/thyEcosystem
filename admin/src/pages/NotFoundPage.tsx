import type { ReactElement } from "react";
import { Link } from "@tanstack/react-router";
import { PageHeader } from "../components/Layout";

export function NotFoundPage(): ReactElement {
  return (
    <>
      <PageHeader title="Page introuvable" />
      <p>
        Cette adresse ne correspond à aucune page. <Link to="/">Retour au tableau de bord</Link>
      </p>
    </>
  );
}
