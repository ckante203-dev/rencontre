-- ═══════════════════════════════════════════════════════════════════
-- Visibilité mutuelle selon « Je cherche » (façon Tinder) — 2026-10-15
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- A voit B sur l'Accueil seulement si B correspond à ce que A cherche
-- ET A correspond à ce que B cherche. Ex. : une femme qui cherche des
-- hommes ne voit jamais un homme qui cherche des hommes (et inversement).
-- « Je cherche » (looking_for) n'est jamais affiché publiquement.
--
-- Valeurs : looking_for = 'hommes' | 'femmes' | 'tout le monde' | vide
--           gender      = 'homme'  | 'femme'  | vide
-- Non renseigné : on suppose qu'on cherche le genre opposé (prudence) ;
-- l'app 1.1.8 demande de choisir. Genre inconnu : on ne filtre pas.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Est-ce que quelqu'un (genre, cherche) s'intéresse au genre « autre » ?
CREATE OR REPLACE FUNCTION public._cherche(p_genre text, p_cherche text, p_autre text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN lower(coalesce(p_autre, '')) NOT IN ('homme', 'femme') THEN true   -- genre inconnu
    WHEN lower(coalesce(p_cherche, '')) = 'tout le monde' THEN true
    WHEN lower(coalesce(p_cherche, '')) = 'hommes' THEN lower(p_autre) = 'homme'
    WHEN lower(coalesce(p_cherche, '')) = 'femmes' THEN lower(p_autre) = 'femme'
    -- pas de choix : genre opposé ; mon genre inconnu : tout le monde
    WHEN lower(coalesce(p_genre, '')) = 'homme' THEN lower(p_autre) = 'femme'
    WHEN lower(coalesce(p_genre, '')) = 'femme' THEN lower(p_autre) = 'homme'
    ELSE true
  END;
$$;

-- Les deux personnes se cherchent mutuellement
CREATE OR REPLACE FUNCTION public._se_cherchent(a_genre text, a_cherche text,
                                                b_genre text, b_cherche text)
RETURNS boolean
LANGUAGE sql IMMUTABLE
AS $$
  SELECT public._cherche(a_genre, a_cherche, b_genre)
     AND public._cherche(b_genre, b_cherche, a_genre);
$$;

-- profils_accueil (version du script 068) + visibilité mutuelle
CREATE OR REPLACE FUNCTION public.profils_accueil(
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_limite int DEFAULT 300)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bloques text[];
  v_genre   text;
  v_cherche text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}'), gender::text, looking_for::text
    INTO v_bloques, v_genre, v_cherche
    FROM profiles WHERE id = v_uid;

  RETURN COALESCE((
    SELECT jsonb_agg(x.ligne ORDER BY x.booste DESC, x.dist NULLS LAST,
                                      x.vu DESC NULLS LAST)
    FROM (
      SELECT jsonb_build_object(
               'id', p.id, 'name', p.name, 'birthdate', p.birthdate,
               'bio', p.bio, 'photo_url', p.photo_url,
               'photo_urls', p.photo_urls, 'interests', p.interests,
               'latitude', p.latitude, 'longitude', p.longitude,
               'gender', p.gender, 'is_online', p.is_online,
               'last_seen', p.last_seen, 'created_at', p.created_at,
               'taille', p.taille, 'poids', p.poids,
               'morphologie', p.morphologie,
               'lieu_rencontre', p.lieu_rencontre,
               'is_premium', p.is_premium,
               'show_birthdate', p.show_birthdate,
               'show_distance', p.show_distance,
               'boost_jusqua', CASE WHEN public.boost_visible(p.id, p.boost_jusqua, p.boost_debut) THEN p.boost_jusqua END,
               'dispo_texte', p.dispo_texte,
               'dispo_jusqua', p.dispo_jusqua,
               'est_verifie', p.est_verifie,
               'metier', p.metier, 'etudes', p.etudes,
               'langues', p.langues, 'questions', p.questions) AS ligne,
             public.boost_visible(p.id, p.boost_jusqua, p.boost_debut) AS booste,
             CASE WHEN p_lat IS NULL OR p_lng IS NULL
                       OR p.latitude IS NULL OR p.longitude IS NULL THEN NULL
                  ELSE 12742 * asin(sqrt(
                         power(sin(radians(p.latitude::float8 - p_lat) / 2), 2)
                       + cos(radians(p_lat)) * cos(radians(p.latitude::float8))
                       * power(sin(radians(p.longitude::float8 - p_lng) / 2), 2)))
             END AS dist,
             p.last_seen AS vu
        FROM profiles p
       WHERE p.id <> v_uid
         AND NOT COALESCE(p.is_suspended, false)
         AND NOT (p.id::text = ANY (v_bloques))
         AND NOT (v_uid::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
         -- Visibilité mutuelle (SQL 070) : chacun correspond à ce que l'autre cherche
         AND public._se_cherchent(v_genre, v_cherche, p.gender::text, p.looking_for::text)
       ORDER BY public.boost_visible(p.id, p.boost_jusqua, p.boost_debut) DESC,
                dist NULLS LAST, p.last_seen DESC NULLS LAST
       LIMIT LEAST(GREATEST(COALESCE(p_limite, 300), 1), 500)
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.profils_accueil(double precision, double precision, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_accueil(double precision, double precision, int) TO authenticated;

COMMIT;
