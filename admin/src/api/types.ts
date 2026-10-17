// Formes des réponses de l'API admin (backend/src/modules/admin). L'admin est exclu du contrat
// OpenAPI public : ces types sont tenus à jour à la main et vérifiés par les tests e2e du backend.

export type Permission =
  | "admin:users.read"
  | "admin:users.reveal"
  | "admin:users.restrict"
  | "admin:audit.read"
  | "admin:settings.manage"
  | "admin:businesses.read";

export interface StaffSession {
  staff: {
    id: string;
    email: string;
    fullName: string;
    roles: string[];
    permissions: Permission[];
  };
  mfaVerified: boolean;
  mfaEnrollmentRequired: boolean;
  csrfToken: string;
}

export interface LoginResponse {
  csrfToken: string;
  next: "enroll_totp" | "verify_totp";
}

export interface TotpSetup {
  otpauthUri: string;
  secret: string;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

export type UserStatus = "ACTIVE" | "SUSPENDED" | "BANNED" | "DELETED";

export interface UserListItem {
  id: string;
  fullName: string | null;
  phoneMasked: string;
  status: UserStatus;
  createdAt: string;
  lastLoginAt: string | null;
}

export interface UserDetail extends Omit<UserListItem, "status"> {
  status: UserStatus;
  locale: string;
  phoneVerifiedAt: string | null;
  businesses: {
    id: string;
    name: string;
    roleCode: string;
    status: string;
    joinedAt: string;
  }[];
  activeSessions: {
    id: string;
    startedAt: string;
    lastRefreshAt: string;
    userAgent: string | null;
  }[];
  recentLogins: { at: string; success: boolean }[];
}

export interface AuditEntry {
  id: number;
  createdAt: string;
  actorType: "user" | "staff" | "system";
  actorId: string | null;
  actorLabel: string | null;
  action: string;
  targetType: string | null;
  targetId: string | null;
  metadata: Record<string, unknown>;
}

export interface FeatureFlag {
  key: string;
  description: string;
  enabled: boolean;
  rolloutPercent: number;
  countries: string[] | null;
  updatedAt: string;
}

export interface BusinessListItem {
  id: string;
  name: string;
  country: string;
  currency: string;
  status: string;
  createdAt: string;
  planCode: string | null;
  subscriptionStatus: string | null;
  members: number;
}

export interface EntitlementRow {
  code: string;
  kind: "LIMIT" | "BOOLEAN";
  description: string;
  planValue: number | null;
  overrideValue: number | null;
  hasOverride: boolean;
  overrideReason: string | null;
  overrideExpiresAt: string | null;
  overrideActive: boolean;
}

export interface BusinessEntitlements {
  business: { id: string; name: string; planCode: string; status: string | null };
  entitlements: EntitlementRow[];
}
