-- ═══════════════════════════════════════════════════════════════════
-- Protections Premium côté serveur — 2026-09-29
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup),
-- APRÈS 20260928000000_securite_rls.sql et 20260929000006_colonnes_carte.sql.
-- Ré-exécutable sans risque (CREATE OR REPLACE / DROP ... IF EXISTS).
-- Tout est dans une transaction : en cas d'erreur, rien n'est appliqué.
--
-- 1. Mode fantôme (is_ghost / ghost_until) : activable uniquement par un
--    Premium (ou un admin). Le désactiver reste toujours possible.
--    Règles reprises de l'app (map_controller.dart) :
--      - toggleGhost() est bloqué si !isPremium ; activer = is_ghost true +
--        ghost_until = maintenant + 30 j ; désactiver = false + NULL ;
--      - estFantome = isPremium && isGhost && (ghost_until NULL ou futur) ;
--      - map_visible / map_invisible_until (mode invisible) et
--        position_precision sont GRATUITS → non restreints ici.
-- 2. « Qui m'a liké / qui m'a vu » : listes servies par des fonctions RPC
--    SECURITY DEFINER réservées aux Premium ; compteurs ouverts à tous.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. PROFILES — trigger de protection des colonnes réservées
--    (logique existante conservée à l'identique + règles mode fantôme)
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
    -- Un nouveau profil n'est jamais Premium → pas de mode fantôme
    NEW.is_ghost     := false;
    NEW.ghost_until  := NULL;
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

  -- Mode fantôme : fonctionnalité Premium.
  -- Interdit pour un non-Premium :
  --   - passer is_ghost à true ;
  --   - modifier ghost_until tant que is_ghost reste true (prolonger, ou
  --     mettre NULL = fantôme illimité).
  -- Toujours autorisé : désactiver (is_ghost false, ghost_until NULL), et
  -- modifier les autres colonnes même si un ancien fantôme est resté actif
  -- après expiration du Premium (l'app l'ignore déjà : estFantome exige
  -- isPremium).
  -- is_premium ne pouvant pas être changé par le client (contrôle
  -- ci-dessus), OLD.is_premium = NEW.is_premium ici.
  IF NOT COALESCE(OLD.is_premium, false)
     AND COALESCE(NEW.is_ghost, false)
     AND (
       NOT COALESCE(OLD.is_ghost, false)
       OR NEW.ghost_until IS DISTINCT FROM OLD.ghost_until
     ) THEN
    RAISE EXCEPTION 'Le mode fantôme est réservé aux membres Premium'
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
-- 2. « Qui m'a liké / qui m'a vu » — listes réservées aux Premium
-- ───────────────────────────────────────────────────────────────────
-- Vérifie que l'appelant est Premium (ou admin), sinon erreur 42501.
CREATE OR REPLACE FUNCTION public._exiger_premium()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non connecté' USING ERRCODE = '42501';
  END IF;

  IF NOT COALESCE(
       (SELECT p.is_premium FROM profiles p WHERE p.id = auth.uid()), false)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Fonctionnalité réservée aux membres Premium'
      USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._exiger_premium() FROM public, anon, authenticated;

-- Liste des personnes qui m'ont liké (les plus récentes d'abord).
-- Champs = ceux utilisés par likes_details_screen.dart.
-- birthdate renvoyé en texte (parsé par DateTime.parse côté app).
-- Le filtrage des profils bloqués reste fait par l'app (blocked_users).
DROP FUNCTION IF EXISTS public.qui_m_a_like(integer);
CREATE FUNCTION public.qui_m_a_like(p_limit integer DEFAULT 50)
RETURNS TABLE (
  id         uuid,
  name       text,
  photo_url  text,
  birthdate  text,
  is_online  boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_premium();

  RETURN QUERY
  SELECT l.from_user_id,
         p.name::text,
         p.photo_url::text,
         p.birthdate::text,
         COALESCE(p.is_online, false)::boolean,
         l.created_at
  FROM likes l
  LEFT JOIN profiles p ON p.id = l.from_user_id
  WHERE l.to_user_id = auth.uid()
  ORDER BY l.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
END;
$$;
REVOKE ALL ON FUNCTION public.qui_m_a_like(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.qui_m_a_like(integer) TO authenticated;

-- Liste des personnes qui ont vu mon profil (les plus récentes d'abord).
DROP FUNCTION IF EXISTS public.qui_m_a_vu(integer);
CREATE FUNCTION public.qui_m_a_vu(p_limit integer DEFAULT 50)
RETURNS TABLE (
  id         uuid,
  name       text,
  photo_url  text,
  birthdate  text,
  is_online  boolean,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_premium();

  RETURN QUERY
  SELECT v.viewer_id,
         p.name::text,
         p.photo_url::text,
         p.birthdate::text,
         COALESCE(p.is_online, false)::boolean,
         v.created_at
  FROM profile_views v
  LEFT JOIN profiles p ON p.id = v.viewer_id
  WHERE v.viewed_id = auth.uid()
  ORDER BY v.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
END;
$$;
REVOKE ALL ON FUNCTION public.qui_m_a_vu(integer) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.qui_m_a_vu(integer) TO authenticated;

-- Compteurs ouverts à tous les utilisateurs connectés (onglet Likes).
-- Prêts pour l'étape 3 ci-dessous (l'app actuelle compte encore en direct).
CREATE OR REPLACE FUNCTION public.compter_likes_recus()
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*) FROM likes WHERE to_user_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.compter_likes_recus() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.compter_likes_recus() TO authenticated;

-- p_depuis optionnel : sert aussi au rappel « X personnes ont vu ton
-- profil » (notification_service.dart, 24 dernières heures).
DROP FUNCTION IF EXISTS public.compter_vues(timestamptz);
CREATE FUNCTION public.compter_vues(p_depuis timestamptz DEFAULT NULL)
RETURNS bigint
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*) FROM profile_views
  WHERE viewed_id = auth.uid()
    AND (p_depuis IS NULL OR created_at >= p_depuis);
$$;
REVOKE ALL ON FUNCTION public.compter_vues(timestamptz) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.compter_vues(timestamptz) TO authenticated;

COMMIT;

-- Recharge le cache de schéma de l'API (les RPC sont visibles tout de suite)
NOTIFY pgrst, 'reload schema';

-- ═══════════════════════════════════════════════════════════════════
-- 3. (PLUS TARD — NE PAS EXÉCUTER MAINTENANT) Fermer la lecture directe
--
-- POURQUOI ON NE LE FAIT PAS TOUT DE SUITE
-- RLS ne sait pas distinguer un « count » d'une liste : retirer la
-- lecture directe d'une ligne casse aussi son comptage.
--
-- • likes (to_user_id = moi) : ON GARDE la lecture directe.
--   Elle est indispensable à :
--     - like_controller.dart : détection du match (like réciproque
--       from_user_id = cible AND to_user_id = moi) ;
--     - home_controller.dart loadLikedMe() + abonnement Realtime sur
--       likes (to_user_id = moi) → likedMeIds / userLikedMe() ;
--       Realtime applique aussi la RLS SELECT ;
--     - profile_insights_controller.dart (compteur .count()) et
--       notification_service.dart _checkNewLikes.
--   Compromis accepté : un client modifié peut encore lister ses likers
--   via l'API. La RPC qui_m_a_like() protège l'écran officiel ; fermer
--   complètement demanderait de déplacer la détection de match et
--   loadLikedMe côté serveur (ex. RPC « est_ce_un_match(cible) »).
--
-- • profile_views (viewed_id = moi) : peut être fermée, MAIS seulement
--   quand une version de l'app qui compte via RPC sera publiée :
--     - profile_insights_controller.dart _loadViewersCount →
--       supabase.rpc('compter_vues') ;
--     - notification_service.dart _checkProfileViews →
--       supabase.rpc('compter_vues', params: {'p_depuis': ...}).
--   Sinon les anciennes versions afficheraient 0 vue.
--   Le spectateur garde la lecture de SES lignes (nécessaire à l'upsert
--   de ecran_profil_detail.dart).
--
-- Script à exécuter à ce moment-là :
--
-- BEGIN;
-- DROP POLICY IF EXISTS profile_views_select ON public.profile_views;
-- CREATE POLICY profile_views_select ON public.profile_views
--   FOR SELECT USING (auth.uid() = viewer_id);
-- COMMIT;
-- ═══════════════════════════════════════════════════════════════════
