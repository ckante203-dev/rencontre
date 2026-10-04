-- ═══════════════════════════════════════════════════════════════════
-- Vignette des vidéos envoyées en message — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- messages.vignette_url : image de la vidéo (bucket « snaps », supprimée
-- avec le message par purge-expired). La durée de la vidéo est rangée
-- dans la colonne existante audio_duration (secondes).
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS vignette_url text;

NOTIFY pgrst, 'reload schema';
