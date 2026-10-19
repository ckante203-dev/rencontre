-- ═══════════════════════════════════════════════════════════════════
-- 🔔 Réglage « Likes & matchs » — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Permet de couper les notifications de likes, matchs, follows et crushs
-- de story (lu par la fonction dynamic-processor). Activé par défaut.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notif_likes boolean NOT NULL DEFAULT true;

NOTIFY pgrst, 'reload schema';
