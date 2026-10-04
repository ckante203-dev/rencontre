-- ═══════════════════════════════════════════════════════════════════
-- « Masquer ma story à… » — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 030 (amis proches).
-- Ré-exécutable sans risque.
--
-- • story_masquee(owner_id, cible_id) : les personnes à qui je masque
--   TOUTES mes stories (même publiques). Lisible par moi seul.
-- • politique RESTRICTIVE stories_masquees : la base ne renvoie jamais
--   une story à quelqu'un à qui son auteur l'a masquée.
-- • alertes ⭐ favoris (push + cloche) et relances de 19 h : ces personnes
--   ne sont pas prévenues des stories qu'elles ne peuvent pas voir.
--   (la cloche des favoris respecte aussi les blocages, oubli corrigé)
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.story_masquee (
  owner_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  cible_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, cible_id),
  CHECK (owner_id <> cible_id)
);
CREATE INDEX IF NOT EXISTS story_masquee_cible_idx ON public.story_masquee (cible_id);

ALTER TABLE public.story_masquee ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS story_masquee_select ON public.story_masquee;
CREATE POLICY story_masquee_select ON public.story_masquee
  FOR SELECT TO authenticated USING (owner_id = auth.uid());

DROP POLICY IF EXISTS story_masquee_insert ON public.story_masquee;
CREATE POLICY story_masquee_insert ON public.story_masquee
  FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS story_masquee_delete ON public.story_masquee;
CREATE POLICY story_masquee_delete ON public.story_masquee
  FOR DELETE TO authenticated USING (owner_id = auth.uid());

-- Vrai si `p_owner` masque ses stories à `p_viewer`
CREATE OR REPLACE FUNCTION public.story_masquee_pour(p_owner uuid, p_viewer uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM story_masquee
    WHERE owner_id = p_owner AND cible_id = p_viewer
  );
