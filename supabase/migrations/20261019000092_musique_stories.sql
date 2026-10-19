-- ═══════════════════════════════════════════════════════════════════
-- 🎵 Musique des stories — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Morceau (id du catalogue de l'app, fichiers dans le bucket public
-- « musiques ») + début de l'extrait en ms. Les anciennes versions de
-- l'app ignorent ces colonnes.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS musique text,
  ADD COLUMN IF NOT EXISTS musique_debut_ms integer NOT NULL DEFAULT 0;

ALTER TABLE public.stories DROP CONSTRAINT IF EXISTS stories_musique_valide;
ALTER TABLE public.stories ADD CONSTRAINT stories_musique_valide CHECK (
  (musique IS NULL OR musique ~ '^[a-z0-9_]{1,40}$')
  AND musique_debut_ms BETWEEN 0 AND 600000
);

NOTIFY pgrst, 'reload schema';
