-- ═══════════════════════════════════════════════════════════════════
-- Boost offert aux Premium — 2026-10-05
-- À exécuter dans Supabase → SQL Editor, APRÈS 041 (bilan du Boost).
-- Ré-exécutable.
--
-- Chaque membre Premium (profiles.is_premium, tenu à jour par le webhook
-- RevenueCat) reçoit 1 Boost d'1 heure gratuit par mois calendaire (UTC).
-- • boost_offert_etat()   : l'app sait s'il est disponible.
-- • utiliser_boost_offert() : l'active (même chemin qu'un Boost acheté :
--   appliquer_boost, donc bilan et notification de fin inclus).
-- Le mois est la clé de la « transaction » dans boost_achats : un 2e
-- appel le même mois ne fait rien (clé déjà prise).
-- Compatible 1.0.11 : nouvelles fonctions seulement.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public._cle_boost_offert(p_user uuid)
RETURNS text
LANGUAGE sql STABLE
AS $$
  SELECT 'offert:' || p_user || ':' || to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM');
$$;
REVOKE ALL ON FUNCTION public._cle_boost_offert(uuid) FROM public, anon, authenticated;

-- État pour l'app : Premium ? Boost du mois encore disponible ?
CREATE OR REPLACE FUNCTION public.boost_offert_etat()
RETURNS TABLE (premium boolean, disponible boolean, prochain timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    COALESCE(p.is_premium, false),
    COALESCE(p.is_premium, false) AND NOT EXISTS (
      SELECT 1 FROM boost_achats b
       WHERE b.transaction_id = public._cle_boost_offert(p.id)),
    (date_trunc('month', now() AT TIME ZONE 'UTC') + interval '1 month')
      AT TIME ZONE 'UTC'
  FROM profiles p
  WHERE p.id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.boost_offert_etat() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.boost_offert_etat() TO authenticated;

-- Activer le Boost offert du mois (1 heure)
CREATE OR REPLACE FUNCTION public.utiliser_boost_offert()
RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_cle text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'non_connecte' USING ERRCODE = 'P0001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles
                  WHERE id = v_uid AND COALESCE(is_premium, false)
                    AND NOT COALESCE(is_suspended, false)) THEN
    RAISE EXCEPTION 'premium_requis' USING ERRCODE = 'P0001';
  END IF;
  v_cle := public._cle_boost_offert(v_uid);
  IF EXISTS (SELECT 1 FROM boost_achats WHERE transaction_id = v_cle) THEN
    RAISE EXCEPTION 'deja_utilise' USING ERRCODE = 'P0001';
  END IF;
  RETURN public.appliquer_boost(v_uid, v_cle, 'offert_premium', 60);
END;
$$;
REVOKE ALL ON FUNCTION public.utiliser_boost_offert() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.utiliser_boost_offert() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
