-- ═══════════════════════════════════════════════════════════════════
-- 🔒 Album privé : vue unique ou durée limitée — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Le propriétaire choisit, en ouvrant son album à quelqu'un :
--   • une durée (1 h, 24 h, 7 jours…) → expire_le ;
--   • ou une VUE UNIQUE : à la 1ʳᵉ ouverture, l'accès ne dure plus que
--     2 minutes, puis se ferme tout seul (comme un snap).
-- C'est le serveur qui ferme l'accès (lignes ET fichiers) : l'app ne
-- peut pas le contourner. Les anciennes versions de l'app partagent
-- toujours « sans limite » (colonnes vides = comme avant).
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.album_acces
  ADD COLUMN IF NOT EXISTS expire_le timestamptz,
  ADD COLUMN IF NOT EXISTS vue_unique boolean NOT NULL DEFAULT false;

-- Accès valable : partagé, pas expiré, pas de blocage
CREATE OR REPLACE FUNCTION public.peut_voir_album(p_owner uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT auth.uid() = p_owner
      OR (EXISTS (SELECT 1 FROM album_acces a
                  WHERE a.owner_id = p_owner
                    AND a.viewer_id = auth.uid()
                    AND (a.expire_le IS NULL OR a.expire_le > now()))
          AND NOT public.blocage_entre(p_owner, auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.peut_voir_album(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.peut_voir_album(uuid) TO authenticated;

-- Ouverture comptée ; en vue unique, la 1ʳᵉ ouverture lance les 2 minutes
CREATE OR REPLACE FUNCTION public.noter_vue_album(p_owner uuid)
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  UPDATE album_acces
     SET vues = vues + 1,
         derniere_vue = now(),
         expire_le = CASE
           WHEN vue_unique
                AND (expire_le IS NULL OR expire_le > now() + interval '2 minutes')
             THEN now() + interval '2 minutes'
           ELSE expire_le END
   WHERE owner_id = p_owner AND viewer_id = auth.uid()
     AND (expire_le IS NULL OR expire_le > now());
$$;
REVOKE ALL ON FUNCTION public.noter_vue_album(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.noter_vue_album(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
