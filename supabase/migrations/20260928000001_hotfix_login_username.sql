-- ═══════════════════════════════════════════════════════════════════
-- Hotfix — connexion par nom d'utilisateur (2026-09-28)
-- La migration 20260928000000 a retiré la lecture anonyme de profiles,
-- or l'écran de connexion (auth_controller.dart signInWithEmail) lit
-- profiles.email par username AVANT d'être connecté.
--
-- On rouvre la lecture anonyme, mais uniquement des colonnes
-- username et email (droits par colonne), pas du reste du profil.
-- Les versions de l'app déjà installées refonctionnent sans mise à jour.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

REVOKE SELECT ON public.profiles FROM anon;
GRANT SELECT (username, email) ON public.profiles TO anon;

DROP POLICY IF EXISTS profiles_select_anon_login ON public.profiles;
CREATE POLICY profiles_select_anon_login ON public.profiles
  FOR SELECT TO anon USING (true);

COMMIT;
