-- ═══════════════════════════════════════════════════════════════════
-- 056 : « Croisés aujourd'hui » — personnes passées à moins de ~200 m
-- de moi, à moins de 30 min d'écart, dans les dernières 24 h.
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
--
-- Vie privée : positions arrondies (~100 m), gardées 24 h, jamais
-- renvoyées à l'app (seulement la liste des personnes croisées).
-- Les personnes invisibles sur la carte ou qui cachent leur distance
-- ne sont pas enregistrées / pas montrées.
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS public.passages (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  lat     numeric(8,3) NOT NULL,
  lng     numeric(8,3) NOT NULL,
  vu_le   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS passages_vu_idx ON public.passages (vu_le);
CREATE INDEX IF NOT EXISTS passages_lieu_idx ON public.passages (lat, lng, vu_le);
-- Aucun accès direct : seulement via les fonctions ci-dessous
ALTER TABLE public.passages ENABLE ROW LEVEL SECURITY;

-- Enregistre mon passage (au plus un toutes les 10 minutes)
CREATE OR REPLACE FUNCTION public.noter_passage(p_lat double precision, p_lng double precision)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL OR p_lat IS NULL OR p_lng IS NULL THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM passages
              WHERE user_id = v_uid AND vu_le > now() - interval '10 minutes') THEN
    RETURN;
  END IF;
  INSERT INTO passages (user_id, lat, lng)
  VALUES (v_uid, round(p_lat::numeric, 3), round(p_lng::numeric, 3));
  -- Ménage : plus rien au-delà de 24 h
  DELETE FROM passages WHERE vu_le < now() - interval '24 hours';
END;
$$;
REVOKE ALL ON FUNCTION public.noter_passage(double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.noter_passage(double precision, double precision) TO authenticated;

-- Personnes croisées dans les dernières 24 h (identifiants seulement)
CREATE OR REPLACE FUNCTION public.croises_aujourdhui()
RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT DISTINCT autre.user_id
    FROM passages moi
    JOIN passages autre
      ON abs(autre.lat - moi.lat) <= 0.002
     AND abs(autre.lng - moi.lng) <= 0.002
     AND abs(extract(epoch FROM autre.vu_le - moi.vu_le)) <= 1800
    JOIN profiles p ON p.id = autre.user_id
   WHERE moi.user_id = auth.uid()
     AND autre.user_id <> auth.uid()
     AND moi.vu_le > now() - interval '24 hours'
     AND NOT COALESCE(p.is_suspended, false)
     AND COALESCE(p.show_distance, true)
     AND NOT public.blocage_entre(p.id, auth.uid())
   LIMIT 200;
$$;
REVOKE ALL ON FUNCTION public.croises_aujourdhui() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.croises_aujourdhui() TO authenticated;

COMMIT;
