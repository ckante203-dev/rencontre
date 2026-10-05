-- ═══════════════════════════════════════════════════════════════════
-- Cloche 🔔 : notification supprimée 24 h après avoir été vue — 2026-10-05
-- À exécuter dans Supabase → SQL Editor, APRÈS 045. Ré-exécutable.
--
-- • notifications.lu_le : moment où la notification a été vue (posé
--   automatiquement quand is_read passe à true, quel que soit le chemin :
--   ouverture de l'écran, tap, « Tout marquer lu »).
-- • Tâche pg_cron « purge-notifications » (toutes les heures) : supprime
--   les notifications vues depuis plus de 24 h, et toutes celles de plus
--   de 30 jours.
-- Les notifications déjà lues avant ce script partent dans 24 h.
-- Compatible 1.0.11 : colonne nullable, ignorée par l'ancienne app.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS lu_le timestamptz;

CREATE INDEX IF NOT EXISTS notifications_lu_le_idx
  ON public.notifications (lu_le) WHERE lu_le IS NOT NULL;

-- Déjà lues avant ce script : supprimées dans 24 h
-- (sans le déclencheur, qui garderait lu_le à NULL)
DROP TRIGGER IF EXISTS trg_poser_lu_le_notification ON public.notifications;
UPDATE public.notifications
   SET lu_le = now()
 WHERE COALESCE(is_read, false) AND lu_le IS NULL;

-- Heure de lecture posée par la base (l'app ne peut pas la falsifier)
CREATE OR REPLACE FUNCTION public.poser_lu_le_notification()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(NEW.is_read, false) AND NOT COALESCE(OLD.is_read, false) THEN
    NEW.lu_le := now();
  ELSIF NOT COALESCE(NEW.is_read, false) THEN
    NEW.lu_le := NULL;
  ELSE
    NEW.lu_le := OLD.lu_le;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_poser_lu_le_notification ON public.notifications;
CREATE TRIGGER trg_poser_lu_le_notification
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.poser_lu_le_notification();

COMMIT;

-- Nettoyage toutes les heures (remplace la tâche si elle existe déjà)
SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge-notifications';
SELECT cron.schedule(
  'purge-notifications',
  '20 * * * *',
  $$DELETE FROM public.notifications
     WHERE lu_le < now() - interval '24 hours'
        OR created_at < now() - interval '30 days'$$
);

NOTIFY pgrst, 'reload schema';
