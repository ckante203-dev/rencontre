-- ═══════════════════════════════════════════════════════════════════
-- Panneau admin : nouvelles pages (Boosts, Albums privés, Purge,
-- Pseudos & amis) — 2026-10-06
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Tout passe par des fonctions réservées aux admins (public.is_admin()) :
-- les tables boost_achats, storage_a_supprimer, amities, cron.* restent
-- fermées aux utilisateurs.
-- Rien ne change pour l'app (aucune version requise).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 0. Garde ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._exiger_admin()
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT COALESCE(public.is_admin(), false) THEN
    RAISE EXCEPTION 'reserve_admin' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._exiger_admin() FROM public, anon;
GRANT EXECUTE ON FUNCTION public._exiger_admin() TO authenticated;

-- ─── 1. Boosts ──────────────────────────────────────────────────────
-- Achats et boosts offerts des p_jours derniers jours
CREATE OR REPLACE FUNCTION public.admin_boost_achats(p_jours int DEFAULT 7)
RETURNS TABLE (transaction_id text, user_id uuid, name text, produit text,
               minutes int, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT b.transaction_id, b.user_id, p.name::text, b.produit, b.minutes,
           b.created_at
      FROM boost_achats b
      LEFT JOIN profiles p ON p.id = b.user_id
     WHERE b.created_at > now() - make_interval(days => GREATEST(p_jours, 1))
     ORDER BY b.created_at DESC
     LIMIT 500;
END;
$$;

-- Offrir un boost (même chemin qu'un achat : prolonge s'il est en cours)
CREATE OR REPLACE FUNCTION public.admin_offrir_boost(p_user uuid, p_minutes int)
RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  IF p_minutes IS NULL OR p_minutes < 15 OR p_minutes > 7 * 24 * 60 THEN
    RAISE EXCEPTION 'duree_invalide' USING ERRCODE = 'P0001';
  END IF;
  RETURN public.appliquer_boost(p_user, 'admin:' || gen_random_uuid(),
                                'offert_admin', p_minutes);
END;
$$;

-- Arrêter un boost en cours (abus, demande de la personne…)
CREATE OR REPLACE FUNCTION public.admin_arreter_boost(p_user uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  UPDATE profiles SET boost_jusqua = now()
   WHERE id = p_user AND boost_jusqua > now();
END;
$$;

-- ─── 2. Albums privés : les admins voient et suppriment ─────────────
-- (uniquement pour traiter un signalement)
DROP POLICY IF EXISTS album_photos_admin ON public.album_photos;
CREATE POLICY album_photos_admin ON public.album_photos
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS albums_lecture_admin ON storage.objects;
CREATE POLICY albums_lecture_admin ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'albums' AND public.is_admin());

DROP POLICY IF EXISTS albums_suppression_admin ON storage.objects;
CREATE POLICY albums_suppression_admin ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'albums' AND public.is_admin());

-- ─── 3. Purge & stockage ────────────────────────────────────────────
-- Ce qui attend d'être purgé : si ces chiffres grimpent, la purge
-- automatique ne passe plus. + 10 derniers passages de la tâche pg_cron.
CREATE OR REPLACE FUNCTION public.admin_purge_etat()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v jsonb;
  v_passages jsonb := '[]'::jsonb;
BEGIN
  PERFORM public._exiger_admin();

  SELECT jsonb_build_object(
    'stories_expirees', (SELECT count(*) FROM stories
                          WHERE expires_at < now() - interval '30 minutes'),
    'messages_a_purger', (SELECT count(*) FROM messages
                           WHERE read_at < now() - interval '25 hours'),
    'fichiers_en_attente', (SELECT count(*) FROM storage_a_supprimer),
    'plus_ancien_fichier', (SELECT min(created_at) FROM storage_a_supprimer)
  ) INTO v;

  BEGIN
    SELECT COALESCE(jsonb_agg(x ORDER BY x.debut DESC), '[]'::jsonb)
      INTO v_passages
      FROM (SELECT d.start_time AS debut, d.end_time AS fin, d.status,
                   left(d.return_message, 200) AS message
              FROM cron.job_run_details d
              JOIN cron.job j ON j.jobid = d.jobid
             WHERE j.jobname = 'purge-expired'
             ORDER BY d.start_time DESC
             LIMIT 10) x;
  EXCEPTION WHEN OTHERS THEN
    v_passages := '[]'::jsonb;  -- pg_cron illisible : on n'affiche rien
  END;

  RETURN v || jsonb_build_object('passages', v_passages);
END;
$$;

-- Espace occupé par bucket (Storage)
CREATE OR REPLACE FUNCTION public.admin_stockage()
RETURNS TABLE (bucket text, fichiers bigint, octets bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, storage
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT o.bucket_id::text, count(*)::bigint,
           COALESCE(sum((o.metadata->>'size')::bigint), 0)::bigint
      FROM storage.objects o
     GROUP BY o.bucket_id
     ORDER BY 3 DESC;
END;
$$;

-- ─── 4. Pseudos & amis : chiffres ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_stats_sociales()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN jsonb_build_object(
    'comptes', (SELECT count(*) FROM profiles),
    'avec_pseudo', (SELECT count(*) FROM profiles WHERE username IS NOT NULL),
    'introuvables', (SELECT count(*) FROM profiles
                      WHERE NOT COALESCE(trouvable_par_pseudo, true)),
    'amities', (SELECT count(*) FROM amities WHERE statut = 'acceptee'),
    'demandes_7j', (SELECT count(*) FROM amities
                     WHERE created_at > now() - interval '7 days'),
    'acceptees_7j', (SELECT count(*) FROM amities
                      WHERE created_at > now() - interval '7 days'
                        AND statut = 'acceptee'),
    'en_attente', (SELECT count(*) FROM amities WHERE statut = 'en_attente')
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_boost_achats(int) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_offrir_boost(uuid, int) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_arreter_boost(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_purge_etat() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_stockage() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_stats_sociales() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_boost_achats(int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_offrir_boost(uuid, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_arreter_boost(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_purge_etat() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_stockage() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_stats_sociales() TO authenticated;

COMMIT;

-- Vérification (doit renvoyer 6 lignes)
SELECT proname FROM pg_proc
 WHERE proname IN ('admin_boost_achats', 'admin_offrir_boost',
                   'admin_arreter_boost', 'admin_purge_etat',
                   'admin_stockage', 'admin_stats_sociales');
