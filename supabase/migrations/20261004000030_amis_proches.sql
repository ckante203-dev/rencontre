-- ═══════════════════════════════════════════════════════════════════
-- Stories « Amis proches » — 2026-10-04
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Avant : l'option « Amis seulement » de l'éditeur enregistrait
-- visibility = 'friends' mais RIEN ne filtrait → tout le monde voyait
-- ces stories. Désormais :
-- • amis_proches(owner_id, ami_id) : ma liste « Amis proches ». Personne
--   d'autre que moi ne peut la lire (on ne sait pas qu'on y est).
-- • politique RESTRICTIVE sur stories : une story 'friends' n'est lisible
--   que par son auteur, ses amis proches et les admins.
-- • relances de 19 h : les stories 'friends' ne comptent que pour les
--   amis proches de l'auteur.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.amis_proches (
  owner_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ami_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (owner_id, ami_id),
  CHECK (owner_id <> ami_id)
);
CREATE INDEX IF NOT EXISTS amis_proches_ami_idx ON public.amis_proches (ami_id);

ALTER TABLE public.amis_proches ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS amis_proches_select ON public.amis_proches;
CREATE POLICY amis_proches_select ON public.amis_proches
  FOR SELECT TO authenticated USING (owner_id = auth.uid());

DROP POLICY IF EXISTS amis_proches_insert ON public.amis_proches;
CREATE POLICY amis_proches_insert ON public.amis_proches
  FOR INSERT TO authenticated WITH CHECK (owner_id = auth.uid());

DROP POLICY IF EXISTS amis_proches_delete ON public.amis_proches;
CREATE POLICY amis_proches_delete ON public.amis_proches
  FOR DELETE TO authenticated USING (owner_id = auth.uid());

-- Vrai si `viewer` est dans la liste « Amis proches » de `owner`
CREATE OR REPLACE FUNCTION public.est_ami_proche(p_owner uuid, p_viewer uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM amis_proches
    WHERE owner_id = p_owner AND ami_id = p_viewer
  );
$$;
REVOKE ALL ON FUNCTION public.est_ami_proche(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.est_ami_proche(uuid, uuid) TO authenticated;

-- Stories « Amis proches » : seulement l'auteur, ses amis proches, admins
-- (RESTRICTIVE : s'ajoute à stories_select et stories_moderation)
DROP POLICY IF EXISTS stories_amis_proches ON public.stories;
CREATE POLICY stories_amis_proches ON public.stories
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(visibility, 'public') <> 'friends'
    OR user_id = auth.uid()
    OR public.est_ami_proche(user_id, auth.uid())
    OR public.is_admin()
  );

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
