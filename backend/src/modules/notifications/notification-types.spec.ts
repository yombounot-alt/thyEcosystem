import { backoffSec, MAX_ATTEMPTS } from "../../kernel/events/outbox-relay.service.js";
import { maskPhone } from "../../kernel/notifications/console-sms-sender.adapter.js";
import { NOTIFICATION_TYPES, isNotificationType, roleLabel } from "./notification-types.js";

describe("gabarits de notification", () => {
  it("rendent le texte dans la langue du destinataire, rôle traduit compris", () => {
    const data = { businessName: "Chez Awa", roleCode: "CASHIER" };
    expect(NOTIFICATION_TYPES.MEMBER_JOINED.render("fr", data)).toEqual({
      title: "Vous avez rejoint Chez Awa",
      body: "Votre rôle : caissier.",
    });
    expect(NOTIFICATION_TYPES.MEMBER_JOINED.render("en", data)).toEqual({
      title: "You joined Chez Awa",
      body: "Your role: cashier.",
    });
  });

  it("une variable absente devient vide (jamais « undefined »)", () => {
    const { body } = NOTIFICATION_TYPES.BUSINESS_WELCOME.render("fr", {});
    expect(body).not.toContain("undefined");
    expect(body).toContain("«  »");
  });

  it("les notifications de sécurité et d'accès ne sont pas désactivables", () => {
    for (const type of [
      "SECURITY_SESSION_REVOKED",
      "MEMBER_ROLE_CHANGED",
      "MEMBER_REMOVED",
      "BUSINESS_INVITATION",
    ] as const) {
      expect(NOTIFICATION_TYPES[type].optional, type).toBe(false);
    }
  });

  it("reconnaît les types connus et laisse passer un code de rôle inconnu tel quel", () => {
    expect(isNotificationType("BUSINESS_WELCOME")).toBe(true);
    expect(isNotificationType("toString")).toBe(false);
    expect(roleLabel("fr", "NOUVEAU_ROLE")).toBe("NOUVEAU_ROLE");
  });
});

describe("relais d'outbox — délai entre tentatives", () => {
  it("double à chaque échec et plafonne à 15 minutes", () => {
    expect([1, 2, 3, 4].map(backoffSec)).toEqual([5, 10, 20, 40]);
    expect(backoffSec(MAX_ATTEMPTS + 20)).toBe(15 * 60);
  });
});

describe("masquage du numéro dans les journaux", () => {
  it("ne garde que l'indicatif et les deux derniers chiffres", () => {
    expect(maskPhone("+224620001234")).toBe("+224•••••••34");
    expect(maskPhone("+22")).toBe("•••");
  });
});
