-- ═══════════════════════════════════════════════════════════════════
-- 🔒 Story mystère — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- La story est floutée pour ceux qui n'ont pas encore liké l'auteur
-- (« Like pour la découvrir ») ; nette pour l'auteur, ceux qui l'ont liké
-- et ses matchs. Les anciennes versions de l'app ignorent la colonne.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS mystere boolean NOT NULL DEFAULT false;

NOTIFY pgrst, 'reload schema';
