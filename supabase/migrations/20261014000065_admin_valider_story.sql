-- ═══════════════════════════════════════════════════════════════════
-- Panneau admin : bouton « Valider » des stories en attente — 2026-10-14
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Le bouton passait par une mise à jour directe de la table stories,
-- refusée par la base (« refusé par la base ») quand la règle du script
-- 025 manquait. On passe par une fonction réservée aux admins : elle ne
-- dépend plus des règles d'accès de la table.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_valider_story(p_story text)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  UPDATE stories SET moderation_status = 'approved' WHERE id::text = p_story;
  RETURN FOUND;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_valider_story(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_valider_story(text) TO authenticated;

-- (Re)crée aussi la règle du script 025, au cas où elle manquerait
DROP POLICY IF EXISTS "admin updates any story" ON public.stories;
CREATE POLICY "admin updates any story" ON public.stories
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

COMMIT;

NOTIFY pgrst, 'reload schema';
