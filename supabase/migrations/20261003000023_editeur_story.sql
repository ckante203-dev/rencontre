-- ═══════════════════════════════════════════════════════════════════
-- Éditeur de story façon Snap — 2026-10-03
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- • legende_x / legende_y : centre de la légende, en fraction de l'écran
--   (0 = gauche/haut, 1 = droite/bas) ; legende_echelle : taille (1 = normal).
--   NULL = ancienne légende affichée en bas.
-- • video_debut_ms / video_fin_ms : passage de la vidéo à jouer (vidéo
--   raccourcie dans l'éditeur). NULL = toute la vidéo.
-- Sans ce script, l'app publie quand même (sans ces réglages).
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS legende_x       double precision,
  ADD COLUMN IF NOT EXISTS legende_y       double precision,
  ADD COLUMN IF NOT EXISTS legende_echelle double precision,
  ADD COLUMN IF NOT EXISTS video_debut_ms  integer,
  ADD COLUMN IF NOT EXISTS video_fin_ms    integer;

NOTIFY pgrst, 'reload schema';
