-- ═══════════════════════════════════════════════════════════════════
-- « Tu as croisé… » après un événement — 2026-10-05
-- À exécuter dans Supabase → SQL Editor, APRÈS 035. Ré-exécutable.
--
-- Le lendemain d'un événement, chaque participant (« J'y vais » ou
-- « Je suis sur place ») reçoit : « 👋 Awa et 4 autres étaient aussi à
-- Soirée X. Dis-leur bonjour ! ». Le tap ouvre l'événement terminé, avec
-- la liste « Ils étaient là aussi » (participants_evenement, inchangé).
-- • evenement_par_id(p_ev) : un événement, même terminé (7 jours), pour
--   l'ouvrir depuis la notification.
-- • croises_a_notifier() : envoyé par rappel-evenements (cron horaire),
--   entre 10 h et 20 h (heure d'Abidjan = UTC), 8 h à 48 h après la fin.
--   Une seule fois par événement (evenement_notifs, type « croises »).
-- Compatible 1.0.11 : nouvelles fonctions seulement.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Un événement par son id, même terminé depuis moins de 7 jours
DROP FUNCTION IF EXISTS public.evenement_par_id(uuid);
CREATE FUNCTION public.evenement_par_id(p_ev uuid)
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
    WHERE p.evenement_id = p_ev
  )
  SELECT e.id, e.titre, e.description, e.categorie, e.lieu, e.ville,
         e.latitude, e.longitude, e.debut, e.fin, e.image_url, e.statut,
         (SELECT count(*)::int FROM parts p
           WHERE p.actif AND p.statut = 'y_va'),
         (SELECT count(*)::int FROM parts p
           WHERE p.actif AND p.statut = 'interesse'),
         (SELECT count(*)::int FROM parts p
           WHERE p.actif AND p.sur_place_le > now() - interval '6 hours'),
         (SELECT p.statut FROM parts p WHERE p.user_id = auth.uid()),
         COALESCE((SELECT p.sur_place_le > now() - interval '6 hours'
                   FROM parts p WHERE p.user_id = auth.uid()), false),
         (SELECT count(*)::int FROM parts p
            JOIN matches m ON (m.user1_id = auth.uid() AND m.user2_id = p.user_id)
                           OR (m.user2_id = auth.uid() AND m.user1_id = p.user_id)
           WHERE p.actif),
         (SELECT count(*)::int FROM stories s
           WHERE s.evenement_id = e.id AND s.expires_at > now()),
         EXISTS (SELECT 1 FROM parts p WHERE p.user_id = auth.uid())
  FROM evenements e
  WHERE e.id = p_ev
    AND auth.uid() IS NOT NULL
    AND e.statut IN ('publie', 'annule')
    AND public.fin_evenement(e) > now() - interval '7 days';
$$;
REVOKE ALL ON FUNCTION public.evenement_par_id(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.evenement_par_id(uuid) TO authenticated;

-- « Tu as croisé… » à envoyer (edge function, service_role)
DROP FUNCTION IF EXISTS public.croises_a_notifier();
CREATE FUNCTION public.croises_a_notifier()
RETURNS TABLE (user_id uuid, fcm_token text, evenement_id uuid,
               titre text, corps text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH ev AS (
    SELECT e.id, e.titre FROM evenements e
    WHERE e.statut = 'publie'
      AND public.fin_evenement(e) <= now() - interval '8 hours'
      AND public.fin_evenement(e) >  now() - interval '48 hours'
      -- en journée seulement (Abidjan = UTC)
      AND extract(hour FROM now() AT TIME ZONE 'UTC') BETWEEN 10 AND 19
  ),
  presents AS (
    -- « J'y vais » ou passé « sur place » (les « Intéressé » ne comptent pas)
    SELECT p.evenement_id, p.user_id, pr.name, pr.fcm_token,
           p.sur_place_le IS NOT NULL AS sur_place
    FROM evenement_participants p
    JOIN ev ON ev.id = p.evenement_id
    JOIN profiles pr ON pr.id = p.user_id
    WHERE (p.statut = 'y_va' OR p.sur_place_le IS NOT NULL)
      AND NOT COALESCE(pr.is_suspended, false)
  ),
  paires AS (
    SELECT moi.evenement_id, moi.user_id, moi.fcm_token,
           count(*)::int AS nb,
           -- un prénom à citer : de préférence quelqu'un venu sur place
           (array_agg(split_part(autre.name, ' ', 1)
                      ORDER BY autre.sur_place DESC, autre.user_id))[1] AS nom
    FROM presents moi
    JOIN presents autre
      ON autre.evenement_id = moi.evenement_id
     AND autre.user_id <> moi.user_id
     AND NOT public.blocage_entre(autre.user_id, moi.user_id)
    WHERE COALESCE(moi.fcm_token, '') <> ''
      AND NOT EXISTS (SELECT 1 FROM evenement_notifs n
                       WHERE n.evenement_id = moi.evenement_id
                         AND n.user_id = moi.user_id
                         AND n.type = 'croises')
    GROUP BY moi.evenement_id, moi.user_id, moi.fcm_token
  )
  SELECT pa.user_id, pa.fcm_token, pa.evenement_id,
         '👋 Tu as croisé du monde à ' || ev.titre,
         CASE
           WHEN pa.nb = 1 THEN
             COALESCE(NULLIF(pa.nom, ''), 'Quelqu''un')
             || ' était aussi là. Dis-lui bonjour !'
           ELSE
             COALESCE(NULLIF(pa.nom, ''), 'Quelqu''un') || ' et '
             || (pa.nb - 1) || CASE WHEN pa.nb - 1 > 1 THEN ' autres' ELSE ' autre' END
             || ' étaient aussi là. Dis-leur bonjour !'
         END
  FROM paires pa
  JOIN ev ON ev.id = pa.evenement_id
  LIMIT 2000;
$$;
REVOKE ALL ON FUNCTION public.croises_a_notifier() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.croises_a_notifier() TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
