-- ═══════════════════════════════════════════════════════════════════
-- Pouls de Zamu (activité en direct) + vues des stories Zamu — 2026-10-17
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- 1. pouls_heure : relevé de l'activité heure par heure, mis à jour
--    toutes les 10 minutes par pg_cron (les messages lus étant purgés au
--    bout de 24 h, on garde ici l'historique pour comparer avec la
--    semaine dernière). Les 8 derniers jours sont reconstitués au
--    lancement (inscriptions, likes, matchs ; messages en partie).
-- 2. admin_pouls() : chiffres en direct + série horaire pour la page
--    « Pouls de Zamu » du panneau admin.
-- 3. Vues des stories officielles : l'app (1.1.9) enregistre chaque vue,
--    le panneau admin affiche le total sous chaque story.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Relevé horaire ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pouls_heure (
  heure         timestamptz PRIMARY KEY,      -- début de l'heure (UTC = heure d'Abidjan)
  en_ligne_max  int NOT NULL DEFAULT 0,       -- pic de personnes en ligne (≤ 5 min)
  actifs        int NOT NULL DEFAULT 0,       -- personnes vues pendant l'heure
  messages      int NOT NULL DEFAULT 0,
  likes         int NOT NULL DEFAULT 0,
  matchs        int NOT NULL DEFAULT 0,
  inscriptions  int NOT NULL DEFAULT 0,
  maj_le        timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.pouls_heure ENABLE ROW LEVEL SECURITY;   -- lu seulement via admin_pouls()

CREATE OR REPLACE FUNCTION public.pouls_enregistrer()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  h timestamptz := date_trunc('hour', now());
BEGIN
  INSERT INTO pouls_heure AS p (heure, en_ligne_max, actifs, messages, likes, matchs, inscriptions, maj_le)
  VALUES (h,
    (SELECT count(*) FROM profiles WHERE last_seen > now() - interval '5 minutes'),
    (SELECT count(*) FROM profiles WHERE last_seen >= h),
    (SELECT count(*) FROM messages WHERE created_at >= h),
    (SELECT count(*) FROM likes WHERE created_at >= h),
    (SELECT count(*) FROM matches WHERE created_at >= h),
    (SELECT count(*) FROM profiles WHERE created_at >= h),
    now())
  ON CONFLICT (heure) DO UPDATE SET
    en_ligne_max = GREATEST(p.en_ligne_max, EXCLUDED.en_ligne_max),
    actifs       = GREATEST(p.actifs, EXCLUDED.actifs),
    messages     = GREATEST(p.messages, EXCLUDED.messages),
    likes        = GREATEST(p.likes, EXCLUDED.likes),
    matchs       = GREATEST(p.matchs, EXCLUDED.matchs),
    inscriptions = GREATEST(p.inscriptions, EXCLUDED.inscriptions),
    maj_le       = now();
END;
$$;
REVOKE ALL ON FUNCTION public.pouls_enregistrer() FROM public, anon, authenticated;

-- Historique reconstitué (8 jours) : ce qui existe encore dans les tables
INSERT INTO public.pouls_heure (heure, messages, likes, matchs, inscriptions)
SELECT h,
  (SELECT count(*) FROM public.messages WHERE created_at >= h AND created_at < h + interval '1 hour'),
  (SELECT count(*) FROM public.likes    WHERE created_at >= h AND created_at < h + interval '1 hour'),
  (SELECT count(*) FROM public.matches  WHERE created_at >= h AND created_at < h + interval '1 hour'),
  (SELECT count(*) FROM public.profiles WHERE created_at >= h AND created_at < h + interval '1 hour')
FROM generate_series(date_trunc('hour', now()) - interval '8 days',
                     date_trunc('hour', now()) - interval '1 hour', interval '1 hour') h
ON CONFLICT (heure) DO NOTHING;

-- Toutes les 10 minutes
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pouls-zamu') THEN
    PERFORM cron.unschedule('pouls-zamu');
  END IF;
