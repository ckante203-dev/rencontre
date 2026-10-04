-- ═══════════════════════════════════════════════════════════════════
-- Statut « Dispo maintenant » (façon Right Now de Grindr) — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- • profiles.dispo_texte  : « ☕ Dispo pour un café »… (40 caractères max)
-- • profiles.dispo_jusqua : fin du statut. Passé cette heure, l'app ne
--   l'affiche plus (rien à purger). Durée plafonnée à 12 h par le trigger.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS dispo_texte text,
  ADD COLUMN IF NOT EXISTS dispo_jusqua timestamptz;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS dispo_texte_longueur;
ALTER TABLE public.profiles ADD CONSTRAINT dispo_texte_longueur
  CHECK (dispo_texte IS NULL OR char_length(dispo_texte) <= 40);

-- Pas de statut « éternel » : 12 h maximum, texte vide = pas de statut.
CREATE OR REPLACE FUNCTION public.borner_dispo()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.dispo_texte := NULLIF(trim(COALESCE(NEW.dispo_texte, '')), '');
  IF NEW.dispo_texte IS NULL THEN
    NEW.dispo_jusqua := NULL;
  ELSIF NEW.dispo_jusqua IS NULL
     OR NEW.dispo_jusqua > now() + interval '12 hours' THEN
    NEW.dispo_jusqua := now() + interval '12 hours';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS borner_dispo ON public.profiles;
CREATE TRIGGER borner_dispo
  BEFORE INSERT OR UPDATE OF dispo_texte, dispo_jusqua ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.borner_dispo();

COMMIT;

NOTIFY pgrst, 'reload schema';
