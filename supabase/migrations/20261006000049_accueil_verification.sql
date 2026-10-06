-- ═══════════════════════════════════════════════════════════════════
-- Accueil allégé + vérification des profils par selfie — 2026-10-06
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
-- Compatible avec les anciennes versions de l'app (1.0.11, 1.1.0) :
-- elles ignorent les nouvelles colonnes et fonctions.
--
-- 1. profiles.est_verifie : badge « Profil vérifié », posé uniquement par
--    un admin (le client ne peut pas se l'attribuer).
-- 2. verifications + bucket privé « verifications » : selfie imitant une
--    pose tirée au hasard, validé ou refusé dans le panneau admin.
-- 3. profils_accueil() : l'Accueil reçoit les profils LES PLUS PROCHES,
--    avec seulement les infos affichées (plus de « je cherche… », e-mail,
--    jeton de notification, liste de blocage…), blocages filtrés par le
--    serveur. Avant : 600 profils complets, triés sur le téléphone.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Badge vérifié ───────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS est_verifie boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.proteger_est_verifie()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- service_role, postgres, fonctions SECURITY DEFINER : autorisés
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.est_verifie := false;
  ELSIF NEW.est_verifie IS DISTINCT FROM OLD.est_verifie THEN
    RAISE EXCEPTION 'Modification de est_verifie non autorisée'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_est_verifie ON public.profiles;
CREATE TRIGGER trg_proteger_est_verifie
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.proteger_est_verifie();

-- ─── 2. Demandes de vérification ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.verifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  chemin      text,             -- selfie dans le bucket « verifications »
  pose        text NOT NULL CHECK (char_length(pose) <= 80),
  statut      text NOT NULL DEFAULT 'en_attente'
              CHECK (statut IN ('en_attente', 'validee', 'refusee')),
  motif       text CHECK (motif IS NULL OR char_length(motif) <= 200),
  created_at  timestamptz NOT NULL DEFAULT now(),
  traitee_le  timestamptz
);
CREATE INDEX IF NOT EXISTS verifications_user_idx
  ON public.verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS verifications_attente_idx
  ON public.verifications (created_at) WHERE statut = 'en_attente';

ALTER TABLE public.verifications ENABLE ROW LEVEL SECURITY;

-- Chacun lit ses demandes (statut affiché dans l'app) ; les admins tout.
DROP POLICY IF EXISTS verifications_lecture ON public.verifications;
CREATE POLICY verifications_lecture ON public.verifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
-- Écritures : uniquement par les fonctions ci-dessous.
REVOKE INSERT, UPDATE, DELETE ON public.verifications FROM anon, authenticated;

-- Bucket privé : chacun dépose dans SON dossier, seuls les admins lisent.
INSERT INTO storage.buckets (id, name, public)
VALUES ('verifications', 'verifications', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS verifications_envoi ON storage.objects;
CREATE POLICY verifications_envoi ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'verifications'
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS verifications_admin_lecture ON storage.objects;
CREATE POLICY verifications_admin_lecture ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'verifications' AND public.is_admin());

DROP POLICY IF EXISTS verifications_admin_suppression ON storage.objects;
CREATE POLICY verifications_admin_suppression ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'verifications' AND public.is_admin());

-- L'app envoie sa demande (une seule en attente à la fois, 3 par jour)
CREATE OR REPLACE FUNCTION public.demander_verification(p_chemin text, p_pose text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'non_connecte' USING ERRCODE = 'P0001';
  END IF;
  IF p_chemin IS NULL OR split_part(p_chemin, '/', 1) <> v_uid::text THEN
    RAISE EXCEPTION 'chemin_invalide' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = v_uid AND est_verifie) THEN
    RAISE EXCEPTION 'deja_verifie' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM verifications
              WHERE user_id = v_uid AND statut = 'en_attente') THEN
    RAISE EXCEPTION 'deja_en_attente' USING ERRCODE = 'P0001';
  END IF;
  IF (SELECT count(*) FROM verifications
       WHERE user_id = v_uid AND created_at > now() - interval '1 day') >= 3 THEN
    RAISE EXCEPTION 'trop_de_demandes' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO verifications (user_id, chemin, pose)
  VALUES (v_uid, p_chemin, left(p_pose, 80))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- Le panneau admin valide ou refuse. Le selfie est ensuite supprimé du
