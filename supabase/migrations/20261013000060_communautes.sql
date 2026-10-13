-- ═══════════════════════════════════════════════════════════════════
-- 060 : Communautés — groupes publics créés par l'équipe Zamu, que
-- chacun peut rejoindre (300 membres maximum).
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
--
-- Créer une communauté (dans le SQL Editor) :
--   INSERT INTO public.groupes (nom, description, public)
--   VALUES ('⚽ Foot à Abidjan', 'Matchs, pronos et sorties au stade', true);
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.groupes
  ADD COLUMN IF NOT EXISTS public boolean NOT NULL DEFAULT false;

-- Liste des communautés (avec le nombre de membres)
CREATE OR REPLACE FUNCTION public.groupes_publics()
RETURNS TABLE (id uuid, nom text, description text, photo_url text,
               nb_membres int, deja_membre boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT g.id, g.nom, g.description, g.photo_url,
         (SELECT count(*)::int FROM groupe_membres m WHERE m.groupe_id = g.id),
         EXISTS (SELECT 1 FROM groupe_membres m
                  WHERE m.groupe_id = g.id AND m.user_id = auth.uid())
    FROM groupes g
   WHERE g.public AND g.evenement_id IS NULL
   ORDER BY 5 DESC, g.created_at;
$$;
REVOKE ALL ON FUNCTION public.groupes_publics() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.groupes_publics() TO authenticated;

-- Rejoindre une communauté
CREATE OR REPLACE FUNCTION public.rejoindre_groupe_public(p_groupe uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  nom_moi text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'non_connecte'; END IF;
  IF NOT EXISTS (SELECT 1 FROM groupes WHERE id = p_groupe AND public) THEN
    RAISE EXCEPTION 'introuvable' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()
              AND COALESCE(is_suspended, false)) THEN
    RAISE EXCEPTION 'suspendu' USING ERRCODE = 'P0001';
  END IF;
  IF (SELECT count(*) FROM groupe_membres WHERE groupe_id = p_groupe) >= 300 THEN
    RAISE EXCEPTION 'complet' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO groupe_membres (groupe_id, user_id)
  VALUES (p_groupe, auth.uid()) ON CONFLICT DO NOTHING;
  IF FOUND THEN
    SELECT name INTO nom_moi FROM profiles WHERE id = auth.uid();
    PERFORM public._message_systeme(p_groupe,
      COALESCE(nom_moi, 'Quelqu''un') || ' a rejoint la communauté');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.rejoindre_groupe_public(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.rejoindre_groupe_public(uuid) TO authenticated;

COMMIT;
