-- ═══════════════════════════════════════════════════════════════════
-- Statistiques du panneau admin — 2026-10-14
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- 1. activite_jour      : 1 ligne par utilisateur et par jour d'ouverture
--                         (remplie par un déclencheur sur profiles.last_seen,
--                         marche avec TOUTES les versions de l'app).
-- 2. versions_historique: chaque passage d'une version à une autre.
-- 3. achats_journal     : chaque événement RevenueCat (achat, renouvellement,
--                         annulation, expiration, Boost…), écrit par le
--                         webhook revenuecat-webhook (fonction swift-service).
-- 4. admin_statistiques(début, fin) : tout ce qu'affiche la page
--                         « Statistiques » (réservée aux admins).
-- Les jours sont comptés en UTC (= heure d'Abidjan).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Activité quotidienne ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.activite_jour (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  jour    date NOT NULL,
  version text,
  PRIMARY KEY (user_id, jour)
);
CREATE INDEX IF NOT EXISTS activite_jour_jour ON public.activite_jour (jour);
ALTER TABLE public.activite_jour ENABLE ROW LEVEL SECURITY;  -- aucune règle : fermée aux utilisateurs

-- ─── 2. Historique des mises à jour ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.versions_historique (
  id            bigserial PRIMARY KEY,
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  version_avant text,
  version_apres text NOT NULL,
  le            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS versions_historique_le ON public.versions_historique (le);
ALTER TABLE public.versions_historique ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public._noter_activite()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Première activité du jour (la présence met last_seen à jour souvent :
  -- on n'écrit qu'une fois par jour) ou changement de version.
  IF NEW.last_seen IS NOT NULL AND (
       OLD.last_seen IS NULL
       OR (OLD.last_seen AT TIME ZONE 'UTC')::date <> (NEW.last_seen AT TIME ZONE 'UTC')::date
       OR NEW.app_version IS DISTINCT FROM OLD.app_version) THEN
    INSERT INTO activite_jour (user_id, jour, version)
    VALUES (NEW.id, (NEW.last_seen AT TIME ZONE 'UTC')::date, NEW.app_version)
    ON CONFLICT (user_id, jour) DO UPDATE SET version = EXCLUDED.version
      WHERE activite_jour.version IS DISTINCT FROM EXCLUDED.version;
  END IF;
  IF NEW.app_version IS NOT NULL AND NEW.app_version IS DISTINCT FROM OLD.app_version THEN
    INSERT INTO versions_historique (user_id, version_avant, version_apres)
    VALUES (NEW.id, OLD.app_version, NEW.app_version);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;  -- les statistiques ne doivent jamais bloquer l'app
END;
$$;

DROP TRIGGER IF EXISTS profiles_noter_activite ON public.profiles;
CREATE TRIGGER profiles_noter_activite
  AFTER UPDATE OF last_seen, app_version ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._noter_activite();

-- Point de départ : la dernière activité connue de chacun
INSERT INTO public.activite_jour (user_id, jour, version)
SELECT id, (last_seen AT TIME ZONE 'UTC')::date, app_version
  FROM public.profiles WHERE last_seen IS NOT NULL
ON CONFLICT DO NOTHING;

-- ─── 3. Journal des achats (écrit par le webhook RevenueCat) ────────
CREATE TABLE IF NOT EXISTS public.achats_journal (
  id           bigserial PRIMARY KEY,
  event_id     text UNIQUE,
  user_id      uuid,
  type         text NOT NULL,       -- INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, NON_RENEWING_PURCHASE…
  produit      text,
  prix_usd     numeric,             -- prix en dollars calculé par RevenueCat
  prix_local   numeric,
  devise       text,
  pays         text,
  environnement text,               -- PRODUCTION ou SANDBOX
  le           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS achats_journal_le ON public.achats_journal (le);
ALTER TABLE public.achats_journal ENABLE ROW LEVEL SECURITY;

-- ─── 4. Fonctions de la page Statistiques ───────────────────────────
-- Nombre de lignes d'une table entre deux jours (0 si la table n'existe pas)
CREATE OR REPLACE FUNCTION public._stat_compte(p_table text, p_debut date, p_fin date,
                                               p_filtre text DEFAULT 'true')
RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE n bigint;
BEGIN
  IF to_regclass('public.' || p_table) IS NULL THEN RETURN 0; END IF;
  EXECUTE format('SELECT count(*) FROM public.%I WHERE created_at >= $1 AND created_at < $2 + 1 AND (%s)',
                 p_table, p_filtre)
    INTO n USING p_debut::timestamptz, p_fin;
  RETURN n;
EXCEPTION WHEN OTHERS THEN RETURN 0;
END;
$$;

-- Nombre de lignes par jour, sur toute la période (jours vides = 0)
CREATE OR REPLACE FUNCTION public._stat_par_jour(p_table text, p_debut date, p_fin date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE r jsonb;
BEGIN
  IF to_regclass('public.' || p_table) IS NULL THEN RETURN '[]'::jsonb; END IF;
  EXECUTE format($q$
    SELECT COALESCE(jsonb_agg(COALESCE(c.n, 0) ORDER BY j.jour), '[]'::jsonb)
      FROM generate_series($1, $2, interval '1 day') AS j(jour)
      LEFT JOIN (SELECT (created_at AT TIME ZONE 'UTC')::date AS jour, count(*) AS n
                   FROM public.%I
                  WHERE created_at >= $1::timestamptz AND created_at < $2 + 1
                  GROUP BY 1) c ON c.jour = j.jour::date$q$, p_table)
    INTO r USING p_debut, p_fin;
  RETURN r;
EXCEPTION WHEN OTHERS THEN RETURN '[]'::jsonb;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_statistiques(p_debut date, p_fin date)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_debut date := LEAST(p_debut, p_fin);
  v_fin   date := GREATEST(p_debut, p_fin);
  v_res   jsonb;
BEGIN
  PERFORM public._exiger_admin();
  IF v_fin - v_debut > 366 THEN v_debut := v_fin - 366; END IF;

  WITH
  jours AS (SELECT j::date AS jour FROM generate_series(v_debut, v_fin, interval '1 day') j),
  actifs_jour AS (
    SELECT j.jour, count(a.user_id) AS n
      FROM jours j LEFT JOIN activite_jour a ON a.jour = j.jour
     GROUP BY j.jour),
  achats AS (
    SELECT * FROM achats_journal
     WHERE le >= v_debut AND le < v_fin + 1
       AND COALESCE(environnement, 'PRODUCTION') = 'PRODUCTION'),
  cohorte AS (
    SELECT id, (created_at AT TIME ZONE 'UTC')::date AS j0, onboarding_complete
      FROM profiles WHERE created_at >= v_debut AND created_at < v_fin + 1)
  SELECT jsonb_build_object(
    'debut', v_debut, 'fin', v_fin,
    'jours', (SELECT jsonb_agg(jour ORDER BY jour) FROM jours),

    -- Chiffres clés
    'inscriptions', (SELECT count(*) FROM cohorte),
    'actifs', (SELECT count(DISTINCT user_id) FROM activite_jour WHERE jour BETWEEN v_debut AND v_fin),
    'actifs_moyen_jour', (SELECT round(avg(n), 1) FROM actifs_jour),
    'total_comptes', (SELECT count(*) FROM profiles),
    'premium_actifs', (SELECT count(*) FROM profiles WHERE is_premium),

    -- Abonnements et achats (journal du webhook)
    'abonnements', jsonb_build_object(
      'nouveaux',       (SELECT count(*) FROM achats WHERE type = 'INITIAL_PURCHASE'),
      'renouvellements',(SELECT count(*) FROM achats WHERE type = 'RENEWAL'),
      'annulations',    (SELECT count(*) FROM achats WHERE type = 'CANCELLATION'),
      'expirations',    (SELECT count(*) FROM achats WHERE type = 'EXPIRATION'),
      'boosts',         (SELECT count(*) FROM achats WHERE type = 'NON_RENEWING_PURCHASE'),
      'revenus_usd',    (SELECT round(COALESCE(sum(prix_usd), 0), 2) FROM achats
                          WHERE type IN ('INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE')),
      'par_produit', (SELECT COALESCE(jsonb_object_agg(produit, n), '{}'::jsonb) FROM (
                        SELECT COALESCE(produit, '?') AS produit, count(*) AS n FROM achats
                         WHERE type IN ('INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE')
                         GROUP BY 1) x),
      'par_pays', (SELECT COALESCE(jsonb_object_agg(pays, n), '{}'::jsonb) FROM (
                        SELECT COALESCE(pays, '?') AS pays, count(*) AS n FROM achats
                         WHERE type IN ('INITIAL_PURCHASE', 'RENEWAL', 'NON_RENEWING_PURCHASE')
                         GROUP BY 1) x),
      'par_jour', (SELECT jsonb_agg(COALESCE(c.n, 0) ORDER BY j.jour) FROM jours j
                     LEFT JOIN (SELECT (le AT TIME ZONE 'UTC')::date AS jour, count(*) AS n FROM achats
                                 WHERE type IN ('INITIAL_PURCHASE', 'RENEWAL') GROUP BY 1) c
                       ON c.jour = j.jour),
      'journal_depuis', (SELECT min(le) FROM achats_journal)),

    -- Mises à jour de l'app
    'versions_actifs_30j', (SELECT COALESCE(jsonb_object_agg(v, n), '{}'::jsonb) FROM (
        SELECT COALESCE(app_version, 'inconnue') AS v, count(*) AS n FROM profiles
         WHERE last_seen > now() - interval '30 days' GROUP BY 1) x),
    'mises_a_jour', (SELECT count(*) FROM versions_historique
                      WHERE le >= v_debut AND le < v_fin + 1 AND version_avant IS NOT NULL),
    'mises_a_jour_par_version', (SELECT COALESCE(jsonb_object_agg(version_apres, n), '{}'::jsonb) FROM (
        SELECT version_apres, count(*) AS n FROM versions_historique
         WHERE le >= v_debut AND le < v_fin + 1 AND version_avant IS NOT NULL GROUP BY 1) x),
    'mises_a_jour_par_jour', (SELECT jsonb_agg(COALESCE(c.n, 0) ORDER BY j.jour) FROM jours j
        LEFT JOIN (SELECT (le AT TIME ZONE 'UTC')::date AS jour, count(*) AS n FROM versions_historique
                    WHERE version_avant IS NOT NULL GROUP BY 1) c ON c.jour = j.jour),

    -- Courbes par jour
    'actifs_par_jour', (SELECT jsonb_agg(n ORDER BY jour) FROM actifs_jour),
    'inscriptions_par_jour', public._stat_par_jour('profiles', v_debut, v_fin),
    'messages_par_jour', public._stat_par_jour('messages', v_debut, v_fin),
    'likes_par_jour', public._stat_par_jour('likes', v_debut, v_fin),
    'matchs_par_jour', public._stat_par_jour('matches', v_debut, v_fin),
    'stories_par_jour', public._stat_par_jour('stories', v_debut, v_fin),

    -- Usage des fonctionnalités sur la période
    'usage', jsonb_build_object(
      'Likes',               public._stat_compte('likes', v_debut, v_fin),
      'Super Likes',         public._stat_compte('likes', v_debut, v_fin, 'est_super'),
      'Matchs',              public._stat_compte('matches', v_debut, v_fin),
      'Messages',            public._stat_compte('messages', v_debut, v_fin),
      'Snaps',               public._stat_compte('snaps', v_debut, v_fin),
      'Stories publiées',    public._stat_compte('stories', v_debut, v_fin),
      'Stories à la une',    public._stat_compte('stories_une', v_debut, v_fin),
      'Vues de profil',      public._stat_compte('profile_views', v_debut, v_fin),
      'Favoris',             public._stat_compte('favoris', v_debut, v_fin),
      'Messages de groupe',  public._stat_compte('groupe_messages', v_debut, v_fin),
      'Inscriptions événements', public._stat_compte('evenement_participants', v_debut, v_fin),
      'Vérifications selfie',public._stat_compte('verifications', v_debut, v_fin),
      'Signalements',        public._stat_compte('reports', v_debut, v_fin),
      'Réponses sondages',   public._stat_compte('reponses_annonces', v_debut, v_fin),
      'Messages programmés', public._stat_compte('messages_programmes', v_debut, v_fin)),

    -- Heures d'activité (messages envoyés, heure d'Abidjan = UTC)
    'messages_par_heure', (SELECT jsonb_agg(COALESCE(c.n, 0) ORDER BY h) FROM generate_series(0, 23) h
        LEFT JOIN (SELECT extract(hour FROM created_at AT TIME ZONE 'UTC')::int AS heure, count(*) AS n
                     FROM messages WHERE created_at >= v_debut AND created_at < v_fin + 1 GROUP BY 1) c
          ON c.heure = h),

    -- Parcours des inscrits de la période (entonnoir)
    -- (liste de paires [étape, nombre] : un objet jsonb perdrait l'ordre)
    'entonnoir', jsonb_build_array(
      jsonb_build_array('Inscrits',            (SELECT count(*) FROM cohorte)),
      jsonb_build_array('Profil terminé',      (SELECT count(*) FROM cohorte WHERE onboarding_complete)),
      jsonb_build_array('A envoyé un like',    (SELECT count(*) FROM cohorte c WHERE EXISTS (SELECT 1 FROM likes l WHERE l.from_user_id = c.id))),
      jsonb_build_array('A eu un match',       (SELECT count(*) FROM cohorte c WHERE EXISTS (SELECT 1 FROM matches m WHERE m.user1_id = c.id OR m.user2_id = c.id))),
      jsonb_build_array('A envoyé un message', (SELECT count(*) FROM cohorte c WHERE EXISTS (SELECT 1 FROM messages m WHERE m.sender_id = c.id))),
      jsonb_build_array('Est passé Premium',   (SELECT count(*) FROM cohorte c WHERE EXISTS (SELECT 1 FROM profiles p WHERE p.id = c.id AND p.is_premium)
                                OR EXISTS (SELECT 1 FROM achats_journal a WHERE a.user_id = c.id AND a.type = 'INITIAL_PURCHASE')))),

    -- Rétention : part des inscrits revenus N jours après leur inscription
    'retention', jsonb_build_object(
      'J1',  (SELECT round(100.0 * count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activite_jour a WHERE a.user_id = c.id AND a.jour = c.j0 + 1))
                     / NULLIF(count(*) FILTER (WHERE c.j0 + 1 <= current_date), 0), 1) FROM cohorte c WHERE c.j0 + 1 <= current_date),
      'J7',  (SELECT round(100.0 * count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activite_jour a WHERE a.user_id = c.id AND a.jour BETWEEN c.j0 + 7 AND c.j0 + 13))
                     / NULLIF(count(*), 0), 1) FROM cohorte c WHERE c.j0 + 7 <= current_date),
      'J30', (SELECT round(100.0 * count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activite_jour a WHERE a.user_id = c.id AND a.jour BETWEEN c.j0 + 30 AND c.j0 + 36))
                     / NULLIF(count(*), 0), 1) FROM cohorte c WHERE c.j0 + 30 <= current_date),
      'suivi_depuis', (SELECT min(jour) FROM activite_jour)),

    -- Qui sont les utilisateurs (comptes actifs sur 30 jours)
    'genres', (SELECT COALESCE(jsonb_object_agg(g, n), '{}'::jsonb) FROM (
        SELECT COALESCE(NULLIF(lower(gender), ''), 'non précisé') AS g, count(*) AS n FROM profiles
         WHERE last_seen > now() - interval '30 days' GROUP BY 1) x),
    'ages', (SELECT COALESCE(jsonb_object_agg(t, n), '{}'::jsonb) FROM (
        SELECT CASE WHEN birthdate IS NULL THEN 'inconnu'
                    WHEN age(birthdate) < interval '25 years' THEN '18-24'
                    WHEN age(birthdate) < interval '35 years' THEN '25-34'
                    WHEN age(birthdate) < interval '45 years' THEN '35-44'
                    ELSE '45+' END AS t, count(*) AS n
          FROM profiles WHERE last_seen > now() - interval '30 days' GROUP BY 1) x)
  ) INTO v_res;

  RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION public._stat_compte(text, date, date, text) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public._stat_par_jour(text, date, date) FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_statistiques(date, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_statistiques(date, date) TO authenticated;

COMMIT;
