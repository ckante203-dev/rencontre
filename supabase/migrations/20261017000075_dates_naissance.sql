-- ═══════════════════════════════════════════════════════════════════
-- Statistiques : âge « inconnu » pour la plupart des comptes — 2026-10-17
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- profiles.birthdate est du texte et l'app l'enregistre souvent en
-- « JJ/MM/AAAA » (parfois avec des espaces). _date_sure (script 063) ne
-- lisait que « AAAA-MM-JJ » : ces comptes tombaient en « inconnu ».
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._date_sure(p text)
RETURNS date
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  t text := regexp_replace(COALESCE(p, ''), '\s', '', 'g');
BEGIN
  IF t = '' THEN RETURN NULL; END IF;
  IF t ~ '^\d{1,2}[/.-]\d{1,2}[/.-]\d{4}' THEN
    -- JJ/MM/AAAA (ou JJ-MM-AAAA, JJ.MM.AAAA)
    RETURN make_date(split_part(regexp_replace(t, '[.-]', '/', 'g'), '/', 3)::int,
                     split_part(regexp_replace(t, '[.-]', '/', 'g'), '/', 2)::int,
                     split_part(regexp_replace(t, '[.-]', '/', 'g'), '/', 1)::int);
  END IF;
  RETURN substr(t, 1, 10)::date;   -- AAAA-MM-JJ…
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;

-- Vérification : répartition des formats et des âges lisibles
SELECT CASE WHEN birthdate IS NULL OR btrim(birthdate::text) = '' THEN 'vide'
            WHEN public._date_sure(birthdate::text) IS NULL THEN 'illisible : ' || left(birthdate::text, 20)
            ELSE 'lisible' END AS etat,
       count(*)
  FROM public.profiles
 GROUP BY 1 ORDER BY 2 DESC;
