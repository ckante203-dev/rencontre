-- ═══════════════════════════════════════════════════════════════════
-- Flammes 🔥 (série de jours) — 2026-10-02
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- Règle : la série d'une conversation augmente d'un jour s'il y a eu au
-- moins UN message (de n'importe lequel des deux) ce jour-là, et le jour
-- précédent aussi. Un jour sans aucun message → la série repart à 1 au
-- message suivant. Jour = heure d'Abidjan (UTC).
--
-- Comptée par la base à chaque message : les messages étant effacés 24 h
-- après lecture, l'historique ne permet pas de la recalculer.
-- L'app lit flamme_compte / flamme_dernier_jour (fetchConversations) et
-- affiche 🔥N à partir de 2 jours, ⏳ si personne n'a écrit aujourd'hui.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS flamme_compte integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS flamme_dernier_jour date;

-- ───────────────────────────────────────────────────────────────────
-- 1. Nouveau message → mise à jour de la série
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.maj_flamme_conversation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  jour date := (now() AT TIME ZONE 'Africa/Abidjan')::date;
BEGIN
  UPDATE conversations c
  SET flamme_compte = CASE
        WHEN c.flamme_dernier_jour = jour - 1 THEN c.flamme_compte + 1
        ELSE 1
      END,
      flamme_dernier_jour = jour
  WHERE c.id = NEW.conversation_id
    AND c.flamme_dernier_jour IS DISTINCT FROM jour;  -- 1 seule fois par jour
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.maj_flamme_conversation() FROM public, anon, authenticated;

DROP TRIGGER IF EXISTS trg_maj_flamme ON public.messages;
CREATE TRIGGER trg_maj_flamme
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.maj_flamme_conversation();

-- ───────────────────────────────────────────────────────────────────
-- 2. L'app ne peut pas modifier la série elle-même
--    (seul le trigger ci-dessus, SECURITY DEFINER, peut l'écrire)
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.protege_flamme_conversation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.flamme_compte := OLD.flamme_compte;
    NEW.flamme_dernier_jour := OLD.flamme_dernier_jour;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protege_flamme ON public.conversations;
CREATE TRIGGER trg_protege_flamme
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.protege_flamme_conversation();

COMMIT;

-- Recharge le cache de schéma de l'API (colonnes visibles tout de suite)
NOTIFY pgrst, 'reload schema';
