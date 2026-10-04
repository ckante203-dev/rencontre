-- ═══════════════════════════════════════════════════════════════════
-- Textes multiples sur les stories (gras, couleur, fond) — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 032. Ré-exécutable.
--
-- stories.stickers accepte maintenant le type 'texte' :
--   {t:'texte', v:<texte ≤ 200>, g:<gras bool>, c:<couleur ARGB>, f:0|1|2}
-- (toujours 20 éléments maximum, GIF uniquement depuis GIPHY)
-- ═══════════════════════════════════════════════════════════════════

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
           OR (e->>'t' = 'texte'
               AND char_length(btrim(COALESCE(e->>'v', ''))) BETWEEN 1 AND 200
               AND COALESCE(jsonb_typeof(e->'c'), 'number') = 'number'
               AND COALESCE(e->>'f', '1') IN ('0', '1', '2'))
         )
    )
  );
$$;

-- La contrainte stories_stickers_valides (032) utilise cette fonction :
-- elle accepte donc les textes dès maintenant.
NOTIFY pgrst, 'reload schema';
