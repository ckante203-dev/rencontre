-- ═══════════════════════════════════════════════════════════════════
-- Matchs + likes de story — 2026-09-28
-- 1. Crée la table `matches` que l'app utilise déjà (like_controller.dart,
--    supabase_service.dart) mais qui n'existait pas en base.
-- 2. Remplit `matches` à partir des likes réciproques existants et
--    remet en « accepted » les conversations entre personnes matchées
--    qui avaient été créées « pending » à cause de la table manquante.
-- 3. Fonction set_story_like : liker la story de quelqu'un d'autre
--    (la RLS n'autorise l'update de stories qu'au propriétaire).
-- Ré-exécutable sans risque.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. Table matches (user1_id < user2_id, comme dans l'app)
-- ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.matches (
  user1_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user2_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (user1_id, user2_id),
  CHECK (user1_id < user2_id)
);

ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS matches_select ON public.matches;
CREATE POLICY matches_select ON public.matches
  FOR SELECT USING (auth.uid() IN (user1_id, user2_id));

-- Un match ne peut être créé que par l'un des deux, et seulement s'il y a
-- un like dans les deux sens.
DROP POLICY IF EXISTS matches_insert ON public.matches;
CREATE POLICY matches_insert ON public.matches
  FOR INSERT WITH CHECK (
    auth.uid() IN (user1_id, user2_id)
    AND EXISTS (SELECT 1 FROM likes l
                WHERE l.from_user_id = matches.user1_id AND l.to_user_id = matches.user2_id)
    AND EXISTS (SELECT 1 FROM likes l
                WHERE l.from_user_id = matches.user2_id AND l.to_user_id = matches.user1_id)
  );

-- Nécessaire pour l'upsert de l'app quand le match existe déjà.
DROP POLICY IF EXISTS matches_update ON public.matches;
CREATE POLICY matches_update ON public.matches
  FOR UPDATE
  USING (auth.uid() IN (user1_id, user2_id))
  WITH CHECK (auth.uid() IN (user1_id, user2_id));

-- ───────────────────────────────────────────────────────────────────
-- 2. Rattrapage des données existantes
-- ───────────────────────────────────────────────────────────────────
INSERT INTO public.matches (user1_id, user2_id)
SELECT DISTINCT LEAST(a.from_user_id, a.to_user_id),
                GREATEST(a.from_user_id, a.to_user_id)
FROM likes a
JOIN likes b ON b.from_user_id = a.to_user_id AND b.to_user_id = a.from_user_id
WHERE a.from_user_id <> a.to_user_id
  AND EXISTS (SELECT 1 FROM profiles p WHERE p.id = a.from_user_id)
  AND EXISTS (SELECT 1 FROM profiles p WHERE p.id = a.to_user_id)
ON CONFLICT DO NOTHING;

UPDATE public.conversations c
SET request_status = 'accepted'
WHERE c.request_status = 'pending'
  AND EXISTS (SELECT 1 FROM public.matches m
              WHERE m.user1_id = LEAST(c.user1_id, c.user2_id)
                AND m.user2_id = GREATEST(c.user1_id, c.user2_id));

-- ───────────────────────────────────────────────────────────────────
-- 3. Like / unlike d'une story (atomique, fonctionne pour tous)
--    Le type de stories.liked_by (uuid[] ou text[]) est détecté.
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_story_like(p_story_id text, p_like boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_elem text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Non connecté' USING ERRCODE = '42501';
  END IF;

  SELECT ltrim(udt_name, '_') INTO v_elem
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'stories' AND column_name = 'liked_by';

  IF p_like THEN
    EXECUTE format(
      'UPDATE stories SET liked_by = array_append(coalesce(liked_by, ''{}''), $1::%1$s)
       WHERE id::text = $2 AND NOT ($1 = ANY (coalesce(liked_by, ''{}'')::text[]))',
      v_elem)
    USING v_uid::text, p_story_id;
  ELSE
    EXECUTE format(
      'UPDATE stories SET liked_by = array_remove(liked_by, $1::%1$s)
       WHERE id::text = $2',
      v_elem)
    USING v_uid::text, p_story_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.set_story_like(text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.set_story_like(text, boolean) TO authenticated;

COMMIT;
