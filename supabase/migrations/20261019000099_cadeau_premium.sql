-- ═══════════════════════════════════════════════════════════════════
-- 🎁 Offrir du Premium — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Un membre Premium (abonnement payé : profiles.is_premium) peut offrir
-- 72 h de Premium à qui il veut, une fois tous les 30 jours.
-- Le cadeau passe par un Boost « invisible » (comme les 48 h de
-- bienvenue) : droits Premium, sans mise en avant sur l'Accueil.
-- Pas de cadeau à soi-même, ni entre personnes bloquées ; un cadeau reçu
-- ne permet pas d'en offrir (seuls les abonnés payants).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.cadeaux_premium (
  id         bigserial PRIMARY KEY,
  de         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  a          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  heures     int  NOT NULL DEFAULT 72,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS cadeaux_premium_de_idx
  ON public.cadeaux_premium (de, created_at DESC);

ALTER TABLE public.cadeaux_premium ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cadeaux_premium_select ON public.cadeaux_premium;
CREATE POLICY cadeaux_premium_select ON public.cadeaux_premium
  FOR SELECT TO authenticated
  USING (de = auth.uid() OR a = auth.uid());
-- Aucune écriture directe : seulement via offrir_premium()

-- Le cadeau ne met pas en avant sur l'Accueil (comme la bienvenue)
CREATE OR REPLACE FUNCTION public.boost_visible(p_user uuid, p_jusqua timestamptz,
                                                p_debut timestamptz)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(p_jusqua > now(), false)
     AND EXISTS (SELECT 1 FROM boost_achats b
                  WHERE b.user_id = p_user
                    AND b.created_at >= COALESCE(p_debut, now()) - interval '2 minutes'
                    AND b.produit NOT IN ('offert_bienvenue', 'parrainage_filleul',
                                          'parrainage_parrain', 'cadeau_premium'));
$$;
REVOKE ALL ON FUNCTION public.boost_visible(uuid, timestamptz, timestamptz) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.boost_visible(uuid, timestamptz, timestamptz) TO authenticated;

-- Mon cadeau : suis-je abonné, est-il disponible, quand le prochain ?
CREATE OR REPLACE FUNCTION public.mon_cadeau_premium()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'premium', COALESCE((SELECT is_premium FROM profiles WHERE id = auth.uid()), false),
    'dernier', (SELECT max(created_at) FROM cadeaux_premium WHERE de = auth.uid()),
    'prochain', (SELECT max(created_at) + interval '30 days'
                   FROM cadeaux_premium WHERE de = auth.uid()),
    'heures', 72);
$$;
REVOKE ALL ON FUNCTION public.mon_cadeau_premium() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mon_cadeau_premium() TO authenticated;

-- Offrir 72 h de Premium à p_a
CREATE OR REPLACE FUNCTION public.offrir_premium(p_a uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_dernier timestamptz;
BEGIN
  IF v_uid IS NULL THEN RETURN 'invalide'; END IF;
  IF p_a IS NULL OR p_a = v_uid THEN RETURN 'soi_meme'; END IF;
  IF NOT COALESCE((SELECT is_premium FROM profiles WHERE id = v_uid), false) THEN
    RETURN 'pas_premium';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = p_a
                  AND NOT COALESCE(is_suspended, false)) THEN
    RETURN 'introuvable';
  END IF;
  IF public.blocage_entre(v_uid, p_a) THEN RETURN 'bloque'; END IF;
  -- Un cadeau tous les 30 jours (verrou : deux appels simultanés)
  PERFORM pg_advisory_xact_lock(hashtext('cadeau_premium:' || v_uid));
  SELECT max(created_at) INTO v_dernier FROM cadeaux_premium WHERE de = v_uid;
  IF v_dernier IS NOT NULL AND v_dernier > now() - interval '30 days' THEN
    RETURN 'deja_offert';
  END IF;

  INSERT INTO cadeaux_premium (de, a, heures) VALUES (v_uid, p_a, 72);
  PERFORM public.appliquer_boost(p_a,
            'cadeau:' || v_uid || ':' || extract(epoch from now())::bigint,
            'cadeau_premium', 72 * 60);
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.offrir_premium(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.offrir_premium(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
