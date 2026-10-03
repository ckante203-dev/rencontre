-- ═══════════════════════════════════════════════════════════════════
-- Modifier un message envoyé (comme WhatsApp) — 2026-10-02
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- • Colonne modifie_le : l'app affiche « modifié » à côté de l'heure.
-- • Seul l'expéditeur peut changer le texte d'un message, seulement un
--   message texte, et seulement dans les 15 minutes après l'envoi.
--   (Le destinataire peut toujours mettre à jour le statut lu / les
--   réactions : il en a besoin, mais il ne peut plus toucher au texte.)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS modifie_le timestamptz;

CREATE OR REPLACE FUNCTION public.protege_modification_message()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- service_role, fonctions SECURITY DEFINER (purge, etc.) : libres
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.content IS DISTINCT FROM OLD.content THEN
    IF auth.uid() IS DISTINCT FROM OLD.sender_id THEN
      RAISE EXCEPTION 'Seul l''expéditeur peut modifier ce message'
        USING ERRCODE = '42501';
    END IF;
    IF OLD.type IS DISTINCT FROM 'text'
       OR OLD.created_at < now() - interval '15 minutes' THEN
      RAISE EXCEPTION 'Ce message ne peut plus être modifié'
        USING ERRCODE = '42501';
    END IF;
    NEW.modifie_le := now();
  ELSE
    -- L'app ne peut pas poser « modifié » sans changer le texte
    NEW.modifie_le := OLD.modifie_le;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protege_modification_message ON public.messages;
CREATE TRIGGER trg_protege_modification_message
  BEFORE UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.protege_modification_message();

COMMIT;

NOTIFY pgrst, 'reload schema';
