-- ═══════════════════════════════════════════════════════════════════
-- 059 : « Coins animés » sur la carte — zones d'environ 1 km avec le
-- plus de membres actifs aujourd'hui, à moins de 25 km de moi.
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
-- Vie privée : 3 membres au moins par zone, centre de zone seulement ;
-- invisibles sur la carte / distance cachée / suspendus exclus.
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.lieux_populaires(p_lat double precision, p_lng double precision)
RETURNS TABLE (lat double precision, lng double precision, nb int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT round(p.latitude::numeric, 2)::float8  AS lat,
         round(p.longitude::numeric, 2)::float8 AS lng,
         count(*)::int AS nb
    FROM profiles p
   WHERE p.latitude IS NOT NULL AND p.longitude IS NOT NULL
     AND p.last_seen > now() - interval '24 hours'
     AND NOT COALESCE(p.is_suspended, false)
     AND COALESCE(p.show_distance, true)
     AND COALESCE(p.map_visible, true)
     AND abs(p.latitude - p_lat) < 0.23
     AND abs(p.longitude - p_lng) < 0.23
   GROUP BY 1, 2
  HAVING count(*) >= 3
   ORDER BY nb DESC
   LIMIT 5;
$$;
REVOKE ALL ON FUNCTION public.lieux_populaires(double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.lieux_populaires(double precision, double precision) TO authenticated;
