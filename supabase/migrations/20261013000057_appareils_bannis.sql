-- ═══════════════════════════════════════════════════════════════════
-- 057 : bannissement de l'appareil (pas seulement du compte)
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
--
-- • L'app enregistre l'identifiant Android du téléphone (profiles.appareil).
-- • Bannir un compte (is_banned, panneau admin) mémorise son appareil.
-- • Un compte qui se connecte depuis un appareil banni est banni et
--   suspendu automatiquement (il ne peut plus écrire ni être vu).
-- • Débannir le compte libère l'appareil.
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS appareil text;

CREATE TABLE IF NOT EXISTS public.appareils_bannis (
  appareil text PRIMARY KEY,
  user_id  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  cree_le  timestamptz NOT NULL DEFAULT now()
);
-- Aucun accès depuis l'app (seulement via les triggers ci-dessous)
ALTER TABLE public.appareils_bannis ENABLE ROW LEVEL SECURITY;

-- Bannissement / débannissement d'un compte → son appareil
CREATE OR REPLACE FUNCTION public.suivre_bannissement_appareil()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.is_banned, false) AND NEW.appareil IS NOT NULL THEN
    INSERT INTO appareils_bannis (appareil, user_id)
    VALUES (NEW.appareil, NEW.id) ON CONFLICT (appareil) DO NOTHING;
  ELSIF NOT COALESCE(NEW.is_banned, false) THEN
    DELETE FROM appareils_bannis WHERE user_id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_suivre_bannissement_appareil ON public.profiles;
CREATE TRIGGER trg_suivre_bannissement_appareil
  AFTER UPDATE OF is_banned ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.suivre_bannissement_appareil();

-- Nouvel appareil enregistré : banni ? → compte banni et suspendu.
-- (Exécuté en SECURITY DEFINER : la protection des colonnes
--  is_suspended / is_premium ne s'applique pas à cette mise à jour.)
CREATE OR REPLACE FUNCTION public.verifier_appareil_banni()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.appareil IS NOT NULL
     AND EXISTS (SELECT 1 FROM appareils_bannis b
                  WHERE b.appareil = NEW.appareil
                    AND b.user_id IS DISTINCT FROM NEW.id) THEN
    UPDATE profiles
       SET is_banned = true, is_suspended = true, is_online = false
     WHERE id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_verifier_appareil_banni ON public.profiles;
CREATE TRIGGER trg_verifier_appareil_banni
  AFTER UPDATE OF appareil ON public.profiles
  FOR EACH ROW
  WHEN (NEW.appareil IS DISTINCT FROM OLD.appareil)
  EXECUTE FUNCTION public.verifier_appareil_banni();

-- Comptes déjà bannis : on mémorise leurs appareils dès qu'ils sont connus
INSERT INTO public.appareils_bannis (appareil, user_id)
SELECT appareil, id FROM public.profiles
 WHERE COALESCE(is_banned, false) AND appareil IS NOT NULL
ON CONFLICT (appareil) DO NOTHING;

COMMIT;
