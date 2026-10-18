-- ═══════════════════════════════════════════════════════════════════
-- « Signaler un bug » — 2026-10-18 (app 1.1.10)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Paramètres → « Signaler un bug » : le membre décrit le problème (+ une
-- capture d'écran facultative) ; l'app joint sa version, le modèle du
-- téléphone et la version d'Android. Le panneau admin (page « Bugs
-- signalés ») les liste, change le statut et répond : la réponse arrive
-- dans la conversation « Zamu » du membre.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.bugs_signales (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  texte       text NOT NULL CHECK (char_length(btrim(texte)) BETWEEN 5 AND 2000),
  capture     text,           -- chemin dans le bucket privé « bugs »
  app_version text CHECK (app_version IS NULL OR char_length(app_version) <= 40),
  appareil    text CHECK (appareil IS NULL OR char_length(appareil) <= 120),
  systeme     text CHECK (systeme IS NULL OR char_length(systeme) <= 120),
  ecran       text CHECK (ecran IS NULL OR char_length(ecran) <= 80),
  statut      text NOT NULL DEFAULT 'nouveau'
              CHECK (statut IN ('nouveau', 'en_cours', 'resolu', 'ignore')),
  reponse     text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  traite_le   timestamptz
);
CREATE INDEX IF NOT EXISTS bugs_signales_date_idx
  ON public.bugs_signales (created_at DESC);
CREATE INDEX IF NOT EXISTS bugs_signales_user_idx
  ON public.bugs_signales (user_id, created_at DESC);

ALTER TABLE public.bugs_signales ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bugs_envoi ON public.bugs_signales;
CREATE POLICY bugs_envoi ON public.bugs_signales
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND statut = 'nouveau' AND reponse IS NULL);
DROP POLICY IF EXISTS bugs_lecture ON public.bugs_signales;
CREATE POLICY bugs_lecture ON public.bugs_signales
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR COALESCE(public.is_admin(), false));

-- Anti-abus : 5 signalements par jour et par personne
CREATE OR REPLACE FUNCTION public.limiter_bugs()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF (SELECT count(*) FROM bugs_signales
       WHERE user_id = NEW.user_id AND created_at > now() - interval '1 day') >= 5 THEN
    RAISE EXCEPTION 'trop_de_signalements' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_limiter_bugs ON public.bugs_signales;
CREATE TRIGGER trg_limiter_bugs
  BEFORE INSERT ON public.bugs_signales
  FOR EACH ROW EXECUTE FUNCTION public.limiter_bugs();

-- ─── Captures d'écran : bucket privé « bugs », dossier <uid>/ ───────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('bugs', 'bugs', false, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS bugs_capture_envoi ON storage.objects;
CREATE POLICY bugs_capture_envoi ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'bugs' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS bugs_capture_admin ON storage.objects;
CREATE POLICY bugs_capture_admin ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'bugs' AND COALESCE(public.is_admin(), false));
DROP POLICY IF EXISTS bugs_capture_admin_suppr ON storage.objects;
CREATE POLICY bugs_capture_admin_suppr ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'bugs' AND COALESCE(public.is_admin(), false));

-- ─── Panneau admin ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_bugs(p_statut text DEFAULT NULL)
RETURNS TABLE (id uuid, user_id uuid, name text, username text, photo_url text,
               texte text, capture text, app_version text, appareil text,
               systeme text, ecran text, statut text, reponse text,
               created_at timestamptz, traite_le timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT b.id, b.user_id, p.name::text, p.username::text, p.photo_url::text,
           b.texte, b.capture, b.app_version, b.appareil, b.systeme, b.ecran,
           b.statut, b.reponse, b.created_at, b.traite_le
      FROM bugs_signales b
      JOIN profiles p ON p.id = b.user_id
     WHERE p_statut IS NULL OR b.statut = p_statut
     ORDER BY b.created_at DESC
     LIMIT 300;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_compter_bugs()
RETURNS bigint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN (SELECT count(*) FROM bugs_signales WHERE statut = 'nouveau');
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_statut_bug(p_id uuid, p_statut text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  IF p_statut NOT IN ('nouveau', 'en_cours', 'resolu', 'ignore') THEN
    RAISE EXCEPTION 'statut_invalide' USING ERRCODE = 'P0001';
  END IF;
  UPDATE bugs_signales
     SET statut = p_statut,
         traite_le = CASE WHEN p_statut IN ('resolu', 'ignore') THEN now() ELSE traite_le END
   WHERE id = p_id;
END;
$$;

-- Répondre : le message part dans la conversation « Zamu » du membre
-- (créée si besoin), avec une notification comme tout message.
CREATE OR REPLACE FUNCTION public.admin_repondre_bug(p_id uuid, p_texte text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user uuid;
  v_off  uuid;
  v_conv uuid;
  v_msg  uuid;
BEGIN
  PERFORM public._exiger_admin();
  IF COALESCE(btrim(p_texte), '') = '' THEN
    RAISE EXCEPTION 'texte_vide' USING ERRCODE = 'P0001';
  END IF;
  SELECT user_id INTO v_user FROM bugs_signales WHERE id = p_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'introuvable' USING ERRCODE = 'P0001'; END IF;
  SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    RAISE EXCEPTION 'compte_zamu_absent' USING ERRCODE = 'P0001';
  END IF;
  SELECT id INTO v_conv FROM conversations
   WHERE (user1_id = v_off AND user2_id = v_user)
      OR (user1_id = v_user AND user2_id = v_off)
   LIMIT 1;
  IF v_conv IS NULL THEN
    INSERT INTO conversations (user1_id, user2_id, request_status, initiated_by)
    VALUES (v_off, v_user, 'accepted', v_off)
    RETURNING id INTO v_conv;
  END IF;
  INSERT INTO messages (conversation_id, sender_id, type, content, status)
  VALUES (v_conv, v_off, 'text', left(btrim(p_texte), 2000), 'sent')
  RETURNING id INTO v_msg;
  UPDATE conversations SET updated_at = now() WHERE id = v_conv;
  UPDATE bugs_signales
     SET reponse = left(btrim(p_texte), 2000),
         statut = CASE WHEN statut = 'nouveau' THEN 'en_cours' ELSE statut END
   WHERE id = p_id;
  RETURN v_msg;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bugs(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_compter_bugs() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_statut_bug(uuid, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_repondre_bug(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_bugs(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_compter_bugs() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_statut_bug(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_repondre_bug(uuid, text) TO authenticated;

-- Temps réel : le panneau est prévenu à chaque nouveau bug
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime'
                    AND schemaname = 'public' AND tablename = 'bugs_signales') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.bugs_signales;
  END IF;
END $$;

COMMIT;
