-- ═══════════════════════════════════════════════════════════════════
-- Certification (badge bleu) — 2026-10-18
-- À exécuter dans Supabase → SQL Editor (après le 079). Ré-exécutable.
--
-- Page « Certification » du panneau admin : tous les comptes certifiés,
-- en attente ou non certifiés, avec recherche. L'admin donne ou retire
-- le badge à tout moment (ex. « rencontré en personne »).
-- Chaque changement du badge est inscrit dans certifications_journal,
-- quel que soit le chemin (selfie validé, photo changée, manuel…).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.certifications_journal (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  certifie    boolean NOT NULL,          -- true = badge donné, false = retiré
  mode        text NOT NULL DEFAULT 'selfie',  -- selfie, manuel
  motif       text,
  admin_email text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS certifications_journal_user_idx
  ON public.certifications_journal (user_id, created_at DESC);
ALTER TABLE public.certifications_journal ENABLE ROW LEVEL SECURITY;
-- Aucune politique : lecture seulement via les fonctions admin ci-dessous

-- Journal automatique à chaque changement du badge
CREATE OR REPLACE FUNCTION public.journal_certification()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.est_verifie IS DISTINCT FROM OLD.est_verifie THEN
    INSERT INTO certifications_journal (user_id, certifie, mode, motif, admin_email)
    VALUES (NEW.id, NEW.est_verifie,
            COALESCE(NULLIF(current_setting('zamu.certif_mode', true), ''), 'selfie'),
            NULLIF(current_setting('zamu.certif_motif', true), ''),
            auth.jwt() ->> 'email');
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_journal_certification ON public.profiles;
CREATE TRIGGER trg_journal_certification
  AFTER UPDATE OF est_verifie ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.journal_certification();

-- Compteurs des trois onglets
CREATE OR REPLACE FUNCTION public.admin_certifications_compteurs()
RETURNS TABLE (certifies bigint, en_attente bigint, non_certifies bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT count(*) FILTER (WHERE p.est_verifie),
           count(*) FILTER (WHERE NOT p.est_verifie AND EXISTS (
             SELECT 1 FROM verifications v
              WHERE v.user_id = p.id AND v.statut = 'en_attente')),
           count(*) FILTER (WHERE NOT p.est_verifie AND NOT EXISTS (
             SELECT 1 FROM verifications v
              WHERE v.user_id = p.id AND v.statut = 'en_attente'))
      FROM profiles p
     WHERE COALESCE(p.onboarding_complete, false)
       AND NOT COALESCE(p.is_banned, false);
END;
$$;

-- Liste d'un onglet : 'certifies', 'attente' ou 'non' (+ recherche nom,
-- pseudo ou e-mail). Avec la dernière décision du journal.
CREATE OR REPLACE FUNCTION public.admin_certifications(
  p_filtre text DEFAULT 'certifies', p_recherche text DEFAULT NULL,
  p_limite int DEFAULT 100)
RETURNS TABLE (id uuid, name text, username text, email text, photo_url text,
               est_verifie boolean, depuis timestamptz, mode text,
               motif text, par text, demande_le timestamptz,
               last_seen timestamptz, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  q text := NULLIF(btrim(COALESCE(p_recherche, '')), '');
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT p.id, p.name::text, p.username::text, p.email::text, p.photo_url::text,
           COALESCE(p.est_verifie, false),
           COALESCE(j.created_at,
             (SELECT max(v.traitee_le) FROM verifications v
               WHERE v.user_id = p.id AND v.statut = 'validee')),
           j.mode, j.motif, j.admin_email,
           (SELECT min(v.created_at) FROM verifications v
             WHERE v.user_id = p.id AND v.statut = 'en_attente'),
           p.last_seen::timestamptz, p.created_at::timestamptz
      FROM profiles p
      LEFT JOIN LATERAL (
        SELECT c.created_at, c.mode, c.motif, c.admin_email
          FROM certifications_journal c
         WHERE c.user_id = p.id AND c.certifie = COALESCE(p.est_verifie, false)
         ORDER BY c.created_at DESC LIMIT 1) j ON true
     WHERE COALESCE(p.onboarding_complete, false)
       AND NOT COALESCE(p.is_banned, false)
       AND CASE p_filtre
             WHEN 'certifies' THEN COALESCE(p.est_verifie, false)
             WHEN 'attente' THEN NOT COALESCE(p.est_verifie, false) AND EXISTS (
               SELECT 1 FROM verifications v
                WHERE v.user_id = p.id AND v.statut = 'en_attente')
             ELSE NOT COALESCE(p.est_verifie, false) AND NOT EXISTS (
               SELECT 1 FROM verifications v
                WHERE v.user_id = p.id AND v.statut = 'en_attente')
           END
       AND (q IS NULL OR p.name ILIKE '%' || q || '%'
            OR p.username ILIKE '%' || q || '%' OR p.email ILIKE '%' || q || '%')
     ORDER BY CASE WHEN p_filtre = 'non' THEN p.last_seen END DESC NULLS LAST,
              p.name
     LIMIT LEAST(GREATEST(p_limite, 1), 500);
END;
$$;

-- Donner (p_valeur = true) ou retirer le badge, avec un motif.
-- Renvoie les selfies en attente à supprimer du stockage.
CREATE OR REPLACE FUNCTION public.admin_certifier(
  p_user uuid, p_valeur boolean, p_motif text DEFAULT NULL)
RETURNS text[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_chemins text[];
BEGIN
  PERFORM public._exiger_admin();
  PERFORM set_config('zamu.certif_mode', 'manuel', true);
  PERFORM set_config('zamu.certif_motif', COALESCE(left(p_motif, 200), ''), true);
  UPDATE profiles SET est_verifie = p_valeur WHERE id = p_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'profil_introuvable' USING ERRCODE = 'P0001';
  END IF;
  IF p_valeur THEN
    -- Une demande selfie en attente devient inutile : validée
    SELECT array_agg(chemin) FILTER (WHERE chemin IS NOT NULL) INTO v_chemins
      FROM verifications WHERE user_id = p_user AND statut = 'en_attente';
    UPDATE verifications
       SET statut = 'validee', motif = 'Certifié par un admin',
           traitee_le = now(), chemin = NULL
     WHERE user_id = p_user AND statut = 'en_attente';
  END IF;
  RETURN COALESCE(v_chemins, ARRAY[]::text[]);
END;
$$;

-- Historique d'une personne (badge donné / retiré)
CREATE OR REPLACE FUNCTION public.admin_certification_historique(p_user uuid)
RETURNS TABLE (certifie boolean, mode text, motif text, admin_email text,
               created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT c.certifie, c.mode, c.motif, c.admin_email, c.created_at
      FROM certifications_journal c
     WHERE c.user_id = p_user
     ORDER BY c.created_at DESC LIMIT 50;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_certifications_compteurs() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_certifications(text, text, int) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_certifier(uuid, boolean, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_certification_historique(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_certifications_compteurs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_certifications(text, text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_certifier(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_certification_historique(uuid) TO authenticated;

COMMIT;
