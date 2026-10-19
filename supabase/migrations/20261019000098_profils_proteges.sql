-- ═══════════════════════════════════════════════════════════════════
-- 🔒 SÉCURITÉ — profils des autres : positions arrondies, données
--    sensibles retirées — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- L'app 1.2.0 ne lit plus la table profiles en entier pour les autres :
-- elle passe par ces fonctions, qui ne renvoient que ce qui s'affiche.
--   • Position ARRONDIE par le serveur sur une grille fixe (le flou de la
--     carte était fait sur le téléphone, au hasard à chaque chargement :
--     en faisant la moyenne, on retrouvait la position exacte) :
--       exacte choisie → ~110 m · normal → ~1 km · très floue → ~5 km
--   • Date de naissance renvoyée seulement si la personne l'affiche.
--   • Jamais : e-mail, jeton de notification, appareil, liste de blocage,
--     abonnement, photos en attente…
-- Les anciennes versions continuent de marcher (la table reste lisible
-- pour les membres connectés, comme avant) ; le verrouillage des
-- colonnes viendra quand la 1.2.0 sera installée par presque tous.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Coordonnée arrondie selon la précision choisie par la personne
CREATE OR REPLACE FUNCTION public._coord_floue(x float8, p_precision text)
RETURNS float8
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN x IS NULL THEN NULL
    WHEN p_precision = 'exact' THEN round(x::numeric, 3)::float8
    WHEN p_precision = 'very_flouted' THEN (round(x::numeric * 20) / 20)::float8
    ELSE round(x::numeric, 2)::float8
  END;
$$;

-- Ligne publique d'un profil (Accueil, fiche, favoris, carte…)
CREATE OR REPLACE FUNCTION public._ligne_accueil(p public.profiles)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'id', p.id, 'name', p.name, 'username', p.username,
    'birthdate', CASE WHEN COALESCE(p.show_birthdate, true) THEN p.birthdate END,
    'bio', p.bio, 'photo_url', p.photo_url,
    'photo_urls', p.photo_urls, 'interests', p.interests,
    'latitude', public._coord_floue(p.latitude::float8, p.position_precision),
    'longitude', public._coord_floue(p.longitude::float8, p.position_precision),
    'gender', p.gender, 'looking_for', p.looking_for,
    'is_online', p.is_online,
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
    'est_officiel', p.est_officiel,
    'metier', p.metier, 'etudes', p.etudes,
    'langues', p.langues, 'questions', p.questions,
    'followers_count', p.followers_count,
    'following_count', p.following_count,
    'matches_count', p.matches_count,
    'photo_visage', p.photo_visage);
$$;
REVOKE ALL ON FUNCTION public._ligne_accueil(public.profiles) FROM public, anon;

-- Ma propre fiche, complète (réglages, e-mail…)
CREATE OR REPLACE FUNCTION public.mon_profil()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT to_jsonb(p) FROM profiles p WHERE p.id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.mon_profil() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mon_profil() TO authenticated;

-- Qui m'a bloqué (sans lire la liste de blocage des autres)
CREATE OR REPLACE FUNCTION public.qui_m_a_bloque()
RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(array_agg(p.id), '{}')
    FROM profiles p
   WHERE auth.uid() IS NOT NULL
     AND auth.uid()::text = ANY (COALESCE(p.blocked_users::text[], '{}'));
$$;
REVOKE ALL ON FUNCTION public.qui_m_a_bloque() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.qui_m_a_bloque() TO authenticated;

-- Fiches publiques par id (profil ouvert, likes, vues, story…) : sans la
-- règle de visibilité mutuelle (on peut ouvrir un profil qui nous écrit)
CREATE OR REPLACE FUNCTION public.profils_publics(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bloques text[];
BEGIN
  IF v_uid IS NULL OR p_ids IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}') INTO v_bloques
    FROM profiles WHERE id = v_uid;
  RETURN COALESCE((
    SELECT jsonb_agg(public._ligne_accueil(p))
      FROM profiles p
     WHERE p.id = ANY (p_ids[1:300])
       AND NOT COALESCE(p.is_suspended, false)
       AND NOT (p.id::text = ANY (v_bloques))
       AND NOT (v_uid::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
  ), '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.profils_publics(uuid[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_publics(uuid[]) TO authenticated;

-- Carte : profils visibles autour de moi (masqués, fantômes et invisibles
-- exclus PAR LE SERVEUR), positions arrondies
CREATE OR REPLACE FUNCTION public.profils_carte(
  p_lat double precision, p_lng double precision, p_rayon_km double precision DEFAULT 50)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bloques text[];
  d_lat float8;
  d_lng float8;
BEGIN
  IF v_uid IS NULL OR p_lat IS NULL OR p_lng IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}') INTO v_bloques
    FROM profiles WHERE id = v_uid;
  d_lat := LEAST(GREATEST(COALESCE(p_rayon_km, 50), 1), 200) / 111.32;
  d_lng := d_lat / GREATEST(abs(cos(radians(p_lat))), 0.01);
  RETURN COALESCE((
    SELECT jsonb_agg(x.ligne)
      FROM (
        SELECT public._ligne_accueil(p) AS ligne
          FROM profiles p
         WHERE p.id <> v_uid
           AND NOT COALESCE(p.is_suspended, false)
           AND NOT COALESCE(p.est_officiel, false)
           AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
           AND p.latitude BETWEEN p_lat - d_lat AND p_lat + d_lat
           AND p.longitude BETWEEN p_lng - d_lng AND p_lng + d_lng
           AND NOT (p.id::text = ANY (v_bloques))
           AND NOT (v_uid::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
           -- Masqué de la carte (définitivement ou jusqu'à une date)
           AND NOT (COALESCE(p.map_visible, true) = false AND p.map_invisible_until IS NULL)
           AND NOT (p.map_invisible_until IS NOT NULL AND p.map_invisible_until > now())
           -- Mode fantôme (Premium) en cours
           AND NOT (COALESCE(p.is_ghost, false) AND COALESCE(p.is_premium, false)
                    AND (p.ghost_until IS NULL OR p.ghost_until > now()))
         ORDER BY p.last_seen DESC NULLS LAST
         LIMIT 100
      ) x
  ), '[]'::jsonb);
END;
$$;
REVOKE ALL ON FUNCTION public.profils_carte(double precision, double precision, double precision) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_carte(double precision, double precision, double precision) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
