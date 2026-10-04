-- ═══════════════════════════════════════════════════════════════════
-- Panneau admin : valider une story en attente — 2026-10-03
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- La page « Modération » du panneau passe une story « pending » à
-- « approved ». Les admins pouvaient supprimer n'importe quelle story
-- (admin deletes any story) mais pas la MODIFIER : sans cette règle, le
-- bouton « Valider » était refusé par la base.
-- (Le trigger protect_story_moderation laisse déjà passer les admins.)
-- ═══════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "admin updates any story" ON public.stories;
CREATE POLICY "admin updates any story" ON public.stories
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
