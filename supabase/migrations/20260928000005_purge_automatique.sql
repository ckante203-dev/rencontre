-- ═══════════════════════════════════════════════════════════════════
-- Purge automatique — PARTIE 2 (à exécuter APRÈS le déploiement de la
-- fonction purge-expired et la création du secret PURGE_SECRET)
--
-- Toutes les 15 minutes, pg_cron appelle la fonction purge-expired qui
-- supprime : stories expirées, messages lus depuis plus de 24h, et
-- fichiers en attente dans storage_a_supprimer (lignes + fichiers).
--
-- ⚠️ Remplacer REMPLACER_PAR_LE_SECRET par la même valeur que PURGE_SECRET.
-- ═══════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- File des fichiers à supprimer (déjà créée si la suppression manuelle
-- des anciens messages a été faite)
CREATE TABLE IF NOT EXISTS public.storage_a_supprimer (
  bucket     text NOT NULL,
  path       text NOT NULL,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (bucket, path)
);
ALTER TABLE public.storage_a_supprimer ENABLE ROW LEVEL SECURITY;

-- Secret partagé avec la fonction (stocké chiffré dans le Vault)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM vault.secrets WHERE name = 'purge_secret') THEN
    PERFORM vault.update_secret(
      (SELECT id FROM vault.secrets WHERE name = 'purge_secret'),
      'REMPLACER_PAR_LE_SECRET');
  ELSE
    PERFORM vault.create_secret('REMPLACER_PAR_LE_SECRET', 'purge_secret');
  END IF;
END $$;

-- Tâche planifiée (remplacée si elle existe déjà)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-expired') THEN
    PERFORM cron.unschedule('purge-expired');
  END IF;
END $$;

SELECT cron.schedule(
  'purge-expired',
  '*/15 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/purge-expired',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-purge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'purge_secret')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $cron$
);
