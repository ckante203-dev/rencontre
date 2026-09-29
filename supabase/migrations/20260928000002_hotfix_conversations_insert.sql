-- ═══════════════════════════════════════════════════════════════════
-- Hotfix — création de conversation depuis l'onglet Story (2026-09-28)
-- discover_feed_viewer.dart insère une conversation sans request_status
-- (défaut 'accepted') : la règle de 20260928000000 la rejetait si les
-- deux personnes ne s'étaient pas likées mutuellement.
-- On garde la protection de sécurité (on ne crée que des conversations
-- dont on fait partie) et on retire la condition sur request_status,
-- qui est une règle produit à gérer dans l'app.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

DROP POLICY IF EXISTS conversations_insert ON public.conversations;
CREATE POLICY conversations_insert ON public.conversations
  FOR INSERT WITH CHECK (
    auth.uid() IN (user1_id, user2_id)
    AND user1_id <> user2_id
    AND (initiated_by IS NULL OR initiated_by = auth.uid())
  );

COMMIT;
