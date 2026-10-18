-- ═══════════════════════════════════════════════════════════════════
-- Filtres des stories — 2026-10-18 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Photo : le filtre est gravé dans l'image, rien à stocker.
-- Vidéo : on garde l'identifiant du filtre (« ebene », « or »…) et le
-- téléphone de celui qui regarde l'applique à la lecture.
-- Les anciennes versions de l'app ignorent la colonne (vidéo sans filtre).
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS filtre text
  CHECK (filtre IS NULL OR filtre ~ '^[a-z_]{1,30}$');

NOTIFY pgrst, 'reload schema';
