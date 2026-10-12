-- 053 : Super Like (1 par jour, 5 avec Premium)
-- À exécuter dans le SQL Editor de Supabase.
BEGIN;

ALTER TABLE public.likes
  ADD COLUMN IF NOT EXISTS est_super boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.envoyer_super_like(p_to uuid)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_max int;
BEGIN
  IF v_uid IS NULL OR p_to IS NULL OR p_to = v_uid THEN
    RETURN 'invalide';
  END IF;
  IF EXISTS (SELECT 1 FROM likes WHERE from_user_id = v_uid AND to_user_id = p_to) THEN
    RETURN 'deja_like';
  END IF;
  IF public.blocage_entre(v_uid, p_to) THEN
    RETURN 'bloque';
  END IF;
  SELECT CASE WHEN COALESCE(is_premium, false)
                OR COALESCE(boost_jusqua > now(), false) THEN 5 ELSE 1 END
    INTO v_max FROM profiles WHERE id = v_uid;
  IF (SELECT count(*) FROM likes
       WHERE from_user_id = v_uid AND est_super
         AND created_at > now() - interval '24 hours') >= COALESCE(v_max, 1) THEN
    RETURN 'limite';
  END IF;
  INSERT INTO likes (from_user_id, to_user_id, est_super)
  VALUES (v_uid, p_to, true);
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.envoyer_super_like(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.envoyer_super_like(uuid) TO authenticated;

COMMIT;

-- ── Parrainage : code = @pseudo du parrain, 1 h de Boost pour les deux ──
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS parrain_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS parraine_le timestamptz;

CREATE OR REPLACE FUNCTION public.utiliser_code_parrainage(p_code text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_moi profiles%ROWTYPE;
  v_parrain uuid;
  v_recompenses int;
BEGIN
  IF v_uid IS NULL THEN RETURN 'invalide'; END IF;
  SELECT * INTO v_moi FROM profiles WHERE id = v_uid;
  IF v_moi.parrain_id IS NOT NULL THEN RETURN 'deja_parraine'; END IF;
  IF v_moi.created_at < now() - interval '7 days' THEN RETURN 'trop_tard'; END IF;
  SELECT id INTO v_parrain FROM profiles
   WHERE lower(username) = lower(trim(both '@' from p_code))
     AND NOT COALESCE(is_suspended, false)
   LIMIT 1;
  IF v_parrain IS NULL THEN RETURN 'introuvable'; END IF;
  IF v_parrain = v_uid THEN RETURN 'soi_meme'; END IF;

  UPDATE profiles SET parrain_id = v_parrain, parraine_le = now() WHERE id = v_uid;
  -- Filleul : 1 h de Boost
  UPDATE profiles
     SET boost_jusqua = GREATEST(COALESCE(boost_jusqua, now()), now()) + interval '1 hour'
   WHERE id = v_uid;
  -- Parrain : 1 h de Boost, 10 récompenses au plus par mois (anti-abus)
  SELECT count(*) INTO v_recompenses FROM profiles
   WHERE parrain_id = v_parrain AND parraine_le > now() - interval '30 days';
  IF v_recompenses <= 10 THEN
    UPDATE profiles
       SET boost_jusqua = GREATEST(COALESCE(boost_jusqua, now()), now()) + interval '1 hour'
     WHERE id = v_parrain;
  END IF;
  RETURN 'ok';
END;
$$;
REVOKE ALL ON FUNCTION public.utiliser_code_parrainage(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.utiliser_code_parrainage(text) TO authenticated;

-- Nombre de filleuls + possibilité d'entrer un code (compte < 7 jours)
CREATE OR REPLACE FUNCTION public.mon_parrainage()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'filleuls', (SELECT count(*) FROM profiles WHERE parrain_id = auth.uid()),
    'peut_saisir', (SELECT parrain_id IS NULL AND created_at > now() - interval '7 days'
                      FROM profiles WHERE id = auth.uid()));
$$;
REVOKE ALL ON FUNCTION public.mon_parrainage() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mon_parrainage() TO authenticated;

COMMIT;

-- ── Messages programmés : envoyés par le serveur à l'heure choisie ──
BEGIN;

CREATE TABLE IF NOT EXISTS public.messages_programmes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content         text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 2000),
  envoyer_le      timestamptz NOT NULL,
  cree_le         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS messages_programmes_envoi_idx
  ON public.messages_programmes (envoyer_le);
ALTER TABLE public.messages_programmes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS messages_programmes_select ON public.messages_programmes;
CREATE POLICY messages_programmes_select ON public.messages_programmes
  FOR SELECT TO authenticated USING (sender_id = auth.uid());

DROP POLICY IF EXISTS messages_programmes_insert ON public.messages_programmes;
CREATE POLICY messages_programmes_insert ON public.messages_programmes
  FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid()
              AND envoyer_le > now()
              AND envoyer_le < now() + interval '31 days'
              AND EXISTS (SELECT 1 FROM conversations c
                           WHERE c.id = conversation_id
                             AND auth.uid() IN (c.user1_id, c.user2_id))
              AND (SELECT count(*) FROM messages_programmes m
                    WHERE m.sender_id = auth.uid()) < 20);

DROP POLICY IF EXISTS messages_programmes_delete ON public.messages_programmes;
CREATE POLICY messages_programmes_delete ON public.messages_programmes
  FOR DELETE TO authenticated USING (sender_id = auth.uid());

-- Envoi : chaque message est inséré comme un message normal (les règles
-- habituelles s'appliquent : blocage, limite sans réponse…). S'il est
-- refusé, il est simplement abandonné.
CREATE OR REPLACE FUNCTION public.envoyer_messages_programmes()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT * FROM messages_programmes
            WHERE envoyer_le <= now() ORDER BY envoyer_le LIMIT 200 LOOP
    BEGIN
      INSERT INTO messages (conversation_id, sender_id, type, content, status)
      VALUES (r.conversation_id, r.sender_id, 'text', r.content, 'sent');
      UPDATE conversations SET updated_at = now() WHERE id = r.conversation_id;
    EXCEPTION WHEN others THEN
      RAISE LOG 'message programmé % non envoyé : %', r.id, SQLERRM;
    END;
    DELETE FROM messages_programmes WHERE id = r.id;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.envoyer_messages_programmes() FROM public, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'messages-programmes') THEN
    PERFORM cron.unschedule('messages-programmes');
  END IF;
END $$;
SELECT cron.schedule('messages-programmes', '* * * * *',
  $cron$SELECT public.envoyer_messages_programmes()$cron$);

COMMIT;