$$;
REVOKE ALL ON FUNCTION public.story_masquee_pour(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.story_masquee_pour(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS stories_masquees ON public.stories;
CREATE POLICY stories_masquees ON public.stories
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_admin()
    OR NOT public.story_masquee_pour(user_id, auth.uid())
  );

-- ── Alerte push « ⭐ X a publié une story » ──
CREATE OR REPLACE FUNCTION public.alerte_story_favoris()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n jsonb := to_jsonb(NEW);
  o jsonb;
  visible boolean;
  visible_avant boolean := false;
  f record;
BEGIN
  visible := COALESCE(n->>'visibility', 'public') = 'public'
    AND (n->>'moderation_status' IS NULL
         OR n->>'moderation_status' IN ('approved', 'unchecked'))
    AND (NEW.expires_at IS NULL OR NEW.expires_at > now());

  IF TG_OP = 'UPDATE' THEN
    o := to_jsonb(OLD);
    visible_avant := COALESCE(o->>'visibility', 'public') = 'public'
      AND (o->>'moderation_status' IS NULL
           OR o->>'moderation_status' IN ('approved', 'unchecked'));
  END IF;

  -- Alerte seulement quand la story DEVIENT visible
  IF NOT visible OR visible_avant THEN
    RETURN NULL;
  END IF;

  FOR f IN
    SELECT fv.user_id
    FROM favoris fv
    JOIN profiles p ON p.id = fv.user_id
    WHERE fv.favori_id = NEW.user_id
      AND COALESCE(p.notif_favoris, true)
      AND NOT public.blocage_entre(NEW.user_id, fv.user_id)
      AND NOT public.story_masquee_pour(NEW.user_id, fv.user_id)
  LOOP
    PERFORM public._alerte_favori(f.user_id, NEW.user_id, 'favori_story',
                                  interval '1 hour');
  END LOOP;

  RETURN NULL;
END;
$$;

-- ── Cloche « story d'un favori » ──
CREATE OR REPLACE FUNCTION public.cloche_story_favori()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  n jsonb := to_jsonb(NEW);
  o jsonb;
  visible boolean;
  visible_avant boolean := false;
  f record;
BEGIN
  visible := COALESCE(n->>'visibility', 'public') = 'public'
    AND (n->>'moderation_status' IS NULL
         OR n->>'moderation_status' IN ('approved', 'unchecked'));
  IF TG_OP = 'UPDATE' THEN
    o := to_jsonb(OLD);
    visible_avant := COALESCE(o->>'visibility', 'public') = 'public'
      AND (o->>'moderation_status' IS NULL
           OR o->>'moderation_status' IN ('approved', 'unchecked'));
  END IF;
  IF NOT visible OR visible_avant THEN
    RETURN NULL;
  END IF;
  FOR f IN SELECT fv.user_id FROM favoris fv
           WHERE fv.favori_id = NEW.user_id
             AND NOT public.blocage_entre(NEW.user_id, fv.user_id)
             AND NOT public.story_masquee_pour(NEW.user_id, fv.user_id)
  LOOP
    PERFORM public._cloche(f.user_id, NEW.user_id, 'favori_story',
                           NEW.id::text, interval '1 hour');
  END LOOP;
  RETURN NULL;
END;
$$;

-- ── Relances de 19 h ──
CREATE OR REPLACE FUNCTION public.relances_du_jour()
RETURNS TABLE (
  user_id uuid, fcm_token text, titre text, corps text,
  type text, filtre text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
#variable_conflict use_column
DECLARE
  p record;
  n int;
BEGIN
  FOR p IN
    SELECT pr.id, pr.fcm_token AS jeton, pr.latitude AS lat,
           pr.longitude AS lon, pr.last_seen AS vu,
           COALESCE(pr.notif_messages, true) AS nm,
           COALESCE(pr.notif_nearby, true)   AS nn,
           COALESCE(pr.notif_stories, true)  AS ns
    FROM profiles pr
    WHERE COALESCE(pr.fcm_token, '') <> ''
      AND NOT COALESCE(pr.is_suspended, false)
      AND pr.last_seen < now() - interval '24 hours'
      AND pr.last_seen > now() - interval '30 days'
      AND (pr.derniere_relance IS NULL
           OR pr.derniere_relance < now() - CASE
                WHEN pr.last_seen > now() - interval '7 days'
                THEN interval '20 hours' ELSE interval '68 hours' END)
  LOOP
    user_id := p.id;
    fcm_token := p.jeton;
    filtre := NULL;

    -- 1. Messages non lus
    IF p.nm THEN
      SELECT count(*) INTO n
      FROM messages m
      JOIN conversations c ON c.id = m.conversation_id
      WHERE (c.user1_id = p.id OR c.user2_id = p.id)
        AND m.sender_id <> p.id
        AND m.is_read IS NOT TRUE
        AND m.status IS DISTINCT FROM 'read'
        AND NOT public.blocage_entre(p.id, m.sender_id);
      IF n > 0 THEN
        titre := '💬 ' || n || CASE WHEN n > 1
                   THEN ' messages t''attendent' ELSE ' message t''attend' END;
        corps := 'Réponds avant que la conversation refroidisse 😉';
        type := 'reengagement';
        filtre := 'messages';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;

    -- 2. Visites de profil
    SELECT count(*) INTO n
    FROM profile_views v
    WHERE v.viewed_id = p.id
      AND v.viewer_id <> p.id
      AND v.created_at > greatest(p.vu, now() - interval '3 days');
    IF n > 0 THEN
      titre := '👀 ' || n || CASE WHEN n > 1
                 THEN ' personnes ont vu ton profil'
                 ELSE ' personne a vu ton profil' END;
      corps := 'Découvre qui s''intéresse à toi';
      type := 'profile_views';
      RETURN NEXT;
      CONTINUE;
    END IF;

    -- 3. Personnes « Dispo maintenant » à moins de 50 km
    IF p.nn AND p.lat IS NOT NULL AND p.lon IS NOT NULL THEN
      SELECT count(*) INTO n
      FROM profiles o
      WHERE o.id <> p.id
        AND o.dispo_texte IS NOT NULL
        AND o.dispo_jusqua > now()
        AND NOT COALESCE(o.is_suspended, false)
        AND o.latitude IS NOT NULL AND o.longitude IS NOT NULL
        AND 12742 * asin(sqrt(
              power(sin(radians(o.latitude - p.lat) / 2), 2)
              + cos(radians(p.lat)) * cos(radians(o.latitude))
                * power(sin(radians(o.longitude - p.lon) / 2), 2))) <= 50
        AND NOT public.blocage_entre(p.id, o.id);
      IF n > 0 THEN
        titre := '🙋 ' || n || CASE WHEN n > 1
                   THEN ' personnes près de toi sont dispo'
                   ELSE ' personne près de toi est dispo' END;
        corps := 'Café, sortie, discussion… vois qui est partant';
        type := 'reengagement';
        filtre := 'dispo';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;

    -- 4. Nouvelles stories depuis la dernière visite
    IF p.ns THEN
      SELECT count(*) INTO n
      FROM stories s
      WHERE s.user_id <> p.id
        AND s.expires_at > now()
        AND s.created_at > p.vu
        AND (s.moderation_status IS NULL
             OR s.moderation_status IN ('approved', 'unchecked'))
        AND (COALESCE(s.visibility, 'public') <> 'friends'
             OR public.est_ami_proche(s.user_id, p.id))
        AND NOT public.story_masquee_pour(s.user_id, p.id)
        AND NOT public.blocage_entre(p.id, s.user_id);
      IF n >= 2 THEN
        titre := '📸 ' || n || ' nouvelles stories';
        corps := 'Depuis ta dernière visite sur Zamu';
        type := 'new_story';
        RETURN NEXT;
        CONTINUE;
      END IF;
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.relances_du_jour() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.relances_du_jour() TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
