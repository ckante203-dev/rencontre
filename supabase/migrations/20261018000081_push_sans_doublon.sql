-- ═══════════════════════════════════════════════════════════════════
-- Notifications de message sans doublon — 2026-10-18
-- À exécuter dans Supabase → SQL Editor AVANT de déployer smooth-action.
-- Ré-exécutable sans risque.
--
-- Un membre recevait de nouveau la notification d'un message auquel il
-- avait déjà répondu. smooth-action note ici chaque message notifié et
-- refuse d'en envoyer une 2ᵉ (en plus : jamais pour un message modifié,
-- déjà lu, de plus de 10 min, ou auquel le destinataire a répondu).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.push_messages_envoyes (
  message_id uuid PRIMARY KEY,
  envoye_le  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.push_messages_envoyes ENABLE ROW LEVEL SECURITY;
-- Aucune politique : seule la fonction serveur (clé secrète) y accède.

-- Ménage quotidien (seule l'heure qui suit l'envoi compte)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purger-push-messages') THEN
    PERFORM cron.unschedule('purger-push-messages');
  END IF;
END $$;
SELECT cron.schedule('purger-push-messages', '20 3 * * *',
  $$DELETE FROM public.push_messages_envoyes WHERE envoye_le < now() - interval '2 days'$$);

COMMIT;

-- Pour voir comment la notification de message est déclenchée :
--   SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--    WHERE tgrelid = 'public.messages'::regclass AND NOT tgisinternal;