-- stockage par le panneau (on ne garde pas la photo du visage).
CREATE OR REPLACE FUNCTION public.admin_traiter_verification(
  p_id uuid, p_valider boolean, p_motif text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user uuid;
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN
    RAISE EXCEPTION 'reserve_admin' USING ERRCODE = '42501';
  END IF;
  UPDATE verifications
     SET statut = CASE WHEN p_valider THEN 'validee' ELSE 'refusee' END,
         motif = left(p_motif, 200),
         traitee_le = now(),
         chemin = NULL
   WHERE id = p_id AND statut = 'en_attente'
  RETURNING user_id INTO v_user;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'introuvable_ou_deja_traitee' USING ERRCODE = 'P0001';
  END IF;
  IF p_valider THEN
    UPDATE profiles SET est_verifie = true WHERE id = v_user;
  END IF;
  RETURN v_user;
END;
$$;

-- Retirer le badge (photo changée pour celle d'un autre, abus…)
CREATE OR REPLACE FUNCTION public.admin_retirer_verification(p_user uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN
    RAISE EXCEPTION 'reserve_admin' USING ERRCODE = '42501';
  END IF;
  UPDATE profiles SET est_verifie = false WHERE id = p_user;
END;
$$;

REVOKE ALL ON FUNCTION public.demander_verification(text, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_traiter_verification(uuid, boolean, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_retirer_verification(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.demander_verification(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_traiter_verification(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_retirer_verification(uuid) TO authenticated;

-- ─── 3. Profils de l'Accueil ────────────────────────────────────────
-- Profils boostés d'abord, puis du plus proche au plus loin (sans
-- position : à la fin, les plus récemment actifs d'abord).
-- Renvoie un tableau JSON (mêmes noms de colonnes que la table).
CREATE OR REPLACE FUNCTION public.profils_accueil(
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_limite int DEFAULT 300)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bloques text[];
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}') INTO v_bloques
    FROM profiles WHERE id = v_uid;

  RETURN COALESCE((
    SELECT jsonb_agg(x.ligne ORDER BY x.booste DESC, x.dist NULLS LAST,
                                      x.vu DESC NULLS LAST)
    FROM (
      SELECT jsonb_build_object(
               'id', p.id, 'name', p.name, 'birthdate', p.birthdate,
               'bio', p.bio, 'photo_url', p.photo_url,
               'photo_urls', p.photo_urls, 'interests', p.interests,
               'latitude', p.latitude, 'longitude', p.longitude,
               'gender', p.gender, 'is_online', p.is_online,
               'last_seen', p.last_seen, 'created_at', p.created_at,
               'taille', p.taille, 'poids', p.poids,
               'morphologie', p.morphologie,
               'lieu_rencontre', p.lieu_rencontre,
               'is_premium', p.is_premium,
               'show_birthdate', p.show_birthdate,
               'show_distance', p.show_distance,
               'boost_jusqua', p.boost_jusqua,
               'dispo_texte', p.dispo_texte,
               'dispo_jusqua', p.dispo_jusqua,
               'est_verifie', p.est_verifie) AS ligne,
             COALESCE(p.boost_jusqua > now(), false) AS booste,
             CASE WHEN p_lat IS NULL OR p_lng IS NULL
                       OR p.latitude IS NULL OR p.longitude IS NULL THEN NULL
                  ELSE 12742 * asin(sqrt(
                         power(sin(radians(p.latitude::float8 - p_lat) / 2), 2)
                       + cos(radians(p_lat)) * cos(radians(p.latitude::float8))
                       * power(sin(radians(p.longitude::float8 - p_lng) / 2), 2)))
             END AS dist,
             p.last_seen AS vu
        FROM profiles p
       WHERE p.id <> v_uid
         AND NOT COALESCE(p.is_suspended, false)
         AND NOT (p.id::text = ANY (v_bloques))
         AND NOT (v_uid::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
       ORDER BY COALESCE(p.boost_jusqua > now(), false) DESC,
                dist NULLS LAST, p.last_seen DESC NULLS LAST
       LIMIT LEAST(GREATEST(COALESCE(p_limite, 300), 1), 500)
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.profils_accueil(double precision, double precision, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_accueil(double precision, double precision, int) TO authenticated;

COMMIT;

-- Vérification : doit renvoyer 5 lignes
SELECT proname FROM pg_proc
 WHERE proname IN ('demander_verification', 'admin_traiter_verification',
                   'admin_retirer_verification', 'profils_accueil',
                   'proteger_est_verifie');
