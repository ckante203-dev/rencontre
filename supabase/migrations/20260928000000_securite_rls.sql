-- ═══════════════════════════════════════════════════════════════════
-- Correctifs de sécurité RLS — 2026-09-28
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Tout est dans une transaction : en cas d'erreur, rien n'est appliqué.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. PROFILES — empêcher un utilisateur de modifier is_premium / is_suspended
--    (seuls le webhook RevenueCat / les edge functions en service_role,
--    le SQL Editor et les admins peuvent les changer).
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.protect_profile_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- service_role, postgres, fonctions SECURITY DEFINER : pas de restriction
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.is_premium   := false;
    NEW.is_suspended := false;
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.is_premium IS DISTINCT FROM OLD.is_premium
     OR NEW.is_suspended IS DISTINCT FROM OLD.is_suspended THEN
    RAISE EXCEPTION 'Modification de is_premium / is_suspended non autorisée'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_columns ON public.profiles;
CREATE TRIGGER trg_protect_profile_columns
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_columns();

-- ───────────────────────────────────────────────────────────────────
-- 2. Plus aucune lecture anonyme (clé anon sans connexion)
-- ───────────────────────────────────────────────────────────────────
-- profiles : profiles_select (auth.uid() IS NOT NULL) reste en place
DROP POLICY IF EXISTS "Tout le monde peut voir les profils" ON public.profiles;
-- stories : stories_select (auth.uid() IS NOT NULL) reste en place
DROP POLICY IF EXISTS "Lecture publique des stories" ON public.stories;
-- annonces : annonces_select (auth.uid() IS NOT NULL) reste en place
DROP POLICY IF EXISTS "Tout le monde peut voir les annonces" ON public.annonces;

DROP POLICY IF EXISTS select_all_comments ON public.story_comments;
DROP POLICY IF EXISTS story_comments_select ON public.story_comments;
CREATE POLICY story_comments_select ON public.story_comments
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS follows_select ON public.follows;
CREATE POLICY follows_select ON public.follows
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Vérification du nom d'utilisateur à l'inscription (avant connexion) :
-- renvoie seulement vrai/faux, sans exposer la table profiles.
CREATE OR REPLACE FUNCTION public.username_available(p_username text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM profiles WHERE username = p_username);
$$;
REVOKE ALL ON FUNCTION public.username_available(text) FROM public;
GRANT EXECUTE ON FUNCTION public.username_available(text) TO anon, authenticated;

-- ───────────────────────────────────────────────────────────────────
-- 3. Modifications des contenus des autres
-- ───────────────────────────────────────────────────────────────────
-- annonce_comments : seul l'auteur modifie son commentaire
DROP POLICY IF EXISTS annonce_comments_update ON public.annonce_comments;
CREATE POLICY annonce_comments_update ON public.annonce_comments
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- messages : le destinataire ne peut changer que les champs d'état
-- (statut, lu, ouvert, expiration du snap, réactions), jamais le contenu.
CREATE OR REPLACE FUNCTION public.protect_message_columns()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  allowed text[] := ARRAY['status', 'is_read', 'is_opened', 'expires_at', 'reactions'];
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.sender_id IS DISTINCT FROM OLD.sender_id
     OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id THEN
    RAISE EXCEPTION 'Modification de l''expéditeur ou de la conversation interdite'
      USING ERRCODE = '42501';
  END IF;

  IF auth.uid() IS DISTINCT FROM OLD.sender_id
     AND (to_jsonb(NEW) - allowed) IS DISTINCT FROM (to_jsonb(OLD) - allowed) THEN
    RAISE EXCEPTION 'Seul l''expéditeur peut modifier le contenu d''un message'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_message_columns ON public.messages;
CREATE TRIGGER trg_protect_message_columns
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.protect_message_columns();

-- ───────────────────────────────────────────────────────────────────
-- 4. typing_status : uniquement les participants de la conversation,
--    et chacun n'écrit que sa propre ligne.
-- ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS typing_all ON public.typing_status;
DROP POLICY IF EXISTS typing_select ON public.typing_status;
DROP POLICY IF EXISTS typing_insert ON public.typing_status;
DROP POLICY IF EXISTS typing_update ON public.typing_status;
DROP POLICY IF EXISTS typing_delete ON public.typing_status;

CREATE POLICY typing_select ON public.typing_status
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM conversations c
            WHERE c.id = typing_status.conversation_id
              AND auth.uid() IN (c.user1_id, c.user2_id))
  );

CREATE POLICY typing_insert ON public.typing_status
  FOR INSERT WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (SELECT 1 FROM conversations c
                WHERE c.id = typing_status.conversation_id
                  AND auth.uid() IN (c.user1_id, c.user2_id))
  );

CREATE POLICY typing_update ON public.typing_status
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY typing_delete ON public.typing_status
  FOR DELETE USING (auth.uid() = user_id);

-- ───────────────────────────────────────────────────────────────────
-- 5. conversations : on ne crée une conversation que si on en fait partie,
--    et on ne peut pas la marquer « acceptée » d'office sans match.
-- ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS conversations_insert ON public.conversations;
CREATE POLICY conversations_insert ON public.conversations
  FOR INSERT WITH CHECK (
    auth.uid() IN (user1_id, user2_id)
    AND user1_id <> user2_id
    AND (initiated_by IS NULL OR initiated_by = auth.uid())
    AND (
      request_status = 'pending'
      -- match = like réciproque (la table matches n'existe pas en base)
      OR (EXISTS (SELECT 1 FROM likes l
                  WHERE l.from_user_id = conversations.user1_id
                    AND l.to_user_id   = conversations.user2_id)
          AND EXISTS (SELECT 1 FROM likes l
                      WHERE l.from_user_id = conversations.user2_id
                        AND l.to_user_id   = conversations.user1_id))
    )
  );

DROP POLICY IF EXISTS conversations_update ON public.conversations;
CREATE POLICY conversations_update ON public.conversations
  FOR UPDATE
  USING (auth.uid() IN (user1_id, user2_id))
  WITH CHECK (auth.uid() IN (user1_id, user2_id));

-- ───────────────────────────────────────────────────────────────────
-- 6. Nettoyage des policies en double (les équivalentes restent)
-- ───────────────────────────────────────────────────────────────────
-- profiles : on garde "Users can update own profile" (qui a un WITH CHECK)
DROP POLICY IF EXISTS profiles_update ON public.profiles;

-- stories : on garde stories_insert / stories_update / stories_delete
DROP POLICY IF EXISTS "Insert stories" ON public.stories;
DROP POLICY IF EXISTS "Update stories" ON public.stories;
DROP POLICY IF EXISTS "Delete stories" ON public.stories;

-- reports : on garde reports_insert_own / reports_select_own
DROP POLICY IF EXISTS reports_insert ON public.reports;
DROP POLICY IF EXISTS reports_select ON public.reports;

-- profile_views : on garde insert_own_view / update_own_view / profile_views_select
DROP POLICY IF EXISTS profile_views_upsert ON public.profile_views;
DROP POLICY IF EXISTS profile_views_update ON public.profile_views;
DROP POLICY IF EXISTS select_views_on_me ON public.profile_views;

COMMIT;

-- ───────────────────────────────────────────────────────────────────
-- 7. matches — la table n'existe pas en base (erreur 42P01) alors que
--    l'app la lit et l'écrit (like_controller.dart, supabase_service.dart).
--    À créer dans une migration séparée.
-- ───────────────────────────────────────────────────────────────────
