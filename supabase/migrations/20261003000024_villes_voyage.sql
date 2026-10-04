-- ═══════════════════════════════════════════════════════════════════
-- Mode voyage multi-pays — 2026-10-03
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- • villes_voyage : liste des villes du mode voyage (Premium), gérée ICI,
--   sans mise à jour de l'app. Pour ouvrir un pays : passer ses villes à
--   actif = true (ou en ajouter), par exemple :
--     UPDATE villes_voyage SET actif = true WHERE pays = 'Sénégal';
-- • villes_voyage_disponibles() : villes actives + nombre de profils dans
--   un rayon de 30 km (pour ne pas « voyager » vers une ville vide).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.villes_voyage (
  id      serial PRIMARY KEY,
  nom     text NOT NULL,
  pays    text NOT NULL,
  drapeau text NOT NULL DEFAULT '',
  lat     double precision NOT NULL,
  lng     double precision NOT NULL,
  actif   boolean NOT NULL DEFAULT true,
  ordre   integer NOT NULL DEFAULT 100,
  UNIQUE (nom, pays)
);

ALTER TABLE public.villes_voyage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS villes_voyage_select ON public.villes_voyage;
CREATE POLICY villes_voyage_select ON public.villes_voyage
  FOR SELECT TO authenticated USING (actif);

-- Côte d'Ivoire : ouverte. Pays voisins / diaspora : prêts, désactivés.
INSERT INTO public.villes_voyage (nom, pays, drapeau, lat, lng, actif, ordre) VALUES
  ('Abidjan',        'Côte d''Ivoire', '🇨🇮', 5.3600, -4.0083, true, 1),
  ('Bouaké',         'Côte d''Ivoire', '🇨🇮', 7.6906, -5.0303, true, 2),
  ('Yamoussoukro',   'Côte d''Ivoire', '🇨🇮', 6.8276, -5.2893, true, 3),
  ('San-Pédro',      'Côte d''Ivoire', '🇨🇮', 4.7485, -6.6363, true, 4),
  ('Korhogo',        'Côte d''Ivoire', '🇨🇮', 9.4580, -5.6296, true, 5),
  ('Daloa',          'Côte d''Ivoire', '🇨🇮', 6.8774, -6.4502, true, 6),
  ('Man',            'Côte d''Ivoire', '🇨🇮', 7.4125, -7.5536, true, 7),
  ('Gagnoa',         'Côte d''Ivoire', '🇨🇮', 6.1319, -5.9506, true, 8),
  ('Grand-Bassam',   'Côte d''Ivoire', '🇨🇮', 5.2118, -3.7388, true, 9),
  ('Assinie',        'Côte d''Ivoire', '🇨🇮', 5.1300, -3.2900, true, 10),
  ('Dakar',          'Sénégal',        '🇸🇳', 14.7167, -17.4677, false, 20),
  ('Bamako',         'Mali',           '🇲🇱', 12.6392, -8.0029, false, 30),
  ('Ouagadougou',    'Burkina Faso',   '🇧🇫', 12.3714, -1.5197, false, 40),
  ('Bobo-Dioulasso', 'Burkina Faso',   '🇧🇫', 11.1771, -4.2979, false, 41),
  ('Accra',          'Ghana',          '🇬🇭', 5.6037, -0.1870, false, 50),
  ('Lomé',           'Togo',           '🇹🇬', 6.1725, 1.2314, false, 60),
  ('Cotonou',        'Bénin',          '🇧🇯', 6.3703, 2.3912, false, 70),
  ('Conakry',        'Guinée',         '🇬🇳', 9.6412, -13.5784, false, 80),
  ('Paris',          'France',         '🇫🇷', 48.8566, 2.3522, false, 90),
  ('Lyon',           'France',         '🇫🇷', 45.7640, 4.8357, false, 91)
ON CONFLICT (nom, pays) DO NOTHING;

-- Villes actives + nombre de profils à moins de 30 km
CREATE OR REPLACE FUNCTION public.villes_voyage_disponibles()
RETURNS TABLE (
  nom text, pays text, drapeau text,
  lat double precision, lng double precision, nb_profils bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT v.nom, v.pays, v.drapeau, v.lat, v.lng,
    (SELECT count(*) FROM profiles p
     WHERE p.latitude IS NOT NULL AND p.longitude IS NOT NULL
       AND p.id <> auth.uid()
       AND NOT COALESCE((to_jsonb(p)->>'is_suspended')::boolean, false)
       -- boîte rapide (~30 km) puis distance exacte
       AND p.latitude BETWEEN v.lat - 0.3 AND v.lat + 0.3
       AND p.longitude BETWEEN v.lng - 0.3 AND v.lng + 0.3
       AND public._distance_km(v.lat, v.lng, p.latitude, p.longitude) <= 30
    ) AS nb_profils
  FROM villes_voyage v
  WHERE v.actif
  ORDER BY v.ordre, v.nom;
$$;
REVOKE ALL ON FUNCTION public.villes_voyage_disponibles() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.villes_voyage_disponibles() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
