-- ═══════════════════════════════════════════════════════════════════
-- Messages éphémères — PARTIE 1 (préparation, aucune suppression)
-- Règle : un message est supprimé 24h après avoir été lu.
-- Cette partie ajoute read_at et le remplit automatiquement côté serveur.
-- La purge (pg_cron + fonction purge-expired-messages) est en partie 2.
-- Ré-exécutable sans risque.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Date de lecture
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS read_at timestamptz;

CREATE INDEX IF NOT EXISTS messages_read_at_idx
  ON public.messages (read_at) WHERE read_at IS NOT NULL;

-- 2. read_at est rempli par le serveur quand le message passe en « lu ».
--    Les clients ne peuvent pas le choisir (sinon on pourrait faire
--    disparaître un message immédiatement en mettant une date ancienne).
CREATE OR REPLACE FUNCTION public.set_message_read_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      NEW.read_at := NULL;
    ELSE
      NEW.read_at := OLD.read_at;
    END IF;
  END IF;

  IF TG_OP = 'UPDATE'
     AND NEW.read_at IS NULL
     AND (COALESCE(NEW.is_read, false) OR NEW.status = 'read')
     AND NOT (COALESCE(OLD.is_read, false) OR OLD.status = 'read') THEN
    NEW.read_at := now();
  END IF;

  RETURN NEW;
END;
$$;

-- Nom choisi pour s'exécuter APRÈS trg_protect_message_columns (ordre alphabétique)
DROP TRIGGER IF EXISTS trg_set_message_read_at ON public.messages;
CREATE TRIGGER trg_set_message_read_at
  BEFORE INSERT OR UPDATE ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.set_message_read_at();

-- 3. Messages déjà lus : ils disparaîtront 24h après la mise en place
UPDATE public.messages
SET read_at = now()
WHERE read_at IS NULL
  AND (COALESCE(is_read, false) OR status = 'read');

-- 4. Supprimer un message auquel quelqu'un a répondu ne doit pas bloquer
DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = ANY (con.conkey)
    WHERE con.conrelid = 'public.messages'::regclass
      AND con.contype = 'f'
      AND a.attname = 'reply_to_id'
  LOOP
    EXECUTE format('ALTER TABLE public.messages DROP CONSTRAINT %I', c.conname);
  END LOOP;

  ALTER TABLE public.messages
    ADD CONSTRAINT messages_reply_to_id_fkey
    FOREIGN KEY (reply_to_id) REFERENCES public.messages (id)
    ON DELETE SET NULL NOT VALID;
END $$;

COMMIT;
