-- ═══════════════════════════════════════════════════════════════════
-- Événements v2 — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 034. Ré-exécutable.
-- (À exécuter AVANT de déployer l'edge function rappel-evenements :
--  la tâche planifiée est créée à la fin de ce script.)
--
-- • « ⭐ Intéressé » ou « ✋ J'y vais » (evenement_participants.statut)
-- • « 📍 Je suis sur place » : vérifié par le GPS (≤ 1,5 km du lieu,
--   pendant l'événement) via marquer_sur_place() uniquement.
-- • Stories de l'événement : stories.evenement_id (seulement si on
--   participe et que l'événement a lieu maintenant).
-- • Propositions des utilisateurs : statut 'en_attente' (3 maximum en
--   attente par personne), validées par l'admin.
-- • Notifications (tâche horaire → edge function rappel-evenements) :
--   rappel la veille et 2 h avant, « des personnes que tu as likées y
--   vont », « nouvel événement près de toi » (case dans l'admin).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Colonnes ────────────────────────────────────────────────────
ALTER TABLE public.evenement_participants
  ADD COLUMN IF NOT EXISTS statut text NOT NULL DEFAULT 'y_va',
  ADD COLUMN IF NOT EXISTS sur_place_le timestamptz;
ALTER TABLE public.evenement_participants
  DROP CONSTRAINT IF EXISTS evenement_participants_statut_check;
ALTER TABLE public.evenement_participants
  ADD CONSTRAINT evenement_participants_statut_check
  CHECK (statut IN ('interesse', 'y_va'));

ALTER TABLE public.evenements
  ADD COLUMN IF NOT EXISTS notifier_proches boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS motif_refus text;
ALTER TABLE public.evenements DROP CONSTRAINT IF EXISTS evenements_statut_check;
ALTER TABLE public.evenements ADD CONSTRAINT evenements_statut_check
  CHECK (statut IN ('publie', 'brouillon', 'annule', 'en_attente', 'refuse'));

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS evenement_id uuid
  REFERENCES public.evenements(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS stories_evenement_idx
  ON public.stories (evenement_id) WHERE evenement_id IS NOT NULL;

-- Notifications déjà envoyées (jamais deux fois la même)
CREATE TABLE IF NOT EXISTS public.evenement_notifs (
  evenement_id uuid NOT NULL REFERENCES public.evenements(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type         text NOT NULL,
  envoye_le    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (evenement_id, user_id, type)
);
ALTER TABLE public.evenement_notifs ENABLE ROW LEVEL SECURITY;
-- (aucune politique : seule l'edge function, en service_role, y accède)

-- Événement en cours (1 h avant le début jusqu'à la fin)
CREATE OR REPLACE FUNCTION public.evenement_en_cours(e public.evenements)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT e.statut = 'publie'
     AND now() >= e.debut - interval '1 hour'
     AND now() <= public.fin_evenement(e);
$$;

CREATE OR REPLACE FUNCTION public.distance_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 12742 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
      * power(sin(radians(lng2 - lng1) / 2), 2)));
$$;

-- ── 2. Participations : statut, « sur place » protégé ───────────────
-- « Sur place » ne peut être posé que par marquer_sur_place() (GPS)
CREATE OR REPLACE FUNCTION public.proteger_sur_place()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF COALESCE(current_setting('zamu.sur_place', true), '') <> 'oui' THEN
    IF TG_OP = 'INSERT' THEN
      NEW.sur_place_le := NULL;
    ELSE
      NEW.sur_place_le := OLD.sur_place_le;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_proteger_sur_place ON public.evenement_participants;
CREATE TRIGGER trg_proteger_sur_place
  BEFORE INSERT OR UPDATE ON public.evenement_participants
  FOR EACH ROW EXECUTE FUNCTION public.proteger_sur_place();

-- Passer de « Intéressé » à « J'y vais » (et inversement)
DROP POLICY IF EXISTS evenement_participants_update ON public.evenement_participants;
CREATE POLICY evenement_participants_update ON public.evenement_participants
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.evenements e
                WHERE e.id = evenement_id
                  AND e.statut = 'publie'
                  AND public.fin_evenement(e) > now())
  );

-- « 📍 Je suis sur place » : 'ok', 'trop_loin', 'pas_en_cours', 'introuvable'
CREATE OR REPLACE FUNCTION public.marquer_sur_place(
  p_ev uuid, p_lat double precision, p_lng double precision)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  e evenements;
BEGIN
  IF auth.uid() IS NULL THEN RETURN 'introuvable'; END IF;
  SELECT * INTO e FROM evenements WHERE id = p_ev;
  IF NOT FOUND THEN RETURN 'introuvable'; END IF;
  IF NOT public.evenement_en_cours(e) THEN RETURN 'pas_en_cours'; END IF;
  IF e.latitude IS NOT NULL AND e.longitude IS NOT NULL THEN
    IF p_lat IS NULL OR p_lng IS NULL
       OR public.distance_km(e.latitude, e.longitude, p_lat, p_lng) > 1.5 THEN
      RETURN 'trop_loin';
    END IF;
  END IF;
  PERFORM set_config('zamu.sur_place', 'oui', true);
  INSERT INTO evenement_participants (evenement_id, user_id, statut, sur_place_le)
  VALUES (p_ev, auth.uid(), 'y_va', now())
  ON CONFLICT (evenement_id, user_id)
  DO UPDATE SET statut = 'y_va', sur_place_le = now();
  PERFORM set_config('zamu.sur_place', '', true);
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.marquer_sur_place(uuid, double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.marquer_sur_place(uuid, double precision, double precision) TO authenticated;

-- ── 3. Propositions des utilisateurs ───────────────────────────────
DROP POLICY IF EXISTS evenements_select ON public.evenements;
CREATE POLICY evenements_select ON public.evenements
  FOR SELECT TO authenticated
  USING (statut IN ('publie', 'annule') OR cree_par = auth.uid()
         OR public.is_admin());

DROP POLICY IF EXISTS evenements_proposition ON public.evenements;
CREATE POLICY evenements_proposition ON public.evenements
  FOR INSERT TO authenticated
  WITH CHECK (cree_par = auth.uid() AND statut = 'en_attente');

-- Une proposition reste « en attente » (seul l'admin publie) ; 3 maximum
CREATE OR REPLACE FUNCTION public.controler_proposition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  NEW.statut := 'en_attente';
  NEW.notifier_proches := false;
  NEW.image_url := NULL;
  NEW.cree_par := auth.uid();
  IF NEW.debut < now() THEN
    RAISE EXCEPTION 'date_passee' USING ERRCODE = 'P0001';
  END IF;
  IF (SELECT count(*) FROM evenements
      WHERE cree_par = auth.uid() AND statut = 'en_attente') >= 3 THEN
    RAISE EXCEPTION 'trop_de_propositions' USING ERRCODE = 'P0001',
      HINT = '3 propositions en attente maximum';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_controler_proposition ON public.evenements;
CREATE TRIGGER trg_controler_proposition
  BEFORE INSERT ON public.evenements
  FOR EACH ROW EXECUTE FUNCTION public.controler_proposition();

-- ── 4. Stories de l'événement ──────────────────────────────────────
-- Seulement si l'auteur participe et que l'événement a lieu maintenant
CREATE OR REPLACE FUNCTION public.controler_story_evenement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.evenement_id IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.evenement_id IS DISTINCT FROM OLD.evenement_id)
     AND NOT (
       public.participe_evenement(NEW.evenement_id, NEW.user_id)
       AND EXISTS (SELECT 1 FROM evenements e
                   WHERE e.id = NEW.evenement_id
                     AND public.evenement_en_cours(e))) THEN
    NEW.evenement_id := NULL;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_controler_story_evenement ON public.stories;
CREATE TRIGGER trg_controler_story_evenement
  BEFORE INSERT OR UPDATE OF evenement_id ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.controler_story_evenement();

-- ── 5. Fonctions pour l'app (nouvelles colonnes) ───────────────────
DROP FUNCTION IF EXISTS public.evenements_a_venir();
CREATE FUNCTION public.evenements_a_venir()
RETURNS TABLE (
  id uuid, titre text, description text, categorie text, lieu text,
  ville text, latitude double precision, longitude double precision,
  debut timestamptz, fin timestamptz, image_url text, statut text,
  nb_participants int, nb_interesses int, nb_sur_place int,
  ma_participation text, je_suis_sur_place boolean,
  nb_matchs int, nb_stories int, je_participe boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH parts AS (
    SELECT p.*, NOT COALESCE(pr.is_suspended, false) AS actif
    FROM evenement_participants p
    JOIN profiles pr ON pr.id = p.user_id
  )
  SELECT e.id, e.titre, e.description, e.categorie, e.lieu, e.ville,
         e.latitude, e.longitude, e.debut, e.fin, e.image_url, e.statut,
         (SELECT count(*)::int FROM parts p
           WHERE p.evenement_id = e.id AND p.actif AND p.statut = 'y_va'),
         (SELECT count(*)::int FROM parts p
           WHERE p.evenement_id = e.id AND p.actif AND p.statut = 'interesse'),
         (SELECT count(*)::int FROM parts p
           WHERE p.evenement_id = e.id AND p.actif
             AND p.sur_place_le > now() - interval '6 hours'),
         (SELECT p.statut FROM evenement_participants p
           WHERE p.evenement_id = e.id AND p.user_id = auth.uid()),
         COALESCE((SELECT p.sur_place_le > now() - interval '6 hours'
                   FROM evenement_participants p
                   WHERE p.evenement_id = e.id AND p.user_id = auth.uid()), false),
         (SELECT count(*)::int FROM parts p
            JOIN matches m ON (m.user1_id = auth.uid() AND m.user2_id = p.user_id)
                           OR (m.user2_id = auth.uid() AND m.user1_id = p.user_id)
           WHERE p.evenement_id = e.id AND p.actif),
         (SELECT count(*)::int FROM stories s
           WHERE s.evenement_id = e.id AND s.expires_at > now()),
         EXISTS (SELECT 1 FROM evenement_participants p
                  WHERE p.evenement_id = e.id AND p.user_id = auth.uid())
  FROM evenements e
  WHERE auth.uid() IS NOT NULL
    AND e.statut IN ('publie', 'annule')
    AND public.fin_evenement(e) > now()
  ORDER BY e.debut
  LIMIT 50;
$$;
REVOKE ALL ON FUNCTION public.evenements_a_venir() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.evenements_a_venir() TO authenticated;

-- Qui vient : mes matchs et mes likes d'abord, puis sur place, en ligne
DROP FUNCTION IF EXISTS public.participants_evenement(uuid);
CREATE FUNCTION public.participants_evenement(p_ev uuid)
RETURNS TABLE (id uuid, name text, photo_url text, username text,
               en_ligne boolean, inscrit_le timestamptz, statut text,
               sur_place boolean, est_match boolean, je_like boolean,
               dispo boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT x.* FROM (
    SELECT pr.id, pr.name::text, pr.photo_url::text, pr.username::text,
           COALESCE(pr.last_seen > now() - interval '30 minutes', false),
           p.created_at, p.statut,
           COALESCE(p.sur_place_le > now() - interval '6 hours', false),
           EXISTS (SELECT 1 FROM matches m
                    WHERE (m.user1_id = auth.uid() AND m.user2_id = pr.id)
                       OR (m.user2_id = auth.uid() AND m.user1_id = pr.id)),
           EXISTS (SELECT 1 FROM likes l
                    WHERE l.from_user_id = auth.uid() AND l.to_user_id = pr.id),
           COALESCE(pr.dispo_jusqua > now() AND pr.dispo_texte IS NOT NULL, false)
    FROM evenement_participants p
    JOIN profiles pr ON pr.id = p.user_id
    WHERE p.evenement_id = p_ev
      AND public.participe_evenement(p_ev, auth.uid())
      AND pr.id <> auth.uid()
      AND NOT COALESCE(pr.is_suspended, false)
      AND NOT public.blocage_entre(pr.id, auth.uid())
  ) x (id, name, photo_url, username, en_ligne, inscrit_le, statut,
       sur_place, est_match, je_like, dispo)
  ORDER BY x.est_match DESC, x.je_like DESC, x.sur_place DESC,
           x.en_ligne DESC, x.inscrit_le DESC
  LIMIT 300;
$$;
REVOKE ALL ON FUNCTION public.participants_evenement(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.participants_evenement(uuid) TO authenticated;

-- ── 6. Notifications à envoyer (tâche horaire) ─────────────────────
DROP FUNCTION IF EXISTS public.notifs_evenements_a_envoyer();
CREATE FUNCTION public.notifs_evenements_a_envoyer()
RETURNS TABLE (user_id uuid, fcm_token text, evenement_id uuid,
               type text, titre text, corps text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH ev AS (
    SELECT e.* FROM evenements e
    WHERE e.statut = 'publie' AND public.fin_evenement(e) > now()
  ),
  destinataires AS (
    SELECT pr.id, pr.fcm_token, pr.latitude, pr.longitude,
           COALESCE(pr.notif_nearby, true) AS proches
    FROM profiles pr
    WHERE COALESCE(pr.fcm_token, '') <> ''
      AND NOT COALESCE(pr.is_suspended, false)
  ),
  candidats AS (
    -- Rappel la veille (entre 3 h et 26 h avant)
    SELECT d.id, d.fcm_token, ev.id AS ev_id, 'veille'::text AS type,
           '📅 Demain : ' || ev.titre AS titre,
           'Tu y vas ? Retrouve les participants avant d''y être 👀' AS corps
    FROM ev
    JOIN evenement_participants p ON p.evenement_id = ev.id
    JOIN destinataires d ON d.id = p.user_id
    WHERE ev.debut > now() + interval '3 hours'
      AND ev.debut <= now() + interval '26 hours'

    UNION ALL
    -- Rappel 2 h avant
    SELECT d.id, d.fcm_token, ev.id, '2h',
           '⏰ Bientôt : ' || ev.titre,
           'Ça commence dans moins de 2 h. Arrivé ? Touche « Je suis sur place » 📍'
    FROM ev
    JOIN evenement_participants p ON p.evenement_id = ev.id
    JOIN destinataires d ON d.id = p.user_id
    WHERE ev.debut > now() AND ev.debut <= now() + interval '2 hours'

    UNION ALL
    -- « Des personnes que tu as likées y vont » (non participants)
    SELECT d.id, d.fcm_token, ev.id, 'likes',
           '💘 ' || count(*) ||
             CASE WHEN count(*) > 1 THEN ' personnes que tu as likées vont à '
                  ELSE ' personne que tu as likée va à ' END || ev.titre,
           'Dis « J''y vais » pour les retrouver sur place'
    FROM ev
    JOIN evenement_participants p ON p.evenement_id = ev.id AND p.statut = 'y_va'
    JOIN likes l ON l.to_user_id = p.user_id
    JOIN destinataires d ON d.id = l.from_user_id AND d.proches
    WHERE ev.debut > now() + interval '3 hours'
      AND ev.debut <= now() + interval '48 hours'
      AND NOT public.participe_evenement(ev.id, d.id)
      AND NOT public.blocage_entre(d.id, p.user_id)
    GROUP BY d.id, d.fcm_token, ev.id, ev.titre

    UNION ALL
    -- Nouvel événement près de toi (case cochée dans l'admin) : à moins
    -- de 50 km, ou tout le monde si l'événement n'a pas de position
    SELECT d.id, d.fcm_token, ev.id, 'nouveau',
           ev_emoji || ' Nouvel événement : ' || ev.titre,
           to_char(ev.debut AT TIME ZONE 'UTC', 'DD/MM à HH24"h"MI') || ' · ' || ev.lieu
    FROM (SELECT ev.*, CASE ev.categorie
                 WHEN 'sport' THEN '⚽' WHEN 'concert' THEN '🎤'
                 WHEN 'soiree' THEN '🎉' WHEN 'festival' THEN '🎪'
                 ELSE '📅' END AS ev_emoji
          FROM ev WHERE ev.notifier_proches AND ev.debut > now()) ev
    JOIN destinataires d ON d.proches
    WHERE ev.latitude IS NULL OR ev.longitude IS NULL
       OR (d.latitude IS NOT NULL AND d.longitude IS NOT NULL
           AND public.distance_km(ev.latitude, ev.longitude,
                                  d.latitude, d.longitude) <= 50)
  )
  SELECT c.id, c.fcm_token, c.ev_id, c.type, c.titre, c.corps
  FROM candidats c
  WHERE NOT EXISTS (SELECT 1 FROM evenement_notifs n
                    WHERE n.evenement_id = c.ev_id AND n.user_id = c.id
                      AND n.type = c.type)
  LIMIT 3000;
$$;
REVOKE ALL ON FUNCTION public.notifs_evenements_a_envoyer() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notifs_evenements_a_envoyer() TO service_role;

COMMIT;

-- ── 7. Tâche planifiée : toutes les heures (même secret que la purge) ──
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rappel-evenements') THEN
    PERFORM cron.unschedule('rappel-evenements');
  END IF;
END $$;

SELECT cron.schedule(
  'rappel-evenements',
  '5 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/rappel-evenements',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'purge_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  );
  $cron$
);

NOTIFY pgrst, 'reload schema';

-- Aperçu (sans rien envoyer) :
-- SELECT type, titre, count(*) FROM public.notifs_evenements_a_envoyer() GROUP BY 1, 2;
