-- ═══════════════════════════════════════════════════════════════════
-- Badge vérifié retiré quand la photo principale change — 2026-10-14
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Le badge certifie que la PHOTO PRINCIPALE correspond au selfie validé.
-- Si elle change (nouvelle photo acceptée par la modération, ou retirée
-- par un admin), le badge saute : la personne peut refaire la
-- vérification depuis son profil. Les photos secondaires ne comptent pas.
--
-- Ordre des déclencheurs : « trg_proteger_est_verifie » (script 049) passe
-- AVANT celui-ci (ordre alphabétique) et ne voit donc pas le changement.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.badge_retire_si_photo()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(OLD.est_verifie, false)
     AND NEW.photo_url IS DISTINCT FROM OLD.photo_url THEN
    NEW.est_verifie := false;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_retrait_badge_photo ON public.profiles;
CREATE TRIGGER trg_retrait_badge_photo
  BEFORE UPDATE OF photo_url ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.badge_retire_si_photo();

COMMIT;
