-- ═══════════════════════════════════════════════════════════════════
-- Préférences des Paramètres — 2026-09-29
-- Colonnes utilisées par les interrupteurs des Paramètres, la carte
-- (show_distance) et les fonctions de notification (notif_messages,
-- notif_son). Créées si elles manquent ; sans effet si elles existent.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_birthdate boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS show_distance  boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_messages boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS notif_son      boolean NOT NULL DEFAULT true;
