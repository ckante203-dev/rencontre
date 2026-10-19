-- ═══════════════════════════════════════════════════════════════════
-- ⚡ Boost : meilleur moment pour booster — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Moyenne des personnes actives par heure de la journée sur 14 jours
-- (table pouls_heure, SQL 076). Aucune donnée personnelle : seulement
-- des moyennes. Heures en UTC (= heure d'Abidjan) ; l'app les convertit
-- à l'heure du téléphone. Lecture très légère (≤ 336 lignes).
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.affluence_heures()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH h AS (
    SELECT extract(hour FROM heure AT TIME ZONE 'UTC')::int AS hh,
           avg(actifs)::numeric AS moy
      FROM pouls_heure
     WHERE heure > now() - interval '14 days'
     GROUP BY 1
  )
  SELECT jsonb_build_object(
    'meilleure', (SELECT hh FROM h ORDER BY moy DESC LIMIT 1),
    'max', (SELECT round(max(moy)) FROM h),
    'maintenant', (SELECT round(moy) FROM h
                    WHERE hh = extract(hour FROM now() AT TIME ZONE 'UTC')::int),
    'heures', (SELECT jsonb_object_agg(hh, round(moy)) FROM h));
$$;
REVOKE ALL ON FUNCTION public.affluence_heures() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.affluence_heures() TO authenticated;

NOTIFY pgrst, 'reload schema';
