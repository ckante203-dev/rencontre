-- 051 : profil enrichi (métier, études, langues parlées, questions façon Hinge)
-- À exécuter dans le SQL Editor de Supabase.
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS metier    text,
  ADD COLUMN IF NOT EXISTS etudes    text,
  ADD COLUMN IF NOT EXISTS langues   text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS questions jsonb  NOT NULL DEFAULT '[]'::jsonb;

-- Longueurs raisonnables (anti-abus)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_metier_len;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_metier_len
  CHECK (metier IS NULL OR char_length(metier) <= 60);
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_etudes_len;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_etudes_len
  CHECK (etudes IS NULL OR char_length(etudes) <= 80);
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_questions_taille;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_questions_taille
  CHECK (jsonb_typeof(questions) = 'array' AND jsonb_array_length(questions) <= 3
         AND octet_length(questions::text) <= 2000);

-- Message épinglé en haut d'une conversation
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS message_epingle_id uuid
  REFERENCES public.messages(id) ON DELETE SET NULL;

-- « enregistre un vocal… » dans les conversations
ALTER TABLE public.typing_status ADD COLUMN IF NOT EXISTS activite text;

-- L'Accueil renvoie aussi ces nouvelles infos
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
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}') INTO v_bloques
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
               'boost_jusqua', p.boost_jusqua,
               'dispo_texte', p.dispo_texte,
               'dispo_jusqua', p.dispo_jusqua,
               'est_verifie', p.est_verifie,
               'metier', p.metier, 'etudes', p.etudes,
               'langues', p.langues, 'questions', p.questions) AS ligne,
             COALESCE(p.boost_jusqua > now(), false) AS booste,
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
       ORDER BY COALESCE(p.boost_jusqua > now(), false) DESC,
                dist NULLS LAST, p.last_seen DESC NULLS LAST
       LIMIT LEAST(GREATEST(COALESCE(p_limite, 300), 1), 500)
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.profils_accueil(double precision, double precision, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_accueil(double precision, double precision, int) TO authenticated;

COMMIT;
