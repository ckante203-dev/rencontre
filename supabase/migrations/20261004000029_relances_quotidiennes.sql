-- ═══════════════════════════════════════════════════════════════════
-- Notifications de relance quotidiennes — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
-- À exécuter APRÈS le déploiement de l'edge function relance-quotidienne.
--
-- Chaque jour à 19 h (heure d'Abidjan = UTC) : une notification
-- personnalisée aux personnes qui n'ont pas ouvert Zamu depuis 24 h,
-- seulement si on a un vrai chiffre à leur donner. Une seule par jour, et
-- tous les 3 jours après une semaine d'absence ; plus rien après 30 jours.
-- Par ordre de priorité :
--   1. 💬 messages non lus           (réglage notif_messages)
--   2. 👀 visites de profil           (depuis la dernière visite, 3 j max)
--   3. 🙋 personnes « Dispo » à < 50 km (réglage notif_nearby)
--   4. 📸 au moins 2 nouvelles stories (réglage notif_stories)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS derniere_relance timestamptz;

CREATE OR REPLACE FUNCTION public.relances_du_jour()
RETURNS TABLE (
  user_id uuid, fcm_token text, titre text, corps text,
  type text, filtre text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  p record;
  n int;
BEGIN
  FOR p IN
    SELECT pr.id, pr.fcm_token AS jeton, pr.latitude AS lat,
           pr.longitude AS lon, pr.last_seen AS vu,
           COALESCE(pr.notif_messages, true) AS nm,
           COALESCE(pr.notif_nearby, true)   AS nn,
           COALESCE(pr.notif_stories, true)  AS ns
    FROM profiles pr
    WHERE COALESCE(pr.fcm_token, '') <> ''
      AND NOT COALESCE(pr.is_suspended, false)
      AND pr.last_seen < now() - interval '24 hours'
      AND pr.last_seen > now() - interval '30 days'
      AND (pr.derniere_relance IS NULL
           OR pr.derniere_relance < now() - CASE
                WHEN pr.last_seen > now() - interval '7 days'
                THEN interval '20 hours' ELSE interval '68 hours' END)
  LOOP
    user_id := p.id;
    fcm_token := p.jeton;
    filtre := NULL;

    -- 1. Messages non lus
    IF p.nm THEN
      SELECT count(*) INTO n
      FROM messages m
      JOIN conversations c ON c.id = m.conversation_id
      WHERE (c.user1_id = p.id OR c.user2_id = p.id)
        AND m.sender_id <> p.id
        AND m.is_read IS NOT TRUE
        AND m.status IS DISTINCT FROM 'read'
        AND NOT public.blocage_entre(p.id, m.sender_id);
      IF n > 0 THEN
        titre := '💬 ' || n || CASE WHEN n > 1
                   THEN ' messages t''attendent' ELSE ' message t''attend' END;
        corps := 'Réponds avant que la conversation refroidisse 😉';
        type := 'reengagement';
        filtre := 'messages';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;

    -- 2. Visites de profil
    SELECT count(*) INTO n
    FROM profile_views v
    WHERE v.viewed_id = p.id
      AND v.viewer_id <> p.id
      AND v.created_at > greatest(p.vu, now() - interval '3 days');
    IF n > 0 THEN
      titre := '👀 ' || n || CASE WHEN n > 1
                 THEN ' personnes ont vu ton profil'
                 ELSE ' personne a vu ton profil' END;
      corps := 'Découvre qui s''intéresse à toi';
      type := 'profile_views';
      RETURN NEXT;
      CONTINUE;
    END IF;

    -- 3. Personnes « Dispo maintenant » à moins de 50 km
    IF p.nn AND p.lat IS NOT NULL AND p.lon IS NOT NULL THEN
      SELECT count(*) INTO n
      FROM profiles o
      WHERE o.id <> p.id
        AND o.dispo_texte IS NOT NULL
        AND o.dispo_jusqua > now()
        AND NOT COALESCE(o.is_suspended, false)
        AND o.latitude IS NOT NULL AND o.longitude IS NOT NULL
        AND 12742 * asin(sqrt(
              power(sin(radians(o.latitude - p.lat) / 2), 2)
              + cos(radians(p.lat)) * cos(radians(o.latitude))
                * power(sin(radians(o.longitude - p.lon) / 2), 2))) <= 50
        AND NOT public.blocage_entre(p.id, o.id);
      IF n > 0 THEN
        titre := '🙋 ' || n || CASE WHEN n > 1
                   THEN ' personnes près de toi sont dispo'
                   ELSE ' personne près de toi est dispo' END;
        corps := 'Café, sortie, discussion… vois qui est partant';
        type := 'reengagement';
        filtre := 'dispo';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;

    -- 4. Nouvelles stories depuis la dernière visite
    IF p.ns THEN
      SELECT count(*) INTO n
      FROM stories s
      WHERE s.user_id <> p.id
        AND s.expires_at > now()
        AND s.created_at > p.vu
        AND (s.moderation_status IS NULL
             OR s.moderation_status IN ('approved', 'unchecked'))
        AND NOT public.blocage_entre(p.id, s.user_id);
      IF n >= 2 THEN
        titre := '📸 ' || n || ' nouvelles stories';
        corps := 'Depuis ta dernière visite sur Zamu';
        type := 'new_story';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.relances_du_jour() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.relances_du_jour() TO service_role;

COMMIT;

-- Tâche planifiée : tous les jours à 19 h UTC (= 19 h à Abidjan).
-- Même secret que la purge (Vault purge_secret = env PURGE_SECRET).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'relance-quotidienne') THEN
    PERFORM cron.unschedule('relance-quotidienne');
  END IF;
END $$;

SELECT cron.schedule(
  'relance-quotidienne',
  '0 19 * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/relance-quotidienne',
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

-- Aperçu (sans rien envoyer) : qui recevrait quoi ce soir ?
-- SELECT user_id, titre, corps, type, filtre FROM public.relances_du_jour();
