-- ═══════════════════════════════════════════════════════════════════
-- Stickers de rencontre acceptés par la base — 2026-10-18 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor, APRÈS 086. Ré-exécutable.
--
-- La contrainte stories_stickers_valides (scripts 032 / 033) n'acceptait
-- que 'emoji', 'giphy' et 'texte' : une story avec un sticker de rencontre
-- était refusée (« impossible de partager »). On ajoute :
--   lieu    : {t:'lieu', v:<ville ≤ 80>}
--   dispo   : {t:'dispo', v:<texte ≤ 80>}
--   crush   : {t:'crush', v:<texte ≤ 80>}
--   sondage : {t:'sondage', v:<question ≤ 80>, o:[<réponse ≤ 25>, <réponse ≤ 25>]}
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
           -- Stickers de rencontre (SQL 086)
           OR (e->>'t' IN ('lieu', 'dispo', 'crush')
               AND char_length(btrim(COALESCE(e->>'v', ''))) BETWEEN 1 AND 80)
           OR (e->>'t' = 'sondage'
               AND char_length(btrim(COALESCE(e->>'v', ''))) BETWEEN 1 AND 80
               AND jsonb_typeof(e->'o') = 'array'
               AND jsonb_array_length(e->'o') = 2
               AND NOT EXISTS (
                 SELECT 1 FROM jsonb_array_elements(e->'o') r
                 WHERE jsonb_typeof(r) <> 'string'
                    OR char_length(btrim(r #>> '{}')) NOT BETWEEN 1 AND 25))
         )
    )
  );
$$;

NOTIFY pgrst, 'reload schema';

-- Vérification (doit renvoyer true) :
-- SELECT public.stickers_valides('[{"t":"dispo","v":"Dispo ce soir ?"},
--   {"t":"sondage","v":"Resto ou balade ?","o":["Resto","Balade"]}]'::jsonb);
