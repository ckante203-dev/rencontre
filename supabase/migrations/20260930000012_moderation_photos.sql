-- ═══════════════════════════════════════════════════════════════════
-- Modération des photos (profil, galerie, stories) — 2026-09-30
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup),
-- AVANT de déployer la fonction moderate-image et la nouvelle app.
-- Le verrouillage complet est dans 20260930000013 (plus tard).
--
-- Les photos passent par la fonction moderate-image (Sightengine) :
--   approved  → publiée
--   unchecked → publiée sans analyse (quota dépassé, vidéo) : à contrôler
--   pending   → douteuse : cachée jusqu'à validation par un admin
--   rejected  → refusée (fichier supprimé)
--
-- Validation par l'admin (en attendant le panneau admin) :
--   photo principale : UPDATE profiles SET photo_url = pending_photo_url,
--                      pending_photo_url = NULL, photo_status = 'approved'
--                      WHERE id = '<uid>';
--   story            : UPDATE stories SET moderation_status = 'approved'
--                      WHERE id = '<id>';
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. Colonnes
-- ───────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS photo_status text,
  ADD COLUMN IF NOT EXISTS pending_photo_url text,
  ADD COLUMN IF NOT EXISTS pending_photo_urls text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS moderation_status text;

-- ───────────────────────────────────────────────────────────────────
-- 2. Stories en attente / refusées : invisibles pour les autres
--    (politique RESTRICTIVE : s'ajoute aux politiques existantes)
-- ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS stories_moderation ON public.stories;
CREATE POLICY stories_moderation ON public.stories
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    moderation_status IS NULL
    OR moderation_status IN ('approved', 'unchecked')
    OR user_id = auth.uid()
    OR public.is_admin()
  );

-- ───────────────────────────────────────────────────────────────────
-- 3. Stories : l'app ne peut pas choisir le statut de modération.
--    Une nouvelle story reste visible (NULL) le temps de l'analyse
--    (une ou deux secondes) : les anciennes versions de l'app, qui
--    n'appellent pas moderate-image, continuent de fonctionner.
--    Le script 20260930000013 la rendra « pending » dès l'envoi.
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.protect_story_moderation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.moderation_status := NULL;
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  IF NEW.moderation_status IS DISTINCT FROM OLD.moderation_status
     OR NEW.media_url IS DISTINCT FROM OLD.media_url THEN
    RAISE EXCEPTION 'Modification de la story non autorisée'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_story_moderation ON public.stories;
CREATE TRIGGER trg_protect_story_moderation
  BEFORE INSERT OR UPDATE ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.protect_story_moderation();

COMMIT;
