-- ═══════════════════════════════════════════════════════════════════
-- Boost = droits Premium pendant sa durée — 2026-10-05
-- À exécuter dans Supabase → SQL Editor, APRÈS 040 et 042. Ré-exécutable.
--
-- Pendant un Boost (profiles.boost_jusqua > now()), le compte a les
-- mêmes droits qu'un Premium :
--   • « Qui m'a liké / qui m'a vu » (_exiger_premium) ;
--   • proposer un événement (controler_proposition).
-- Côté app, la même règle est appliquée (ControleurProfil
-- .estPremiumMaintenant) : ville, filtres, profils illimités, etc.
-- Côté notifications, dynamic-processor dévoile le nom de la personne
-- qui like (déployé).
-- Exceptions volontaires :
--   • le mode fantôme reste réservé aux vrais Premium (un Boost sert à
--     être vu ; un fantôme activé pendant 1 h resterait 30 jours) ;
--   • le Boost offert du mois reste réservé aux vrais Premium (042).
-- Compatible 1.0.11 : mêmes fonctions, règle élargie.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Premium effectif : abonnement OU Boost en cours
CREATE OR REPLACE FUNCTION public.premium_effectif(p_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT COALESCE(p.is_premium, false)
            OR COALESCE(p.boost_jusqua > now(), false)
       FROM profiles p WHERE p.id = p_user),
    false);
$$;
REVOKE ALL ON FUNCTION public.premium_effectif(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.premium_effectif(uuid) TO authenticated;

-- « Qui m'a liké / qui m'a vu » : Premium, Boost en cours ou admin
CREATE OR REPLACE FUNCTION public._exiger_premium()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Non connecté' USING ERRCODE = '42501';
  END IF;

  IF NOT public.premium_effectif(auth.uid())
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Fonctionnalité réservée aux membres Premium'
      USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._exiger_premium() FROM public, anon, authenticated;

-- Proposer un événement : Premium ou Boost en cours
CREATE OR REPLACE FUNCTION public.controler_proposition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  -- 👑 Premium (ou Boost en cours) uniquement
  IF NOT public.premium_effectif(auth.uid()) THEN
    RAISE EXCEPTION 'premium_requis' USING ERRCODE = 'P0001',
      HINT = 'Proposer un événement est réservé aux membres Premium';
  END IF;
  NEW.statut := 'en_attente';
  NEW.notifier_proches := false;
  NEW.image_url := NULL;
  NEW.cree_par := auth.uid();
  IF NEW.debut < now() THEN
    RAISE EXCEPTION 'date_passee' USING ERRCODE = 'P0001';
  END IF;
  IF (SELECT count(*) FROM evenements
      WHERE cree_par = auth.uid() AND statut = 'en_attente') >= 3 THEN
    RAISE EXCEPTION 'trop_de_propositions' USING ERRCODE = 'P0001',
      HINT = '3 propositions en attente maximum';
  END IF;
  RETURN NEW;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
