-- Gestion d'équipe : invitations sous RLS et acceptées depuis l'app (plus de jeton à transmettre),
-- retrait de membres. Référence : docs/blueprint/04-identity-access.md §4.5, audit du 2026-09-27.

-- ---------------------------------------------------------------------------
-- Invitations : plus de jeton secret. L'invité se connecte par OTP avec le numéro invité, et voit
-- ses invitations dans l'app (GET /me/invitations) : la possession du numéro EST la preuve. Le
-- jeton, renvoyé en clair à l'invitant faute d'envoi SMS, disparaît donc du protocole.
-- ---------------------------------------------------------------------------
ALTER TABLE core.business_invitations ALTER COLUMN token_hash DROP NOT NULL;
ALTER TABLE core.business_invitations ADD COLUMN responded_at timestamptz;
ALTER TABLE core.business_invitations DROP CONSTRAINT business_invitations_status_check;
ALTER TABLE core.business_invitations ADD CONSTRAINT business_invitations_status_check
  CHECK (status IN ('PENDING', 'ACCEPTED', 'DECLINED', 'REVOKED', 'EXPIRED'));
-- Une seule invitation en attente par (entreprise, numéro) : réinviter remplace l'ancienne.
-- Doublons existants : seule la plus récente reste en attente.
UPDATE core.business_invitations i SET status = 'REVOKED'
 WHERE status = 'PENDING'
   AND EXISTS (SELECT 1 FROM core.business_invitations j
                WHERE j.business_id = i.business_id AND j.phone = i.phone
                  AND j.status = 'PENDING' AND j.created_at > i.created_at);
CREATE UNIQUE INDEX business_invitations_pending_uq
  ON core.business_invitations (business_id, phone) WHERE status = 'PENDING';
CREATE INDEX business_invitations_phone_idx
  ON core.business_invitations (phone) WHERE status = 'PENDING';

-- Numéro de l'utilisateur courant (app.user_id), pour les politiques ci-dessous. SECURITY DEFINER
-- + search_path fixé : lit core.users sans dépendre des droits/RLS de l'appelant, et ne renvoie
-- QUE le numéro de l'utilisateur déjà identifié par la transaction.
CREATE OR REPLACE FUNCTION core.current_user_phone() RETURNS text
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, core AS $$
  SELECT phone FROM core.users
   WHERE id = NULLIF(current_setting('app.user_id', true), '')::uuid AND status <> 'DELETED'
$$;
REVOKE ALL ON FUNCTION core.current_user_phone() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION core.current_user_phone() TO thy_app;

ALTER TABLE core.business_invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE core.business_invitations FORCE ROW LEVEL SECURITY;
-- Visible par l'entreprise (app.business_id) OU par la personne invitée (son numéro).
CREATE POLICY business_invitations_tenant_or_invitee ON core.business_invitations
  USING (
    business_id = NULLIF(current_setting('app.business_id', true), '')::uuid
    OR phone = core.current_user_phone()
  )
  WITH CHECK (
    business_id = NULLIF(current_setting('app.business_id', true), '')::uuid
    OR phone = core.current_user_phone()
  );

-- Une personne invitée voit le NOM de l'entreprise qui l'invite (rien d'autre n'est lu ainsi).
DROP POLICY businesses_tenant_or_member ON core.businesses;
CREATE POLICY businesses_tenant_or_member ON core.businesses
  USING (
    id = NULLIF(current_setting('app.business_id', true), '')::uuid
    OR owner_id = NULLIF(current_setting('app.user_id', true), '')::uuid
    OR EXISTS (
      SELECT 1 FROM core.business_members m
       WHERE m.business_id = businesses.id
         AND m.user_id = NULLIF(current_setting('app.user_id', true), '')::uuid
         AND m.status = 'ACTIVE'
    )
    OR EXISTS (
      SELECT 1 FROM core.business_invitations i
       WHERE i.business_id = businesses.id
         AND i.status = 'PENDING'
         AND i.phone = core.current_user_phone()
    )
  )
  WITH CHECK (
    owner_id = NULLIF(current_setting('app.user_id', true), '')::uuid
    OR id = NULLIF(current_setting('app.business_id', true), '')::uuid
  );

-- ---------------------------------------------------------------------------
-- Membres : REMOVED garde l'historique (qui a vendu quoi reste attribuable) et permet une réinvitation.
-- ---------------------------------------------------------------------------
ALTER TABLE core.business_members DROP CONSTRAINT business_members_status_check;
ALTER TABLE core.business_members ADD CONSTRAINT business_members_status_check
  CHECK (status IN ('ACTIVE', 'SUSPENDED', 'REMOVED'));
