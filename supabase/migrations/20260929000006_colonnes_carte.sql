-- ═══════════════════════════════════════════════════════════════════
-- Colonnes de la carte manquantes dans profiles — 2026-09-29
-- L'app (map_controller.dart, home_controller.dart) les lit et les écrit,
-- mais elles n'existaient pas : le chargement de la carte échouait.
-- Valeurs par défaut = comportement de l'app quand la valeur est absente.
-- Ré-exécutable sans risque.
-- ═══════════════════════════════════════════════════════════════════

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS map_visible         boolean     NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_ghost            boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ghost_until         timestamptz,
  ADD COLUMN IF NOT EXISTS map_invisible_until timestamptz,
  ADD COLUMN IF NOT EXISTS position_precision  text        NOT NULL DEFAULT 'flouted';
