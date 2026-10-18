-- ═══════════════════════════════════════════════════════════════════
-- Stickers de rencontre, 2e série — 2026-10-18 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor, APRÈS 087. Ré-exécutable.
--
--   ❓ question : « Pose-moi une question » → réponse en message privé
--   💯 curseur  : « Note mon look » (curseur à émoji 0–100, moyenne)
--   ⏰ rdv      : « Rendez-vous » (texte + quand) → « Je viens » en message
-- + un style au choix pour chaque sticker de rencontre (clé « s » : 0–2).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Contrainte : nouveaux types acceptés ───────────────────────────
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
           -- Stickers de rencontre (SQL 086 / 088)
           OR (e->>'t' IN ('lieu', 'dispo', 'crush', 'question', 'curseur', 'rdv')
               AND char_length(btrim(COALESCE(e->>'v', ''))) BETWEEN 1 AND 80
               AND (e->'o' IS NULL OR (
                     jsonb_typeof(e->'o') = 'array'
                     AND jsonb_array_length(e->'o') <= 2
                     AND NOT EXISTS (
                       SELECT 1 FROM jsonb_array_elements(e->'o') r
                       WHERE jsonb_typeof(r) <> 'string'
                          OR char_length(r #>> '{}') > 40))))
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

-- ─── 💯 Note mon look (curseur 0–100) ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_curseurs (
  story_id   text NOT NULL,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  valeur     smallint NOT NULL CHECK (valeur BETWEEN 0 AND 100),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, user_id)
);
ALTER TABLE public.story_curseurs ENABLE ROW LEVEL SECURITY;
-- Aucune politique : tout passe par les fonctions ci-dessous

CREATE OR REPLACE FUNCTION public.resultat_curseur_story(p_story text)
RETURNS TABLE (moyenne int, nombre bigint, ma_note int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(round(avg(c.valeur))::int, 0), count(*),
         (SELECT m.valeur::int FROM story_curseurs m
           WHERE m.story_id = p_story AND m.user_id = auth.uid())
    FROM story_curseurs c
   WHERE c.story_id = p_story;
$$;

CREATE OR REPLACE FUNCTION public.noter_curseur_story(p_story text, p_valeur int)
RETURNS TABLE (moyenne int, nombre bigint, ma_note int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'non_connecte'; END IF;
  IF p_valeur NOT BETWEEN 0 AND 100 THEN RAISE EXCEPTION 'valeur_invalide'; END IF;
  IF NOT EXISTS (SELECT 1 FROM stories s
                  WHERE s.id::text = p_story AND s.expires_at > now()
                    AND s.user_id <> auth.uid()
                    AND NOT public.blocage_entre(auth.uid(), s.user_id)) THEN
    RAISE EXCEPTION 'story_indisponible';
  END IF;
  INSERT INTO story_curseurs (story_id, user_id, valeur)
  VALUES (p_story, auth.uid(), p_valeur)
  ON CONFLICT (story_id, user_id) DO UPDATE SET valeur = EXCLUDED.valeur;
  RETURN QUERY SELECT * FROM public.resultat_curseur_story(p_story);
END;
$$;

REVOKE ALL ON FUNCTION public.resultat_curseur_story(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.noter_curseur_story(text, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.resultat_curseur_story(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.noter_curseur_story(text, int) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
