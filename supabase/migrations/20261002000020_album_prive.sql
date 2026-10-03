-- ═══════════════════════════════════════════════════════════════════
-- Album privé (façon Grindr) — 2026-10-02
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- • Bucket PRIVÉ « albums » : dossier = id du propriétaire.
-- • album_photos : photos de chaque album (12 maximum).
-- • album_acces  : à qui le propriétaire a ouvert son album.
-- • Seuls le propriétaire et les personnes autorisées peuvent lister les
--   photos et obtenir un lien (temporaire) vers les fichiers.
-- • Un blocage entre les deux personnes coupe l'accès.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. Bucket privé (10 Mo max par photo, images uniquement)
-- ───────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('albums', 'albums', false, 10485760,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;

-- ───────────────────────────────────────────────────────────────────
-- 2. Tables
-- ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.album_photos (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  chemin     text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS album_photos_owner_idx
  ON public.album_photos (owner_id);

CREATE TABLE IF NOT EXISTS public.album_acces (
  owner_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  viewer_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, viewer_id),
  CHECK (owner_id <> viewer_id)
);
CREATE INDEX IF NOT EXISTS album_acces_viewer_idx
  ON public.album_acces (viewer_id);

-- Vrai si moi (auth.uid()) je peux voir l'album de p_owner
CREATE OR REPLACE FUNCTION public.peut_voir_album(p_owner uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() = p_owner
      OR (EXISTS (SELECT 1 FROM album_acces a
                  WHERE a.owner_id = p_owner AND a.viewer_id = auth.uid())
          AND NOT public.blocage_entre(p_owner, auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.peut_voir_album(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.peut_voir_album(uuid) TO authenticated;

-- ───────────────────────────────────────────────────────────────────
-- 3. Règles d'accès (RLS)
-- ───────────────────────────────────────────────────────────────────
ALTER TABLE public.album_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.album_acces  ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS album_photos_select ON public.album_photos;
CREATE POLICY album_photos_select ON public.album_photos
  FOR SELECT TO authenticated
  USING (public.peut_voir_album(owner_id));

DROP POLICY IF EXISTS album_photos_insert ON public.album_photos;
CREATE POLICY album_photos_insert ON public.album_photos
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid()
              AND chemin LIKE auth.uid()::text || '/%');

DROP POLICY IF EXISTS album_photos_delete ON public.album_photos;
CREATE POLICY album_photos_delete ON public.album_photos
  FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

DROP POLICY IF EXISTS album_acces_select ON public.album_acces;
CREATE POLICY album_acces_select ON public.album_acces
  FOR SELECT TO authenticated
  USING (owner_id = auth.uid() OR viewer_id = auth.uid());

DROP POLICY IF EXISTS album_acces_insert ON public.album_acces;
CREATE POLICY album_acces_insert ON public.album_acces
  FOR INSERT TO authenticated
  WITH CHECK (owner_id = auth.uid()
              AND NOT public.blocage_entre(owner_id, viewer_id));

DROP POLICY IF EXISTS album_acces_delete ON public.album_acces;
CREATE POLICY album_acces_delete ON public.album_acces
  FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- 12 photos maximum par album
CREATE OR REPLACE FUNCTION public.limite_album_photos()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF (SELECT count(*) FROM public.album_photos
      WHERE owner_id = NEW.owner_id) >= 12 THEN
    RAISE EXCEPTION 'album_plein' USING ERRCODE = 'P0001',
      HINT = '12 photos maximum dans l''album privé';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_limite_album_photos ON public.album_photos;
CREATE TRIGGER trg_limite_album_photos
  BEFORE INSERT ON public.album_photos
  FOR EACH ROW EXECUTE FUNCTION public.limite_album_photos();

-- ───────────────────────────────────────────────────────────────────
-- 4. Fichiers (Storage) : dossier « <id propriétaire>/… »
-- ───────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS albums_lecture ON storage.objects;
CREATE POLICY albums_lecture ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'albums'
         AND public.peut_voir_album(((storage.foldername(name))[1])::uuid));

DROP POLICY IF EXISTS albums_envoi ON storage.objects;
CREATE POLICY albums_envoi ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'albums'
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS albums_suppression ON storage.objects;
CREATE POLICY albums_suppression ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'albums'
         AND (storage.foldername(name))[1] = auth.uid()::text);

COMMIT;

NOTIFY pgrst, 'reload schema';
