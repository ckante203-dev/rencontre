-- ═══════════════════════════════════════════════════════════════════
-- 🔒 SÉCURITÉ — plus aucune lecture anonyme des profils — 2026-10-19
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Le hotfix du 28/09 (20260928000001) avait rouvert, pour la connexion
-- par pseudo, la lecture SANS CONNEXION des colonnes username et email :
-- n'importe qui, avec la clé publique de l'app, pouvait lister tous les
-- e-mails. La connexion par pseudo passe maintenant par la fonction
-- serveur « connexion-pseudo » (qui ne renvoie jamais l'e-mail).
--
-- Effet : la 1.1.9 ne peut plus se connecter avec le pseudo (seulement
-- avec l'e-mail ou Google) ; les personnes déjà connectées ne voient
-- aucune différence.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

DROP POLICY IF EXISTS profiles_select_anon_login ON public.profiles;
REVOKE SELECT ON public.profiles FROM anon;

COMMIT;

NOTIFY pgrst, 'reload schema';
