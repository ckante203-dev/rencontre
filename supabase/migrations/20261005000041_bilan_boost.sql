-- ═══════════════════════════════════════════════════════════════════
-- Bilan du Boost — 2026-10-05
-- À exécuter dans Supabase → SQL Editor, APRÈS 015 (boost). Ré-exécutable.
--
-- • profiles.boost_debut : début du Boost en cours (ou du dernier).
--   Posé par appliquer_boost() quand un nouveau Boost démarre ; un achat
--   pendant un Boost le prolonge sans changer le début.
-- • bilan_boost() : vues et likes reçus pendant le Boost, comparés au
--   rythme habituel des 7 jours précédents (« ×4 »).
-- • boosts_a_notifier() : Boosts terminés depuis moins de 24 h dont le
--   bilan n'a pas encore été envoyé (notification « Ton Boost est
--   terminé : 45 vues, 3 likes ») — envoyé par rappel-evenements.
-- Compatible 1.0.11 : colonnes nullables, ignorées par l'ancienne app.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS boost_debut timestamptz,
  ADD COLUMN IF NOT EXISTS boost_bilan_envoye_le timestamptz;

-- Le client ne peut toucher à aucune colonne du Boost
CREATE OR REPLACE FUNCTION public.protect_boost_column()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.boost_jusqua := NULL;
    NEW.boost_debut := NULL;
    NEW.boost_bilan_envoye_le := NULL;
    RETURN NEW;
  END IF;
  IF NEW.boost_jusqua IS DISTINCT FROM OLD.boost_jusqua
     OR NEW.boost_debut IS DISTINCT FROM OLD.boost_debut
     OR NEW.boost_bilan_envoye_le IS DISTINCT FROM OLD.boost_bilan_envoye_le THEN
    RAISE EXCEPTION 'Modification du Boost non autorisée'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

-- Application d'un Boost (webhook) : nouveau Boost → nouveau début
CREATE OR REPLACE FUNCTION public.appliquer_boost(
  p_user        uuid,
  p_transaction text,
  p_produit     text,
  p_minutes     int
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fin timestamptz;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.boost_achats (transaction_id, user_id, produit, minutes)
  VALUES (p_transaction, p_user, p_produit, p_minutes)
  ON CONFLICT (transaction_id) DO NOTHING;

  IF NOT FOUND THEN
    SELECT boost_jusqua INTO v_fin FROM public.profiles WHERE id = p_user;
    RETURN v_fin;
  END IF;

  UPDATE public.profiles
     SET boost_debut = CASE
           WHEN boost_jusqua IS NULL OR boost_jusqua <= now() THEN now()
           ELSE COALESCE(boost_debut, now()) END,
         boost_bilan_envoye_le = CASE
           WHEN boost_jusqua IS NULL OR boost_jusqua <= now() THEN NULL
           ELSE boost_bilan_envoye_le END,
         boost_jusqua = greatest(coalesce(boost_jusqua, now()), now())
                        + make_interval(mins => p_minutes)
   WHERE id = p_user
  RETURNING boost_jusqua INTO v_fin;

  RETURN v_fin;
END;
$$;
REVOKE ALL ON FUNCTION public.appliquer_boost(uuid, text, text, int)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.appliquer_boost(uuid, text, text, int)
  TO service_role;

-- Calcul du bilan pour un profil (interne)
CREATE OR REPLACE FUNCTION public._bilan_boost(p_user uuid)
RETURNS TABLE (debut timestamptz, fin timestamptz, en_cours boolean,
               vues int, likes int, multiplicateur numeric)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  d timestamptz;
  f timestamptz;
  borne timestamptz;
  heures numeric;
  ref_vues int;
BEGIN
  SELECT p.boost_debut, p.boost_jusqua INTO d, f
  FROM profiles p WHERE p.id = p_user;
  IF d IS NULL OR f IS NULL THEN RETURN; END IF;
  borne := least(f, now());

  debut := d;
  fin := f;
  en_cours := f > now();
  SELECT count(*)::int INTO vues FROM profile_views v
   WHERE v.viewed_id = p_user AND v.viewer_id <> p_user
     AND v.created_at >= d AND v.created_at <= borne;
  SELECT count(*)::int INTO likes FROM likes l
   WHERE l.to_user_id = p_user
     AND l.created_at >= d AND l.created_at <= borne;

  -- Rythme habituel : vues par heure sur les 7 jours avant le Boost
  SELECT count(*)::int INTO ref_vues FROM profile_views v
   WHERE v.viewed_id = p_user AND v.viewer_id <> p_user
     AND v.created_at >= d - interval '7 days' AND v.created_at < d;
  heures := greatest(extract(epoch FROM (borne - d)) / 3600.0, 0.25);
  multiplicateur := CASE
    WHEN ref_vues = 0 OR vues = 0 THEN NULL
    ELSE round((vues / heures) / (ref_vues / 168.0), 1) END;
  RETURN NEXT;
END;
$$;
REVOKE ALL ON FUNCTION public._bilan_boost(uuid) FROM public, anon, authenticated;

-- Mon bilan (app)
CREATE OR REPLACE FUNCTION public.bilan_boost()
RETURNS TABLE (debut timestamptz, fin timestamptz, en_cours boolean,
               vues int, likes int, multiplicateur numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT * FROM public._bilan_boost(auth.uid());
$$;
REVOKE ALL ON FUNCTION public.bilan_boost() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.bilan_boost() TO authenticated;

-- Boosts terminés à notifier (edge function, service_role)
CREATE OR REPLACE FUNCTION public.boosts_a_notifier()
RETURNS TABLE (user_id uuid, fcm_token text, vues int, likes int,
               multiplicateur numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.id, p.fcm_token, b.vues, b.likes, b.multiplicateur
  FROM profiles p
  CROSS JOIN LATERAL public._bilan_boost(p.id) b
  WHERE p.boost_jusqua <= now()
    AND p.boost_jusqua > now() - interval '24 hours'
    AND p.boost_debut IS NOT NULL
    AND p.boost_bilan_envoye_le IS NULL
    AND COALESCE(p.fcm_token, '') <> ''
    AND NOT COALESCE(p.is_suspended, false)
  LIMIT 1000;
$$;
REVOKE ALL ON FUNCTION public.boosts_a_notifier() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.boosts_a_notifier() TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
