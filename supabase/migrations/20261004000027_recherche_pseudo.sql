-- ═══════════════════════════════════════════════════════════════════
-- Recherche d'un profil par son nom d'utilisateur — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- • profiles.trouvable_par_pseudo (par défaut oui) : Paramètres →
--   « Me trouver par mon nom d'utilisateur ». Désactivé = introuvable.
-- • chercher_par_pseudo(q) : profils dont le NOM D'UTILISATEUR commence par
--   q (3 caractères minimum, « @ » accepté). Jamais sur le prénom (taper
--   « Aïcha » ne liste pas toutes les Aïcha). Exclus : moi, comptes
--   suspendus / bannis, introuvables, blocages dans les deux sens.
--   10 résultats maximum, le pseudo exact en premier.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS trouvable_par_pseudo boolean NOT NULL DEFAULT true;

CREATE OR REPLACE FUNCTION public.chercher_par_pseudo(p_q text)
RETURNS TABLE (
  id uuid, name text, username text, photo_url text, en_ligne boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH q AS (
    SELECT lower(regexp_replace(trim(COALESCE(p_q, '')), '^@+', '')) AS t
  )
  SELECT p.id, p.name::text, p.username::text, p.photo_url::text,
         COALESCE(p.last_seen > now() - interval '30 minutes', false)
  FROM profiles p, q
  WHERE auth.uid() IS NOT NULL
    AND length(q.t) >= 3
    AND p.id <> auth.uid()
    AND p.username IS NOT NULL
    -- « _ » et « % » pris au pied de la lettre (pas comme jokers)
    AND lower(p.username) LIKE
        replace(replace(replace(q.t, '\', '\\'), '_', '\_'), '%', '\%') || '%'
    AND p.trouvable_par_pseudo
    AND NOT COALESCE(p.is_suspended, false)
    AND NOT public.blocage_entre(auth.uid(), p.id)
  ORDER BY (lower(p.username) = q.t) DESC, length(p.username), p.username
  LIMIT 10;
$$;
REVOKE ALL ON FUNCTION public.chercher_par_pseudo(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.chercher_par_pseudo(text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
