-- ═══════════════════════════════════════════════════════════════════
-- 062 : stories officielles « Zamu » (annonces de nouveautés), publiées
-- depuis le panneau admin, visibles par tout le monde en tête de
-- l'onglet Stories jusqu'à leur date de fin.
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS public.stories_officielles (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  media_url text NOT NULL DEFAULT '',
  is_video  boolean NOT NULL DEFAULT false,
  texte     text CHECK (texte IS NULL OR char_length(texte) <= 500),
  fond      text,
  legende   text CHECK (legende IS NULL OR char_length(legende) <= 300),
  cree_le   timestamptz NOT NULL DEFAULT now(),
  expire_le timestamptz NOT NULL DEFAULT now() + interval '7 days'
);
ALTER TABLE public.stories_officielles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stories_officielles_lecture ON public.stories_officielles;
CREATE POLICY stories_officielles_lecture ON public.stories_officielles
  FOR SELECT TO authenticated USING (expire_le > now() OR public.is_admin());
DROP POLICY IF EXISTS stories_officielles_admin ON public.stories_officielles;
CREATE POLICY stories_officielles_admin ON public.stories_officielles
  FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

COMMIT;
