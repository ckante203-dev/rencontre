-- 052 : lien de billetterie / réservation sur les événements
-- + nombre d'ouvertures de l'album privé par personne
-- À exécuter dans le SQL Editor de Supabase.
BEGIN;

ALTER TABLE public.evenements
  ADD COLUMN IF NOT EXISTS lien text;
ALTER TABLE public.evenements DROP CONSTRAINT IF EXISTS evenements_lien_format;
ALTER TABLE public.evenements ADD CONSTRAINT evenements_lien_format
  CHECK (lien IS NULL OR (lien ~ '^https?://' AND char_length(lien) <= 300));

ALTER TABLE public.album_acces
  ADD COLUMN IF NOT EXISTS vues int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS derniere_vue timestamptz;

-- Appelée par l'app quand j'ouvre l'album de quelqu'un qui me l'a partagé
CREATE OR REPLACE FUNCTION public.noter_vue_album(p_owner uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  UPDATE album_acces
     SET vues = vues + 1, derniere_vue = now()
   WHERE owner_id = p_owner AND viewer_id = auth.uid();
$$;
REVOKE ALL ON FUNCTION public.noter_vue_album(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.noter_vue_album(uuid) TO authenticated;

COMMIT;
