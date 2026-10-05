-- ═══════════════════════════════════════════════════════════════════
-- Sécurité : positions arrondies à ~500 m — 2026-10-06
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable.
--
-- Avant : profiles.latitude / longitude = position GPS exacte (quelques
-- mètres), lisible par tout utilisateur connecté en interrogeant la base
-- directement (sans passer par l'app) → on pouvait localiser quelqu'un
-- chez lui (faille « trilatération » de Grindr).
-- Désormais la base arrondit TOUTE position reçue à une grille de
-- 0,005° (~550 m), quelle que soit la version de l'app (1.0.11 comprise).
-- Les positions déjà enregistrées sont arrondies aussi.
-- Pas d'impact : tri par proximité, filtres, alertes d'événements et de
-- favoris restent bons à 500 m près ; « Je suis sur place » utilise la
-- position GPS du moment (paramètres de marquer_sur_place), pas celle-ci.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.arrondir_position_profil()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.latitude IS NOT NULL THEN
    NEW.latitude := round(NEW.latitude::numeric / 0.005) * 0.005;
  END IF;
  IF NEW.longitude IS NOT NULL THEN
    NEW.longitude := round(NEW.longitude::numeric / 0.005) * 0.005;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_arrondir_position_profil ON public.profiles;
CREATE TRIGGER trg_arrondir_position_profil
  BEFORE INSERT OR UPDATE OF latitude, longitude ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.arrondir_position_profil();

-- Positions déjà enregistrées (le déclencheur les arrondit). Les alertes
-- « favori à proximité » sont coupées le temps de cette mise à jour,
-- sinon tous les favoris recevraient une notification.
ALTER TABLE public.profiles DISABLE TRIGGER trg_alertes_favoris;
UPDATE public.profiles
   SET latitude = latitude, longitude = longitude
 WHERE latitude IS NOT NULL OR longitude IS NOT NULL;
ALTER TABLE public.profiles ENABLE TRIGGER trg_alertes_favoris;

COMMIT;

-- Vérification : aucune position exacte ne doit rester (résultat 0)
SELECT count(*) AS positions_non_arrondies
FROM public.profiles
WHERE latitude IS NOT NULL
  AND round(latitude::numeric / 0.005) * 0.005 <> latitude::numeric;