END $$;
SELECT cron.schedule('pouls-zamu', '*/10 * * * *', 'SELECT public.pouls_enregistrer()');

-- ─── 2. Page « Pouls de Zamu » ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_pouls()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_off uuid;
BEGIN
  PERFORM public._exiger_admin();
  PERFORM public.pouls_enregistrer();          -- l'heure en cours est à jour
  SELECT id INTO v_off FROM profiles WHERE COALESCE(est_officiel, false) ORDER BY created_at LIMIT 1;
  RETURN jsonb_build_object(
    'maintenant', now(),
    'en_ligne_5min',  (SELECT count(*) FROM profiles WHERE last_seen > now() - interval '5 minutes'),
    'en_ligne_30min', (SELECT count(*) FROM profiles WHERE last_seen > now() - interval '30 minutes'),
    'messages_1h',    (SELECT count(*) FROM messages WHERE created_at > now() - interval '1 hour'),
    'likes_1h',       (SELECT count(*) FROM likes WHERE created_at > now() - interval '1 hour'),
    'matchs_1h',      (SELECT count(*) FROM matches WHERE created_at > now() - interval '1 hour'),
    'inscriptions_24h', (SELECT count(*) FROM profiles WHERE created_at > now() - interval '24 hours'),
    'derniere_inscription', (SELECT max(created_at) FROM profiles WHERE NOT COALESCE(est_officiel, false)),
    -- Nouveaux (48 h) qui n'ont encore envoyé ni like ni message (hors Zamu)
    'nouveaux_inactifs', (SELECT count(*) FROM profiles p
        WHERE p.created_at > now() - interval '48 hours' AND COALESCE(p.onboarding_complete, false)
          AND NOT COALESCE(p.est_officiel, false)
          AND NOT EXISTS (SELECT 1 FROM likes l WHERE l.from_user_id = p.id)
          AND NOT EXISTS (SELECT 1 FROM messages m WHERE m.sender_id = p.id
                            AND m.conversation_id NOT IN (SELECT c.id FROM conversations c
                                                           WHERE v_off IN (c.user1_id, c.user2_id)))),
    'signalements_24h', (SELECT count(*) FROM reports WHERE created_at > now() - interval '24 hours'),
    'serie', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                 'heure', heure, 'en_ligne', en_ligne_max, 'actifs', actifs, 'messages', messages,
                 'likes', likes, 'matchs', matchs, 'inscriptions', inscriptions) ORDER BY heure), '[]'::jsonb)
              FROM pouls_heure WHERE heure > now() - interval '8 days 1 hour')
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_pouls() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_pouls() TO authenticated;

-- ─── 3. Vues des stories officielles ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.stories_officielles_vues (
  story_id uuid NOT NULL REFERENCES public.stories_officielles(id) ON DELETE CASCADE,
  user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  vu_le    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, user_id)
);
ALTER TABLE public.stories_officielles_vues ENABLE ROW LEVEL SECURITY;   -- écrit via la fonction

CREATE OR REPLACE FUNCTION public.vue_story_officielle(p_story uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  INSERT INTO stories_officielles_vues (story_id, user_id)
  SELECT p_story, auth.uid()
   WHERE auth.uid() IS NOT NULL
     AND EXISTS (SELECT 1 FROM stories_officielles WHERE id = p_story)
  ON CONFLICT DO NOTHING;
$$;
REVOKE ALL ON FUNCTION public.vue_story_officielle(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.vue_story_officielle(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_vues_stories_zamu()
RETURNS TABLE (story_id uuid, vues int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY SELECT v.story_id, count(*)::int FROM stories_officielles_vues v GROUP BY v.story_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_vues_stories_zamu() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_vues_stories_zamu() TO authenticated;

COMMIT;

-- Vérification
SELECT count(*) AS heures_enregistrees, max(heure) AS derniere FROM public.pouls_heure;
