-- ═══════════════════════════════════════════════════════════════════
-- Stories texte impossibles à publier — 2026-10-02
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- Erreur dans l'app (publishTextStory) :
--   null value in column "moderation_status" of relation "stories"
--   violates not-null constraint (23502)
--
-- Cause : le trigger protect_story_moderation (20260930000012/13) met
-- moderation_status à NULL pour une story texte (rien à analyser), et
-- NULL = visible dans la politique stories_moderation. Mais la colonne
-- a reçu une contrainte NOT NULL dans la base en ligne (pas dans les
-- migrations) → toute story texte est refusée.
--
-- Correctif : on retire la contrainte NOT NULL, conformément à la
-- conception d'origine. Rien d'autre ne change (le verrouillage de la
-- modération des photos/vidéos reste tel quel).
-- ═══════════════════════════════════════════════════════════════════

-- (Facultatif) vérifier l'état avant : is_nullable doit valoir 'NO'
-- SELECT column_name, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'stories'
--   AND column_name = 'moderation_status';

ALTER TABLE public.stories
  ALTER COLUMN moderation_status DROP NOT NULL;
