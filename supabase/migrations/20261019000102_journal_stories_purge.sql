-- ═══════════════════════════════════════════════════════════════════
-- 🧹 Journal des stories : effacement — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- story_journal (SQL 100) ne sert qu'aux critères Zamu Star (30 jours).
-- 1. Effacé avec le compte (clé vers profiles, ON DELETE CASCADE).
-- 2. Lignes de plus de 31 jours supprimées chaque nuit (pg_cron).
-- (Annoncé dans la politique de confidentialité du 19/10/2026.)
-- ═══════════════════════════════════════════════════════════════════

-- Comptes déjà supprimés : leurs lignes partent avant la pose de la clé
DELETE FROM public.story_journal j
 WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = j.user_id);

ALTER TABLE public.story_journal
  DROP CONSTRAINT IF EXISTS story_journal_user_fk;
ALTER TABLE public.story_journal
  ADD CONSTRAINT story_journal_user_fk
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

DELETE FROM public.story_journal WHERE created_at < now() - interval '31 days';

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'purge-story-journal';
SELECT cron.schedule('purge-story-journal', '30 3 * * *',
  $$DELETE FROM public.story_journal WHERE created_at < now() - interval '31 days'$$);
