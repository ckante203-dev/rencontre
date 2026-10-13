-- 054 : réglage Premium « Masquer quand j'ai lu »
-- À exécuter dans le SQL Editor de Supabase.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS lectures_masquees boolean NOT NULL DEFAULT false;

-- ── Stories à la une (gardées sur le profil après 24 h) ──
BEGIN;

CREATE TABLE IF NOT EXISTS public.stories_une (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  media_url  text NOT NULL DEFAULT '',
  is_video   boolean NOT NULL DEFAULT false,
  texte      text CHECK (texte IS NULL OR char_length(texte) <= 500),
  fond       text,
  legende    text CHECK (legende IS NULL OR char_length(legende) <= 300),
  stickers   jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS stories_une_user_idx ON public.stories_une (user_id, created_at DESC);
ALTER TABLE public.stories_une ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS stories_une_select ON public.stories_une;
CREATE POLICY stories_une_select ON public.stories_une
  FOR SELECT TO authenticated
  USING (NOT public.blocage_entre(user_id, auth.uid()));

DROP POLICY IF EXISTS stories_une_insert ON public.stories_une;
CREATE POLICY stories_une_insert ON public.stories_une
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND (media_url = '' OR media_url LIKE '%/storage/v1/object/public/stories/%'));

DROP POLICY IF EXISTS stories_une_delete ON public.stories_une;
CREATE POLICY stories_une_delete ON public.stories_une
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- 10 au maximum par personne
CREATE OR REPLACE FUNCTION public.limite_stories_une()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT count(*) FROM public.stories_une WHERE user_id = NEW.user_id) >= 10 THEN
    RAISE EXCEPTION 'stories_une_max' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS limite_stories_une ON public.stories_une;
CREATE TRIGGER limite_stories_une BEFORE INSERT ON public.stories_une
  FOR EACH ROW EXECUTE FUNCTION public.limite_stories_une();

COMMIT;
