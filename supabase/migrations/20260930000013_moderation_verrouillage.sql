-- ═══════════════════════════════════════════════════════════════════
-- Modération des photos — VERROUILLAGE — 2026-09-30
-- À exécuter SEULEMENT quand presque tous les utilisateurs ont la
-- version de l'app qui passe par moderate-image (sinon, avec une
-- ancienne version : changer de photo échoue et les nouvelles stories
-- restent invisibles). Nécessite 20260930000012.
--
-- Effets :
--   - une story avec photo/vidéo est cachée dès l'envoi (« pending »)
--     jusqu'à son analyse ;
--   - l'app ne peut plus poser elle-même une photo de notre Storage sur
--     un profil : impossible de contourner la modération en modifiant
--     l'application.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. Stories : l'app ne peut pas choisir le statut de modération.
--    Une story avec photo/vidéo démarre « pending » ; seule la
--    fonction moderate-image (service_role) ou un admin la valide.
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
    NEW.moderation_status := CASE
      WHEN coalesce(NEW.media_url, '') = '' THEN NULL  -- story texte
      ELSE 'pending'
    END;
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

-- ───────────────────────────────────────────────────────────────────
-- 2. Profils : l'app ne peut plus poser elle-même une photo de notre
--    Storage (elle doit passer par moderate-image). Toujours permis :
--    retirer la photo, mettre une photo externe (Google), retirer ou
--    réordonner les photos de la galerie.
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.protect_profile_photos()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  storage_url constant text := '%/storage/v1/object/public/%';
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.photo_url LIKE storage_url THEN
      NEW.photo_url := NULL;
    END IF;
    IF NEW.photo_urls IS NOT NULL AND NEW.photo_urls::text NOT IN ('{}', '[]') THEN
      RAISE EXCEPTION 'Photos non vérifiées' USING ERRCODE = '42501';
    END IF;
    NEW.photo_status       := NULL;
    NEW.pending_photo_url  := NULL;
    NEW.pending_photo_urls := '{}';
    RETURN NEW;
  END IF;

  IF public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- Photo principale
  IF NEW.photo_url IS DISTINCT FROM OLD.photo_url
     AND coalesce(NEW.photo_url, '') LIKE storage_url THEN
    RAISE EXCEPTION 'Photo non vérifiée' USING ERRCODE = '42501';
  END IF;

  -- Galerie : uniquement retirer ou réordonner
  IF NEW.photo_urls IS DISTINCT FROM OLD.photo_urls
     AND NEW.photo_urls IS NOT NULL
     AND NEW.photo_urls::text NOT IN ('{}', '[]')
     AND NOT coalesce(NEW.photo_urls <@ OLD.photo_urls, false) THEN
    RAISE EXCEPTION 'Photos non vérifiées' USING ERRCODE = '42501';
  END IF;

  -- Statut et photos en attente : l'app peut seulement les retirer
  IF NEW.photo_status IS DISTINCT FROM OLD.photo_status
     AND NEW.photo_status IS NOT NULL THEN
    RAISE EXCEPTION 'Statut de photo non modifiable' USING ERRCODE = '42501';
  END IF;
  IF NEW.pending_photo_url IS DISTINCT FROM OLD.pending_photo_url
     AND NEW.pending_photo_url IS NOT NULL THEN
    RAISE EXCEPTION 'Photo non vérifiée' USING ERRCODE = '42501';
  END IF;
  IF NOT (coalesce(NEW.pending_photo_urls, '{}') <@ coalesce(OLD.pending_photo_urls, '{}')) THEN
    RAISE EXCEPTION 'Photos non vérifiées' USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_profile_photos ON public.profiles;
CREATE TRIGGER trg_protect_profile_photos
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_profile_photos();

COMMIT;
