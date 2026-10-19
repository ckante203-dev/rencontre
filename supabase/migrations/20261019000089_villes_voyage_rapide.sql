-- ═══════════════════════════════════════════════════════════════════
-- Liste des villes du mode voyage, en beaucoup plus léger — 2026-10-19
-- À exécuter dans Supabase → SQL Editor (après 084). Ré-exécutable.
--
-- Le 084 comptait les profils autour de CHACUNE des 269 villes en
-- reparcourant toute la table profiles (et en convertissant chaque ligne
-- en JSON) : très lourd sur un petit serveur, et appelé à chaque
-- ouverture de l'app. Ici, les positions sont lues UNE seule fois, puis
-- comptées ville par ville. Même résultat, même ordre.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.villes_voyage_disponibles()
RETURNS TABLE (
  nom text, pays text, drapeau text,
  lat double precision, lng double precision, nb_profils bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH positions AS MATERIALIZED (
    SELECT p.latitude AS la, p.longitude AS lo
      FROM profiles p
     WHERE p.latitude IS NOT NULL AND p.longitude IS NOT NULL
       AND p.id IS DISTINCT FROM auth.uid()
       AND NOT COALESCE(p.is_suspended, false)
  ),
  moi AS (
    SELECT latitude AS la, longitude AS lo FROM profiles WHERE id = auth.uid()
  ),
  villes AS (
    SELECT v.nom, v.pays, v.drapeau, v.lat, v.lng, v.ordre,
           count(po.la) AS nb
      FROM villes_voyage v
      LEFT JOIN positions po
        ON po.la BETWEEN v.lat - 0.3 AND v.lat + 0.3
       AND po.lo BETWEEN v.lng - 0.3 AND v.lng + 0.3
       AND public._distance_km(v.lat, v.lng, po.la, po.lo) <= 30
     WHERE v.actif
     GROUP BY v.nom, v.pays, v.drapeau, v.lat, v.lng, v.ordre
  ),
  mon_pays AS (
    SELECT vi.pays FROM villes vi, moi
     WHERE moi.la IS NOT NULL AND moi.lo IS NOT NULL
     ORDER BY public._distance_km(vi.lat, vi.lng, moi.la, moi.lo)
     LIMIT 1
  ),
  par_pays AS (
    SELECT vi.pays, sum(vi.nb) AS total FROM villes vi GROUP BY vi.pays
  )
  SELECT vi.nom, vi.pays, vi.drapeau, vi.lat, vi.lng, vi.nb
    FROM villes vi
    JOIN par_pays pp ON pp.pays = vi.pays
   ORDER BY (vi.pays = (SELECT pays FROM mon_pays)) DESC NULLS LAST,
            pp.total DESC, vi.pays, vi.ordre, vi.nom;
$$;
REVOKE ALL ON FUNCTION public.villes_voyage_disponibles() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.villes_voyage_disponibles() TO authenticated;

NOTIFY pgrst, 'reload schema';
