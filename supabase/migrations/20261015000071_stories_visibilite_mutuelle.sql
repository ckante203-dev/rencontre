-- ═══════════════════════════════════════════════════════════════════
-- Stories : même visibilité mutuelle que l'Accueil — 2026-10-15
-- À exécuter dans Supabase → SQL Editor, APRÈS le script 070.
-- Ré-exécutable sans risque.
--
-- Je vois la story de quelqu'un seulement si nous nous cherchons
-- mutuellement (genre + « Je cherche », script 070)… SAUF si nous sommes
-- déjà en lien : match, conversation, ou amis (pseudos & amis).
-- Toujours visibles : mes propres stories ; tout pour les admins.
-- Politique RESTRICTIVE : s'ajoute aux règles existantes (amis proches,
-- modération, stories masquées…).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.story_visible_pour(p_auteur uuid, p_lecteur uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  a profiles%ROWTYPE;
  l profiles%ROWTYPE;
BEGIN
  IF p_lecteur IS NULL THEN RETURN false; END IF;
  IF p_auteur = p_lecteur THEN RETURN true; END IF;
  SELECT * INTO a FROM profiles WHERE id = p_auteur;
  SELECT * INTO l FROM profiles WHERE id = p_lecteur;
  IF public._se_cherchent(l.gender::text, l.looking_for::text,
                          a.gender::text, a.looking_for::text) THEN
    RETURN true;
  END IF;
  -- Déjà en lien : on garde les stories visibles
  RETURN EXISTS (SELECT 1 FROM matches m
                  WHERE (m.user1_id = p_auteur AND m.user2_id = p_lecteur)
                     OR (m.user1_id = p_lecteur AND m.user2_id = p_auteur))
      OR EXISTS (SELECT 1 FROM conversations c
                  WHERE (c.user1_id = p_auteur AND c.user2_id = p_lecteur)
                     OR (c.user1_id = p_lecteur AND c.user2_id = p_auteur))
      OR public.sont_amis(p_auteur, p_lecteur);
EXCEPTION WHEN OTHERS THEN
  RETURN true;   -- en cas de souci, ne pas casser l'onglet Stories
END;
$$;
REVOKE ALL ON FUNCTION public.story_visible_pour(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.story_visible_pour(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS stories_visibilite_mutuelle ON public.stories;
CREATE POLICY stories_visibilite_mutuelle ON public.stories
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_admin()
    OR public.story_visible_pour(user_id, auth.uid())
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
