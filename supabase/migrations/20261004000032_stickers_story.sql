-- ═══════════════════════════════════════════════════════════════════
-- Stickers, emoji et GIF sur les stories — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- stories.stickers : liste JSON [{t, v, x, y, e, r}] posée par l'éditeur
--   t = 'emoji' (v = l'emoji) ou 'giphy' (v = URL media*.giphy.com)
-- Garde-fous : 20 stickers maximum, emoji courts, et seulement des GIF
-- GIPHY (impossible d'afficher une image arbitraire par ce biais).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS stickers jsonb;

CREATE OR REPLACE FUNCTION public.stickers_valides(s jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT s IS NULL OR (
    jsonb_typeof(s) = 'array'
    AND jsonb_array_length(s) <= 20
    AND NOT EXISTS (
      SELECT 1 FROM jsonb_array_elements(s) e
      WHERE jsonb_typeof(e) <> 'object'
         OR NOT (
           (e->>'t' = 'emoji' AND char_length(COALESCE(e->>'v', '')) BETWEEN 1 AND 16)
           OR (e->>'t' = 'giphy'
               AND COALESCE(e->>'v', '') ~ '^https://media[0-9]*\.giphy\.com/'
               AND char_length(e->>'v') <= 300)
         )
    )
  );
$$;

ALTER TABLE public.stories DROP CONSTRAINT IF EXISTS stories_stickers_valides;
ALTER TABLE public.stories ADD CONSTRAINT stories_stickers_valides
  CHECK (public.stickers_valides(stickers));

COMMIT;

NOTIFY pgrst, 'reload schema';
