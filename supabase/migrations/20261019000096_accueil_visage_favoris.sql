-- ═══════════════════════════════════════════════════════════════════
-- 🏠 Accueil — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- 1. profiles.photo_visage : la photo principale montre-t-elle un visage ?
--    Renseigné par l'app de chaque membre (détection sur le téléphone) ;
--    vide = pas encore vérifié. Les profils sans visage passent après les
--    autres dans la grille.
-- 2. profils_accueil renvoie photo_visage (reste identique sinon).
-- 3. profils_par_ids : profils précis (favoris, croisés) même s'ils ne
--    sont pas parmi les plus proches, avec les mêmes règles (blocages,
--    comptes suspendus, visibilité mutuelle).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS photo_visage boolean;

-- Ligne d'un profil telle que l'Accueil l'affiche
CREATE OR REPLACE FUNCTION public._ligne_accueil(p public.profiles)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
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
    'langues', p.langues, 'questions', p.questions,
    'photo_visage', p.photo_visage);
$$;
REVOKE ALL ON FUNCTION public._ligne_accueil(public.profiles) FROM public, anon;

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
      SELECT public._ligne_accueil(p) AS ligne,
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
         AND NOT COALESCE(p.est_officiel, false)   -- compte « Zamu » (SQL 072)
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

-- Profils précis (favoris, croisés), où qu'ils soient
CREATE OR REPLACE FUNCTION public.profils_par_ids(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bloques text[];
  v_genre   text;
  v_cherche text;
BEGIN
  IF v_uid IS NULL OR p_ids IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}'), gender::text, looking_for::text
    INTO v_bloques, v_genre, v_cherche
    FROM profiles WHERE id = v_uid;

  RETURN COALESCE((
    SELECT jsonb_agg(public._ligne_accueil(p))
      FROM profiles p
     WHERE p.id = ANY (p_ids[1:200])
       AND p.id <> v_uid
       AND NOT COALESCE(p.is_suspended, false)
       AND NOT COALESCE(p.est_officiel, false)
       AND NOT (p.id::text = ANY (v_bloques))
       AND NOT (v_uid::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
       AND public._se_cherchent(v_genre, v_cherche, p.gender::text, p.looking_for::text)
  ), '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.profils_par_ids(uuid[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_par_ids(uuid[]) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
