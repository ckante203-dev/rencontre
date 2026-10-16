-- ═══════════════════════════════════════════════════════════════════
-- Vidéo de profil d'un admin : partait sans modération — 2026-10-17
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Le trigger 055 laissait passer TOUTES les modifications d'un admin :
-- quand un admin ajoutait SA vidéo depuis l'app, elle n'était pas mise
-- « en attente » et n'apparaissait pas dans le panneau « Vidéos de
-- profil ». Désormais l'exception admin ne vaut que pour le profil d'un
-- AUTRE utilisateur.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.proteger_video_profil()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Fonctions serveur, ou admin qui modifie le profil de quelqu'un d'autre
  IF current_user NOT IN ('authenticated', 'anon')
     OR (public.is_admin() AND NEW.id IS DISTINCT FROM auth.uid()) THEN
    RETURN NEW;
  END IF;
  IF NEW.video_url IS DISTINCT FROM OLD.video_url THEN
    -- Nouvelle vidéo (ou suppression) : repart en modération
    NEW.video_statut := CASE WHEN NEW.video_url IS NULL THEN NULL ELSE 'en_attente' END;
    NEW.video_soumise_le := CASE WHEN NEW.video_url IS NULL THEN NULL ELSE now() END;
    NEW.video_motif := NULL;
  ELSE
    NEW.video_statut := OLD.video_statut;
    NEW.video_soumise_le := OLD.video_soumise_le;
    NEW.video_motif := OLD.video_motif;
  END IF;
  RETURN NEW;
END;
$$;

-- Vidéos envoyées sans statut (cas ci-dessus) : à modérer
UPDATE public.profiles
   SET video_statut = 'en_attente',
       video_soumise_le = COALESCE(video_soumise_le, now())
 WHERE video_url IS NOT NULL AND video_statut IS NULL;

COMMIT;

-- Vérification : vidéos en attente
SELECT name, video_statut, video_soumise_le FROM public.profiles
 WHERE video_url IS NOT NULL ORDER BY video_soumise_le DESC NULLS LAST LIMIT 10;
