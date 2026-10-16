-- ═══════════════════════════════════════════════════════════════════
-- Messages de l'équipe Zamu — 2026-10-16
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- AVANT : créer le compte officiel dans Authentication → Users → « Add
-- user » (e-mail support.zamuapp@gmail.com, un mot de passe, « Auto
-- confirm »). Ce script en fait le profil « Zamu » (vérifié, invisible
-- sur l'Accueil).
--
-- 1. Chaque nouvel inscrit reçoit un message de bienvenue de « Zamu »
--    (texte modifiable : app_config.message_bienvenue ; {prenom} est
--    remplacé par le prénom). Notification push comme un vrai message.
-- 2. Le panneau admin (page « Messages Zamu ») lit les réponses et répond
--    au nom de Zamu.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS est_officiel boolean NOT NULL DEFAULT false;
ALTER TABLE public.app_config ADD COLUMN IF NOT EXISTS message_bienvenue text;

UPDATE public.app_config
   SET message_bienvenue = COALESCE(message_bienvenue,
'Bienvenue sur Zamu, {prenom} 💜

Tu as 48 h de Premium offertes : vois qui t''a liké, découvre plus de profils et ton profil est mis en avant.

Quelques conseils :
📸 une photo où l''on voit ton visage
✅ fais vérifier ton profil (badge bleu)
👣 regarde « Croisés » sur l''Accueil

Une idée, un souci, une question ? Réponds-nous ici, on lit tout 🙂
— L''équipe Zamu')
 WHERE id = 'config';

-- ─── Compte officiel « Zamu » ───────────────────────────────────────
DO $$
DECLARE
  v uuid;
BEGIN
  SELECT id INTO v FROM auth.users WHERE email = 'support.zamuapp@gmail.com';
  IF v IS NULL THEN
    RAISE NOTICE 'Compte officiel absent : crée d''abord l''utilisateur support.zamuapp@gmail.com dans Authentication, puis relance ce script.';
    RETURN;
  END IF;
  INSERT INTO public.profiles (id, name, onboarding_complete, est_officiel)
  VALUES (v, 'Zamu', true, true)
  ON CONFLICT (id) DO UPDATE
    SET name = 'Zamu', onboarding_complete = true, est_officiel = true;
  UPDATE public.profiles
     SET est_verifie = true,
         bio = 'Le compte officiel de Zamu 💜 Une question, une idée ? Écris-nous ici.',
         boost_jusqua = NULL
   WHERE id = v;
END $$;

-- ─── 1. Message de bienvenue à l'inscription ────────────────────────
CREATE OR REPLACE FUNCTION public._message_bienvenue()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_off  uuid;
  v_conv uuid;
  v_txt  text;
BEGIN
  IF COALESCE(NEW.est_officiel, false) THEN RETURN NEW; END IF;
  IF COALESCE(NEW.onboarding_complete, false)
     AND (TG_OP = 'INSERT' OR NOT COALESCE(OLD.onboarding_complete, false))
     AND NEW.created_at > now() - interval '7 days' THEN
    SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
    IF v_off IS NULL OR v_off = NEW.id THEN RETURN NEW; END IF;
    SELECT message_bienvenue INTO v_txt FROM app_config WHERE id = 'config';
    IF COALESCE(btrim(v_txt), '') = '' THEN RETURN NEW; END IF;
    -- Une seule fois par personne
    IF EXISTS (SELECT 1 FROM conversations
                WHERE (user1_id = v_off AND user2_id = NEW.id)
                   OR (user1_id = NEW.id AND user2_id = v_off)) THEN
      RETURN NEW;
    END IF;
    INSERT INTO conversations (user1_id, user2_id, request_status, initiated_by)
    VALUES (v_off, NEW.id, 'accepted', v_off)
    RETURNING id INTO v_conv;
    INSERT INTO messages (conversation_id, sender_id, type, content, status)
    VALUES (v_conv, v_off, 'text',
            replace(v_txt, '{prenom}', COALESCE(NULLIF(btrim(NEW.name), ''), '')),
            'sent');
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;   -- jamais bloquer une inscription
END;
$$;

DROP TRIGGER IF EXISTS profiles_message_bienvenue ON public.profiles;
CREATE TRIGGER profiles_message_bienvenue
  AFTER INSERT OR UPDATE OF onboarding_complete ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._message_bienvenue();

-- ─── 2. Panneau admin : lire et répondre au nom de Zamu ─────────────
CREATE OR REPLACE FUNCTION public.admin_messages_zamu()
RETURNS TABLE (conversation_id uuid, user_id uuid, name text, photo_url text,
               dernier text, dernier_de_zamu boolean, dernier_le timestamptz,
               non_lus int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_off uuid;
BEGIN
  PERFORM public._exiger_admin();
  SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
  RETURN QUERY
    SELECT c.id,
           p.id,
           p.name::text,
           p.photo_url::text,
           m.content::text,
           (m.sender_id = v_off),
           m.created_at,
           (SELECT count(*)::int FROM messages x
             WHERE x.conversation_id = c.id AND x.sender_id <> v_off
               AND NOT COALESCE(x.is_read, false))
      FROM conversations c
      JOIN profiles p ON p.id = CASE WHEN c.user1_id = v_off THEN c.user2_id ELSE c.user1_id END
      LEFT JOIN LATERAL (SELECT * FROM messages y WHERE y.conversation_id = c.id
                          ORDER BY y.created_at DESC LIMIT 1) m ON true
     WHERE v_off IS NOT NULL AND (c.user1_id = v_off OR c.user2_id = v_off)
     -- Les conversations où la personne a répondu d'abord
     ORDER BY EXISTS (SELECT 1 FROM messages z WHERE z.conversation_id = c.id
                       AND z.sender_id <> v_off) DESC,
              m.created_at DESC NULLS LAST
     LIMIT 300;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_conversation_zamu(p_conv uuid)
RETURNS TABLE (id uuid, de_zamu boolean, content text, type text, created_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_off uuid;
BEGIN
  PERFORM public._exiger_admin();
  SELECT p.id INTO v_off FROM profiles p WHERE p.est_officiel ORDER BY p.created_at LIMIT 1;
  -- Lu par l'équipe
  UPDATE messages SET is_read = true
   WHERE conversation_id = p_conv AND sender_id <> v_off AND NOT COALESCE(is_read, false);
  RETURN QUERY
    SELECT m.id, (m.sender_id = v_off), m.content::text, m.type::text, m.created_at
      FROM messages m WHERE m.conversation_id = p_conv
     ORDER BY m.created_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_repondre_zamu(p_conv uuid, p_texte text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_off uuid;
  v_id  uuid;
BEGIN
  PERFORM public._exiger_admin();
  IF COALESCE(btrim(p_texte), '') = '' THEN RAISE EXCEPTION 'texte_vide' USING ERRCODE = 'P0001'; END IF;
  SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
  IF v_off IS NULL OR NOT EXISTS (SELECT 1 FROM conversations
                                   WHERE id = p_conv AND (user1_id = v_off OR user2_id = v_off)) THEN
    RAISE EXCEPTION 'conversation_introuvable' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO messages (conversation_id, sender_id, type, content, status)
  VALUES (p_conv, v_off, 'text', left(btrim(p_texte), 2000), 'sent')
  RETURNING id INTO v_id;
  UPDATE conversations SET updated_at = now() WHERE id = p_conv;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_messages_zamu() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_conversation_zamu(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_repondre_zamu(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_messages_zamu() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_conversation_zamu(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_repondre_zamu(uuid, text) TO authenticated;

-- ─── 3. Le compte « Zamu » n'apparaît pas sur l'Accueil ─────────────
CREATE OR REPLACE FUNCTION public.profils_accueil(
  p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL,
  p_limite int DEFAULT 300)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bloques text[];
  v_genre   text;
  v_cherche text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(blocked_users::text[], '{}'), gender::text, looking_for::text
    INTO v_bloques, v_genre, v_cherche
    FROM profiles WHERE id = v_uid;

  RETURN COALESCE((
    SELECT jsonb_agg(x.ligne ORDER BY x.booste DESC, x.dist NULLS LAST,
                                      x.vu DESC NULLS LAST)
    FROM (
      SELECT jsonb_build_object(
               'id', p.id, 'name', p.name, 'birthdate', p.birthdate,
               'bio', p.bio, 'photo_url', p.photo_url,
               'photo_urls', p.photo_urls, 'interests', p.interests,
               'latitude', p.latitude, 'longitude', p.longitude,
               'gender', p.gender, 'is_online', p.is_online,
               'last_seen', p.last_seen, 'created_at', p.created_at,
               'taille', p.taille, 'poids', p.poids,
               'morphologie', p.morphologie,
               'lieu_rencontre', p.lieu_rencontre,
               'is_premium', p.is_premium,
               'show_birthdate', p.show_birthdate,
               'show_distance', p.show_distance,
               'boost_jusqua', CASE WHEN public.boost_visible(p.id, p.boost_jusqua, p.boost_debut) THEN p.boost_jusqua END,
               'dispo_texte', p.dispo_texte,
               'dispo_jusqua', p.dispo_jusqua,
               'est_verifie', p.est_verifie,
               'metier', p.metier, 'etudes', p.etudes,
               'langues', p.langues, 'questions', p.questions) AS ligne,
             public.boost_visible(p.id, p.boost_jusqua, p.boost_debut) AS booste,
             CASE WHEN p_lat IS NULL OR p_lng IS NULL
                       OR p.latitude IS NULL OR p.longitude IS NULL THEN NULL
                  ELSE 12742 * asin(sqrt(
                         power(sin(radians(p.latitude::float8 - p_lat) / 2), 2)
                       + cos(radians(p_lat)) * cos(radians(p.latitude::float8))
                       * power(sin(radians(p.longitude::float8 - p_lng) / 2), 2)))
             END AS dist,
             p.last_seen AS vu
        FROM profiles p
       WHERE p.id <> v_uid
         AND NOT COALESCE(p.is_suspended, false)
         AND NOT COALESCE(p.est_officiel, false)   -- compte « Zamu » (SQL 072)
         AND NOT (p.id::text = ANY (v_bloques))
         AND NOT (v_uid::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
         -- Visibilité mutuelle (SQL 070) : chacun correspond à ce que l'autre cherche
         AND public._se_cherchent(v_genre, v_cherche, p.gender::text, p.looking_for::text)
       ORDER BY public.boost_visible(p.id, p.boost_jusqua, p.boost_debut) DESC,
                dist NULLS LAST, p.last_seen DESC NULLS LAST
       LIMIT LEAST(GREATEST(COALESCE(p_limite, 300), 1), 500)
    ) x
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.profils_accueil(double precision, double precision, int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.profils_accueil(double precision, double precision, int) TO authenticated;

COMMIT;
