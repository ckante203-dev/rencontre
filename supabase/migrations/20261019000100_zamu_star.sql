-- ═══════════════════════════════════════════════════════════════════
-- ⭐ Zamu Star — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Statut public sur DEMANDE, validé par Zamu (panneau admin), gratuit.
-- Critères (calculés par le serveur) : profil vérifié, photo avec
-- visage, compte de plus de 14 jours, 5 stories et 100 vues de stories
-- sur 30 jours. Avantages : badge ⭐, stories mises en avant.
--
-- 1. story_journal : chaque story et ses vues, gardés après la
--    suppression de la story (sinon impossible de compter sur 30 jours).
-- 2. zamu_stars (lisible par tous) et demandes_star (la sienne).
-- 3. criteres_star(), demander_star(), admin_star_*().
-- La décision est annoncée par un message du compte « Zamu ».
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Journal des stories ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_journal (
  story_id   uuid PRIMARY KEY,
  user_id    uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  vues       int NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS story_journal_user_idx
  ON public.story_journal (user_id, created_at DESC);
ALTER TABLE public.story_journal ENABLE ROW LEVEL SECURITY;
-- Aucun accès direct : seulement via criteres_star()

CREATE OR REPLACE FUNCTION public._journal_story()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO story_journal (story_id, user_id, created_at, vues)
  VALUES (NEW.id, NEW.user_id, COALESCE(NEW.created_at, now()),
          COALESCE(cardinality(NEW.viewed_by), 0))
  ON CONFLICT (story_id) DO UPDATE
    SET vues = GREATEST(story_journal.vues, EXCLUDED.vues);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;   -- ne jamais bloquer une story
END;
$$;

DROP TRIGGER IF EXISTS stories_journal ON public.stories;
CREATE TRIGGER stories_journal
  AFTER INSERT OR UPDATE OF viewed_by ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public._journal_story();

-- Stories encore en ligne : reprises dans le journal
INSERT INTO public.story_journal (story_id, user_id, created_at, vues)
SELECT s.id, s.user_id, COALESCE(s.created_at, now()),
       COALESCE(cardinality(s.viewed_by), 0)
  FROM public.stories s
ON CONFLICT (story_id) DO NOTHING;

-- ─── 2. Stars et demandes ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.zamu_stars (
  user_id   uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  categorie text NOT NULL,
  depuis    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.zamu_stars ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS zamu_stars_select ON public.zamu_stars;
CREATE POLICY zamu_stars_select ON public.zamu_stars
  FOR SELECT TO authenticated USING (true);

CREATE TABLE IF NOT EXISTS public.demandes_star (
  id           bigserial PRIMARY KEY,
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  categorie    text NOT NULL CHECK (categorie IN ('artiste','createur','lieu','personnalite')),
  presentation text NOT NULL CHECK (char_length(presentation) BETWEEN 10 AND 400),
  lien         text CHECK (lien IS NULL OR char_length(lien) <= 200),
  criteres     jsonb,
  statut       text NOT NULL DEFAULT 'en_attente'
               CHECK (statut IN ('en_attente','validee','refusee')),
  motif        text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  traitee_le   timestamptz
);
CREATE INDEX IF NOT EXISTS demandes_star_statut_idx
  ON public.demandes_star (statut, created_at);
ALTER TABLE public.demandes_star ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS demandes_star_select ON public.demandes_star;
CREATE POLICY demandes_star_select ON public.demandes_star
  FOR SELECT TO authenticated USING (user_id = auth.uid());
-- Écriture seulement via demander_star() / admin_star_decider()

-- ─── 3. Critères ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._criteres_star(p_user uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH p AS (SELECT * FROM profiles WHERE id = p_user),
       j AS (SELECT count(*) AS nb, COALESCE(sum(vues), 0) AS vues
               FROM story_journal
              WHERE user_id = p_user AND created_at > now() - interval '30 days')
  SELECT jsonb_build_object(
    'verifie',  COALESCE((SELECT est_verifie FROM p), false),
    'visage',   COALESCE((SELECT photo_visage FROM p), false),
    'anciennete', COALESCE((SELECT created_at < now() - interval '14 days' FROM p), false),
    'jamais_suspendu', NOT COALESCE((SELECT is_suspended FROM p), false),
    'stories',  (SELECT nb FROM j), 'stories_min', 5,
    'vues',     (SELECT vues FROM j), 'vues_min', 100,
    'ok', COALESCE((SELECT est_verifie FROM p), false)
          AND COALESCE((SELECT photo_visage FROM p), false)
          AND COALESCE((SELECT created_at < now() - interval '14 days' FROM p), false)
          AND NOT COALESCE((SELECT is_suspended FROM p), false)
          AND (SELECT nb FROM j) >= 5
          AND (SELECT vues FROM j) >= 100);
$$;
REVOKE ALL ON FUNCTION public._criteres_star(uuid) FROM public, anon, authenticated;

-- Mes critères + ma situation (Star ? demande en cours ?)
CREATE OR REPLACE FUNCTION public.criteres_star()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT public._criteres_star(auth.uid()) || jsonb_build_object(
    'est_star', EXISTS (SELECT 1 FROM zamu_stars WHERE user_id = auth.uid()),
    'demande', (SELECT jsonb_build_object('statut', statut, 'motif', motif,
                                          'created_at', created_at)
                  FROM demandes_star WHERE user_id = auth.uid()
                 ORDER BY created_at DESC LIMIT 1));
$$;
REVOKE ALL ON FUNCTION public.criteres_star() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.criteres_star() TO authenticated;

CREATE OR REPLACE FUNCTION public.demander_star(
  p_categorie text, p_presentation text, p_lien text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_crit jsonb;
BEGIN
  IF v_uid IS NULL THEN RETURN 'invalide'; END IF;
  IF EXISTS (SELECT 1 FROM zamu_stars WHERE user_id = v_uid) THEN RETURN 'deja_star'; END IF;
  IF EXISTS (SELECT 1 FROM demandes_star WHERE user_id = v_uid AND statut = 'en_attente') THEN
    RETURN 'en_attente';
  END IF;
  -- Après un refus : nouvelle demande possible 14 jours plus tard
  IF EXISTS (SELECT 1 FROM demandes_star WHERE user_id = v_uid AND statut = 'refusee'
              AND traitee_le > now() - interval '14 days') THEN
    RETURN 'trop_tot';
  END IF;
  v_crit := public._criteres_star(v_uid);
  IF NOT (v_crit->>'ok')::boolean THEN RETURN 'criteres'; END IF;
  IF p_categorie NOT IN ('artiste','createur','lieu','personnalite') THEN RETURN 'invalide'; END IF;
  IF char_length(btrim(COALESCE(p_presentation, ''))) < 10 THEN RETURN 'presentation'; END IF;
  INSERT INTO demandes_star (user_id, categorie, presentation, lien, criteres)
  VALUES (v_uid, p_categorie, left(btrim(p_presentation), 400),
          NULLIF(left(btrim(COALESCE(p_lien, '')), 200), ''), v_crit);
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.demander_star(text, text, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.demander_star(text, text, text) TO authenticated;

-- ─── 4. Message du compte « Zamu » à une personne ───────────────────
CREATE OR REPLACE FUNCTION public._message_zamu_a(p_user uuid, p_texte text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_off  uuid;
  v_conv uuid;
BEGIN
  SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
  IF v_off IS NULL OR v_off = p_user THEN RETURN; END IF;
  SELECT id INTO v_conv FROM conversations
   WHERE (user1_id = v_off AND user2_id = p_user)
      OR (user1_id = p_user AND user2_id = v_off)
   LIMIT 1;
  IF v_conv IS NULL THEN
    INSERT INTO conversations (user1_id, user2_id, request_status, initiated_by)
    VALUES (v_off, p_user, 'accepted', v_off)
    RETURNING id INTO v_conv;
  END IF;
  INSERT INTO messages (conversation_id, sender_id, type, content, status)
  VALUES (v_conv, v_off, 'text', p_texte, 'sent');
  UPDATE conversations SET updated_at = now() WHERE id = v_conv;
EXCEPTION WHEN OTHERS THEN
  RETURN;   -- le message ne doit jamais bloquer la décision
END;
$$;
REVOKE ALL ON FUNCTION public._message_zamu_a(uuid, text) FROM public, anon, authenticated;

-- ─── 5. Panneau admin ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_star_demandes(p_statut text DEFAULT 'en_attente')
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'id', d.id, 'user_id', d.user_id, 'categorie', d.categorie,
             'presentation', d.presentation, 'lien', d.lien,
             'criteres', public._criteres_star(d.user_id),
             'statut', d.statut, 'motif', d.motif,
             'created_at', d.created_at, 'traitee_le', d.traitee_le,
             'nom', p.name, 'pseudo', p.username, 'photo_url', p.photo_url,
             'est_verifie', p.est_verifie)
           ORDER BY d.created_at)
      FROM demandes_star d JOIN profiles p ON p.id = d.user_id
     WHERE d.statut = COALESCE(p_statut, d.statut)
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_stars()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
             'user_id', s.user_id, 'categorie', s.categorie, 'depuis', s.depuis,
             'nom', p.name, 'pseudo', p.username, 'photo_url', p.photo_url)
           ORDER BY s.depuis DESC)
      FROM zamu_stars s JOIN profiles p ON p.id = s.user_id
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_star_decider(
  p_demande bigint, p_valider boolean, p_motif text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  d demandes_star%ROWTYPE;
BEGIN
  PERFORM public._exiger_admin();
  SELECT * INTO d FROM demandes_star WHERE id = p_demande FOR UPDATE;
  IF NOT FOUND THEN RETURN 'introuvable'; END IF;
  IF d.statut <> 'en_attente' THEN RETURN 'deja_traitee'; END IF;
  UPDATE demandes_star
     SET statut = CASE WHEN p_valider THEN 'validee' ELSE 'refusee' END,
         motif = NULLIF(left(btrim(COALESCE(p_motif, '')), 300), ''),
         traitee_le = now()
   WHERE id = p_demande;
  IF p_valider THEN
    INSERT INTO zamu_stars (user_id, categorie) VALUES (d.user_id, d.categorie)
    ON CONFLICT (user_id) DO UPDATE SET categorie = EXCLUDED.categorie;
    PERFORM public._message_zamu_a(d.user_id,
      '⭐ Félicitations ! Tu es maintenant Zamu Star. Ton badge est actif et tes stories sont mises en avant auprès de tous les membres. Merci de respecter les règles : pas de nudité, pas d''arnaque.');
  ELSE
    PERFORM public._message_zamu_a(d.user_id,
      '⭐ Ta demande Zamu Star n''a pas été acceptée cette fois.'
      || CASE WHEN COALESCE(btrim(p_motif), '') <> '' THEN ' Motif : ' || btrim(p_motif) ELSE '' END
      || ' Tu pourras refaire une demande dans 14 jours.');
  END IF;
  RETURN 'ok';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_star_retirer(p_user uuid, p_motif text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  DELETE FROM zamu_stars WHERE user_id = p_user;
  IF NOT FOUND THEN RETURN 'pas_star'; END IF;
  PERFORM public._message_zamu_a(p_user,
    '⭐ Ton statut Zamu Star a été retiré.'
    || CASE WHEN COALESCE(btrim(p_motif), '') <> '' THEN ' Motif : ' || btrim(p_motif) ELSE '' END);
  RETURN 'ok';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_star_demandes(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_stars() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_star_decider(bigint, boolean, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_star_retirer(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_star_demandes(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_stars() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_star_decider(bigint, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_star_retirer(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
