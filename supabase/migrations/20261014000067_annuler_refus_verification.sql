-- ═══════════════════════════════════════════════════════════════════
-- Vérifications : revenir sur un refus fait par erreur — 2026-10-14
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Page « Vérifications » du panneau : liste des demandes refusées depuis
-- 7 jours, avec un bouton « Valider quand même ». Le selfie a déjà été
-- supprimé au refus : on s'appuie sur ce que l'admin avait vu.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Demandes refusées depuis 7 jours (les plus récentes d'abord)
CREATE OR REPLACE FUNCTION public.admin_verifications_refusees()
RETURNS TABLE (id uuid, user_id uuid, name text, photo_url text,
               motif text, traitee_le timestamptz, est_verifie boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT v.id, v.user_id, p.name::text, p.photo_url::text, v.motif,
           v.traitee_le, COALESCE(p.est_verifie, false)
      FROM verifications v
      JOIN profiles p ON p.id = v.user_id
     WHERE v.statut = 'refusee'
       AND v.traitee_le > now() - interval '7 days'
     ORDER BY v.traitee_le DESC
     LIMIT 100;
END;
$$;

-- Valider une demande refusée par erreur (7 jours au plus)
CREATE OR REPLACE FUNCTION public.admin_annuler_refus(p_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user uuid;
BEGIN
  PERFORM public._exiger_admin();
  UPDATE verifications
     SET statut = 'validee', motif = NULL, traitee_le = now()
   WHERE id = p_id AND statut = 'refusee'
     AND traitee_le > now() - interval '7 days'
  RETURNING user_id INTO v_user;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'introuvable_ou_trop_ancienne' USING ERRCODE = 'P0001';
  END IF;
  UPDATE profiles SET est_verifie = true WHERE id = v_user;
  RETURN v_user;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_verifications_refusees() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_annuler_refus(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_verifications_refusees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_annuler_refus(uuid) TO authenticated;

COMMIT;
