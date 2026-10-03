-- ═══════════════════════════════════════════════════════════════════
-- Favoris ⭐ + alertes — 2026-10-02
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup),
-- APRÈS avoir rangé la clé secrète dans le coffre-fort :
--   SELECT vault.create_secret('sb_secret_…', 'notif_secret',
--     'Alertes favoris → dynamic-processor');
-- Ré-exécutable sans risque.
--
-- • favoris : PRIVÉS (la personne ne sait pas qu'elle est en favori).
-- • Alertes envoyées par dynamic-processor (types favori_*) :
--     ⭐ X est en ligne        (au plus 1 fois / 6 h par favori)
--     ⭐ X est près de toi     (< 5 km, au plus 1 fois / 12 h)
--     ⭐ X est dans ta ville   (arrive à < 30 km en venant de > 100 km,
--                               au plus 1 fois / 24 h)
-- • Pas d'alerte de position si le favori est en mode fantôme, invisible
--   sur la carte, ou cache sa distance. Pas d'alerte en cas de blocage.
-- • Réglage profiles.notif_favoris (Paramètres → Alertes de mes favoris).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net;

-- ───────────────────────────────────────────────────────────────────
-- 1. Tables
-- ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.favoris (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  favori_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, favori_id),
  CHECK (user_id <> favori_id)
);
CREATE INDEX IF NOT EXISTS favoris_favori_idx ON public.favoris (favori_id);

ALTER TABLE public.favoris ENABLE ROW LEVEL SECURITY;

-- Chacun ne voit / gère QUE ses propres favoris
DROP POLICY IF EXISTS favoris_select ON public.favoris;
CREATE POLICY favoris_select ON public.favoris
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS favoris_insert ON public.favoris;
CREATE POLICY favoris_insert ON public.favoris
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS favoris_delete ON public.favoris;
CREATE POLICY favoris_delete ON public.favoris
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Anti-spam des alertes (lu/écrit seulement par les fonctions serveur)
CREATE TABLE IF NOT EXISTS public.favoris_alertes (
  user_id   uuid NOT NULL,
  favori_id uuid NOT NULL,
  type      text NOT NULL,
  envoye_le timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, favori_id, type)
);
ALTER TABLE public.favoris_alertes ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_favoris boolean NOT NULL DEFAULT true;

-- ───────────────────────────────────────────────────────────────────
-- 2. Outils
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._distance_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision)
RETURNS double precision
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) *
    power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- Envoie une alerte (si pas déjà envoyée dans le délai) via dynamic-processor
CREATE OR REPLACE FUNCTION public._alerte_favori(
  p_destinataire uuid, p_favori uuid, p_type text,
  p_delai interval, p_distance double precision DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cle text;
BEGIN
  -- Délai anti-spam
  IF EXISTS (SELECT 1 FROM favoris_alertes
             WHERE user_id = p_destinataire AND favori_id = p_favori
               AND type = p_type AND envoye_le > now() - p_delai) THEN
    RETURN;
  END IF;

  SELECT decrypted_secret INTO cle
  FROM vault.decrypted_secrets WHERE name = 'notif_secret' LIMIT 1;
  IF cle IS NULL THEN
    RAISE WARNING 'Alertes favoris : secret notif_secret absent du Vault';
    RETURN;
  END IF;

  INSERT INTO favoris_alertes (user_id, favori_id, type, envoye_le)
  VALUES (p_destinataire, p_favori, p_type, now())
  ON CONFLICT (user_id, favori_id, type) DO UPDATE SET envoye_le = now();

  PERFORM net.http_post(
    url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/dynamic-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cle,
      'apikey', cle),
    body := jsonb_build_object(
      'type', p_type,
      'from_user_id', p_favori,
      'to_user_id', p_destinataire,
      'distance_km', p_distance)
  );
END;
$$;
REVOKE ALL ON FUNCTION public._alerte_favori(uuid, uuid, text, interval, double precision)
  FROM public, anon, authenticated;

-- ───────────────────────────────────────────────────────────────────
-- 3. Trigger : connexion ou déplacement d'un profil
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alertes_favoris()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n jsonb := to_jsonb(NEW);   -- colonnes facultatives lues sans erreur
  vient_en_ligne boolean;
  a_bouge boolean;
  position_visible boolean;
  f record;
  d_nouv double precision;
  d_anc double precision;
BEGIN
  -- Personne ne m'a en favori : rien à faire (cas le plus fréquent)
  IF NOT EXISTS (SELECT 1 FROM favoris WHERE favori_id = NEW.id) THEN
    RETURN NULL;
  END IF;

  vient_en_ligne := NEW.last_seen IS NOT NULL
    AND NEW.last_seen > now() - interval '2 minutes'
    AND (OLD.last_seen IS NULL OR OLD.last_seen < now() - interval '30 minutes');

  a_bouge := NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL
    AND (NEW.latitude IS DISTINCT FROM OLD.latitude
         OR NEW.longitude IS DISTINCT FROM OLD.longitude);

  IF NOT vient_en_ligne AND NOT a_bouge THEN
    RETURN NULL;
  END IF;

  -- Discrétion : fantôme (Premium), invisible sur la carte, distance cachée
  position_visible :=
    COALESCE((n->>'show_distance')::boolean, true)
    AND COALESCE((n->>'map_visible')::boolean, true)
    AND NOT (COALESCE((n->>'is_ghost')::boolean, false)
             AND COALESCE((n->>'is_premium')::boolean, false)
             AND (n->>'ghost_until' IS NULL
                  OR (n->>'ghost_until')::timestamptz > now()));

  FOR f IN
    SELECT p.id, p.latitude, p.longitude
    FROM favoris fv
    JOIN profiles p ON p.id = fv.user_id
    WHERE fv.favori_id = NEW.id
      AND COALESCE(p.notif_favoris, true)
      AND NOT public.blocage_entre(NEW.id, p.id)
  LOOP
    IF vient_en_ligne THEN
      PERFORM public._alerte_favori(f.id, NEW.id, 'favori_en_ligne',
                                    interval '6 hours');
    END IF;

    IF a_bouge AND position_visible
       AND f.latitude IS NOT NULL AND f.longitude IS NOT NULL THEN
      d_nouv := public._distance_km(NEW.latitude, NEW.longitude,
                                    f.latitude, f.longitude);
      d_anc := CASE WHEN OLD.latitude IS NULL OR OLD.longitude IS NULL
                    THEN NULL
                    ELSE public._distance_km(OLD.latitude, OLD.longitude,
                                             f.latitude, f.longitude) END;

      IF d_nouv <= 5 AND (d_anc IS NULL OR d_anc > 5) THEN
        PERFORM public._alerte_favori(f.id, NEW.id, 'favori_proche',
                                      interval '12 hours', round(d_nouv::numeric, 1));
      ELSIF d_nouv <= 30 AND d_anc IS NOT NULL AND d_anc > 100 THEN
        PERFORM public._alerte_favori(f.id, NEW.id, 'favori_ville',
                                      interval '24 hours');
      END IF;
    END IF;
  END LOOP;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_alertes_favoris ON public.profiles;
CREATE TRIGGER trg_alertes_favoris
  AFTER UPDATE OF last_seen, latitude, longitude ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.alertes_favoris();

COMMIT;

NOTIFY pgrst, 'reload schema';
