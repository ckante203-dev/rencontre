-- ═══════════════════════════════════════════════════════════════════
-- 061 : annonces, sondages et notes de satisfaction affichés dans l'app
-- (fenêtre au lancement), créés depuis le panneau admin.
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
--
-- type = 'annonce'  : un message de l'équipe (bouton OK)
--        'sondage'  : une question + des choix (+ commentaire libre)
--        'note'     : « Tu aimes Zamu ? » 1 à 5 étoiles + commentaire
-- Chaque personne voit une fenêtre au plus une fois (sa réponse, ou
-- « plus tard », est enregistrée).
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS public.annonces_app (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type      text NOT NULL CHECK (type IN ('annonce', 'sondage', 'note')),
  titre     text NOT NULL CHECK (char_length(titre) BETWEEN 1 AND 120),
  texte     text CHECK (texte IS NULL OR char_length(texte) <= 1000),
  choix     jsonb NOT NULL DEFAULT '[]'::jsonb,   -- sondage : ["Oui", "Non", …]
  langue    text CHECK (langue IS NULL OR langue IN ('fr', 'en')), -- null = toutes
  actif     boolean NOT NULL DEFAULT true,
  cree_le   timestamptz NOT NULL DEFAULT now(),
  expire_le timestamptz
);

CREATE TABLE IF NOT EXISTS public.reponses_annonces (
  annonce_id  uuid NOT NULL REFERENCES public.annonces_app(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  choix       int,            -- index du choix (sondage)
  note        int CHECK (note IS NULL OR note BETWEEN 1 AND 5),
  commentaire text CHECK (commentaire IS NULL OR char_length(commentaire) <= 1000),
  ignoree     boolean NOT NULL DEFAULT false, -- « plus tard »
  cree_le     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (annonce_id, user_id)
);

ALTER TABLE public.annonces_app ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reponses_annonces ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS annonces_app_lecture ON public.annonces_app;
CREATE POLICY annonces_app_lecture ON public.annonces_app
  FOR SELECT TO authenticated USING (actif OR public.is_admin());
DROP POLICY IF EXISTS annonces_app_admin ON public.annonces_app;
CREATE POLICY annonces_app_admin ON public.annonces_app
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS reponses_annonces_moi ON public.reponses_annonces;
CREATE POLICY reponses_annonces_moi ON public.reponses_annonces
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS reponses_annonces_lecture ON public.reponses_annonces;
CREATE POLICY reponses_annonces_lecture ON public.reponses_annonces
  FOR SELECT TO authenticated USING (user_id = auth.uid() OR public.is_admin());

-- La fenêtre à montrer maintenant (la plus récente pas encore traitée)
CREATE OR REPLACE FUNCTION public.annonce_a_afficher(p_langue text DEFAULT 'fr')
RETURNS SETOF public.annonces_app
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.* FROM annonces_app a
   WHERE a.actif
     AND (a.expire_le IS NULL OR a.expire_le > now())
     AND (a.langue IS NULL OR a.langue = p_langue)
     AND NOT EXISTS (SELECT 1 FROM reponses_annonces r
                      WHERE r.annonce_id = a.id AND r.user_id = auth.uid())
   ORDER BY a.cree_le DESC
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.annonce_a_afficher(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.annonce_a_afficher(text) TO authenticated;

-- Résultats pour le panneau admin
CREATE OR REPLACE FUNCTION public.admin_resultats_annonce(p_annonce uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin requis' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'reponses',  (SELECT count(*) FROM reponses_annonces WHERE annonce_id = p_annonce AND NOT ignoree),
    'ignorees',  (SELECT count(*) FROM reponses_annonces WHERE annonce_id = p_annonce AND ignoree),
    'moyenne',   (SELECT round(avg(note)::numeric, 2) FROM reponses_annonces WHERE annonce_id = p_annonce AND note IS NOT NULL),
    'par_choix', COALESCE((SELECT jsonb_object_agg(choix, n) FROM (
                    SELECT choix, count(*) AS n FROM reponses_annonces
                     WHERE annonce_id = p_annonce AND choix IS NOT NULL GROUP BY choix) t), '{}'::jsonb),
    'par_note',  COALESCE((SELECT jsonb_object_agg(note, n) FROM (
                    SELECT note, count(*) AS n FROM reponses_annonces
                     WHERE annonce_id = p_annonce AND note IS NOT NULL GROUP BY note) t), '{}'::jsonb),
    'commentaires', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                        'texte', r.commentaire, 'note', r.note, 'choix', r.choix,
                        'nom', p.name, 'le', r.cree_le) ORDER BY r.cree_le DESC)
                      FROM reponses_annonces r JOIN profiles p ON p.id = r.user_id
                     WHERE r.annonce_id = p_annonce
                       AND COALESCE(r.commentaire, '') <> ''), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_resultats_annonce(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_resultats_annonce(uuid) TO authenticated;

COMMIT;
