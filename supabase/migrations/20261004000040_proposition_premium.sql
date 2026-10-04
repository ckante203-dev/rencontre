-- ═══════════════════════════════════════════════════════════════════
-- Proposer un événement : réservé aux membres Premium — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 035. Ré-exécutable.
--
-- La base refuse une proposition d'un compte gratuit (profiles.is_premium,
-- synchronisé par le webhook RevenueCat), même si l'app est contournée.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.controler_proposition()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF public.is_admin() THEN RETURN NEW; END IF;
  -- 👑 Premium uniquement
  IF NOT EXISTS (SELECT 1 FROM profiles
                 WHERE id = auth.uid() AND COALESCE(is_premium, false)) THEN
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

NOTIFY pgrst, 'reload schema';
