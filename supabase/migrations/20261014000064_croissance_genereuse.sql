-- ═══════════════════════════════════════════════════════════════════
-- Phase de croissance : plus généreux en gratuit — 2026-10-14
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- 1. Bienvenue : chaque nouvel inscrit reçoit 48 h de Boost dès que son
--    profil est terminé. Un Boost donne tous les droits Premium (app et
--    serveur, voir premium_effectif) et s'arrête tout seul : rien à
--    surveiller. Marche avec toutes les versions de l'app.
-- 2. Parrainage : 7 jours de Boost pour le parrain (4 récompenses au plus
--    par mois, anti-abus) et 24 h pour l'ami invité (au lieu de 1 h).
--
-- Pour arrêter le cadeau de bienvenue plus tard :
--   DROP TRIGGER IF EXISTS profiles_bienvenue ON public.profiles;
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Cadeau de bienvenue ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._cadeau_bienvenue()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.onboarding_complete, false)
     AND (TG_OP = 'INSERT' OR NOT COALESCE(OLD.onboarding_complete, false))
     AND NEW.created_at > now() - interval '7 days' THEN
    -- Transaction « bienvenue:<id> » : une seule fois par compte
    PERFORM public.appliquer_boost(NEW.id, 'bienvenue:' || NEW.id,
                                   'offert_bienvenue', 48 * 60);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;  -- le cadeau ne doit jamais bloquer une inscription
END;
$$;

DROP TRIGGER IF EXISTS profiles_bienvenue ON public.profiles;
CREATE TRIGGER profiles_bienvenue
  AFTER INSERT OR UPDATE OF onboarding_complete ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._cadeau_bienvenue();

-- ─── 2. Parrainage plus généreux ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.utiliser_code_parrainage(p_code text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_moi profiles%ROWTYPE;
  v_parrain uuid;
  v_recompenses int;
BEGIN
  IF v_uid IS NULL THEN RETURN 'invalide'; END IF;
  SELECT * INTO v_moi FROM profiles WHERE id = v_uid;
  IF v_moi.parrain_id IS NOT NULL THEN RETURN 'deja_parraine'; END IF;
  IF v_moi.created_at < now() - interval '7 days' THEN RETURN 'trop_tard'; END IF;
  SELECT id INTO v_parrain FROM profiles
   WHERE lower(username) = lower(trim(both '@' from p_code))
     AND NOT COALESCE(is_suspended, false)
   LIMIT 1;
  IF v_parrain IS NULL THEN RETURN 'introuvable'; END IF;
  IF v_parrain = v_uid THEN RETURN 'soi_meme'; END IF;

  UPDATE profiles SET parrain_id = v_parrain, parraine_le = now() WHERE id = v_uid;
  -- Ami invité : 24 h de Boost (droits Premium)
  PERFORM public.appliquer_boost(v_uid, 'filleul:' || v_uid, 'parrainage_filleul', 24 * 60);
  -- Parrain : 7 jours, 4 récompenses au plus sur 30 jours (anti-abus)
  SELECT count(*) INTO v_recompenses FROM profiles
   WHERE parrain_id = v_parrain AND parraine_le > now() - interval '30 days';
  IF v_recompenses <= 4 THEN
    PERFORM public.appliquer_boost(v_parrain, 'parrain:' || v_uid, 'parrainage_parrain', 7 * 24 * 60);
  END IF;
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.utiliser_code_parrainage(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.utiliser_code_parrainage(text) TO authenticated;

COMMIT;
