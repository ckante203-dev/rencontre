-- ═══════════════════════════════════════════════════════════════════
-- Alertes sécurité — 2026-10-18
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- La base repère automatiquement, par mots-clés (FR + EN) :
--   • 🔞 mineur possible : « j'ai 16 ans », « je suis au collège »,
--     « né en 2010 », date de naissance < 18 ans…
--   • ⚠️ danger : menaces (« je vais te tuer »), idées suicidaires,
--     armes, viol, chantage aux photos…
-- dans les messages privés, les messages de groupe, la bio, le nom et le
-- pseudo. Chaque détection crée une alerte visible dans le panneau admin
-- (Dashboard + page « Alertes sécurité ») avec la phrase et les 3
-- messages qui la précèdent. Rien d'autre des conversations n'est lisible.
-- La détection ne bloque jamais l'envoi d'un message.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.alertes_securite (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  categorie       text NOT NULL CHECK (categorie IN ('mineur', 'danger')),
  source          text NOT NULL,  -- message, groupe, bio, nom, pseudo, date_naissance
  extrait         text,           -- la phrase (300 caractères max)
  mot             text,           -- ce qui a déclenché l'alerte
  contexte        jsonb,          -- 3 messages précédents (copie : les messages s'effacent)
  conversation_id uuid,
  groupe_id       uuid,
  message_id      uuid,
  statut          text NOT NULL DEFAULT 'nouvelle'
                  CHECK (statut IN ('nouvelle', 'traitee', 'fausse_alerte')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  traitee_le      timestamptz,
  traitee_par     text
);
CREATE INDEX IF NOT EXISTS alertes_securite_nouvelles_idx
  ON public.alertes_securite (created_at DESC) WHERE statut = 'nouvelle';
CREATE INDEX IF NOT EXISTS alertes_securite_user_idx
  ON public.alertes_securite (user_id, created_at DESC);

ALTER TABLE public.alertes_securite ENABLE ROW LEVEL SECURITY;
-- Lecture réservée aux admins (et temps réel du panneau)
DROP POLICY IF EXISTS alertes_securite_admin ON public.alertes_securite;
CREATE POLICY alertes_securite_admin ON public.alertes_securite
  FOR SELECT TO authenticated USING (COALESCE(public.is_admin(), false));

-- ─── Détection par mots-clés ────────────────────────────────────────
-- Renvoie une ligne par catégorie trouvée (categorie, mot déclencheur).
CREATE OR REPLACE FUNCTION public._detecter_risque(p_texte text)
RETURNS TABLE (categorie text, mot text)
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  t text;
  m text[];
  pat text;
  annee int;
  regles_mineur text[] := ARRAY[
    -- « j'ai 16 ans », « g 15ans », « moi 14 ans », « âge : 17 ans »
    '(\mj\s?''?\s?ai|\mjai|\mg|\mmoi|\mage|âge)\s*(que|seulement|juste|bientot|bientôt)?\s*:?\s*(1[0-7]|[5-9])\s*ans?\M',
    -- message qui commence par l'âge : « 16 ans et toi ? »
    '^\W*(1[0-7])\s*ans?\M',
    -- « je suis mineur(e) »
    '\m(je suis|jsuis|j''suis|chui|suis)\s+(une?\s+)?mineure?\M',
    -- école : « je suis en 3e », « au collège », « je suis lycéenne »
    '\m(je suis|jsuis|j''suis|chui)\s+(en|au)\s+(6|5|4|3)\s*(e|è|eme|ème|ieme|ième)\M',
    '\m(je suis|jsuis|j''suis|chui)\s+(en|au)\s+(coll[eè]ge|lyc[eé]e|seconde|2nde|cm1|cm2)\M',
    '\m(je suis|jsuis|j''suis|chui)\s+(une?\s+)?(coll[eé]gien|lyc[eé]en|[eé]l[eè]ve)(ne)?\M',
    '\mje\s+(passe|pr[eé]pare|vais passer)\s+(le\s+|mon\s+)?(bepc|brevet|cepe|cep)\M',
    -- anglais
    '\m(i''?m|im|i am)\s+(only\s+|just\s+)?(1[0-7])\M(?!\s*(min|minutes|h|hours|km|kg|cm|%))',
    '\m(1[0-7])\s*(yo|y/o|yrs? old|years? old)\M',
    '\m(i''?m|i am)\s+(a\s+)?minor\M',
    '\m(i''?m|i am)\s+in\s+(middle|high)\s+school\M'
  ];
  regles_danger text[] := ARRAY[
    -- menaces
    '\mje\s+(vais|vas|veux|v)\s+(te|vous|t'')\s*(tuer|buter|d[eé]foncer|massacrer|[eé]gorger|planter|cramer|violer|frapper|tabasser)\M',
    '\m(on|ils)\s+(va|vont)\s+te\s+(tuer|buter|retrouver|d[eé]foncer)\M',
    '\mje\s+(te|vous)\s+(tue|tuerai|bute|buterai|d[eé]fonce)\M',
    '\mt''?\s?(es|e)\s+(un\s+homme\s+|une\s+femme\s+)?mort(e)?\M(?!\s*(de\s+rire|de\s+fatigue|mdr|ptdr|😂))',
    '\mje\s+(sais|connais)\s+o[uù]\s+tu\s+(habites|vis|dors)\M',
    '\mje\s+vais\s+te\s+(faire\s+(du\s+mal|la\s+peau)|retrouver)\M',
    -- détresse / suicide
    '\msuicid',
    '\mme\s+(tuer|suicider|pendre|foutre en l''air)\M',
    '\men\s+finir\s+avec\s+(la|ma)\s+vie\M',
    '\m(envie|veux)\s+(de\s+)?mourir\M',
    '\mplus\s+envie\s+de\s+vivre\M',
    -- armes, violences sexuelles
    '\m(pistolet|flingue|kalach|kalachnikov|machette|arme\s+blanche|revolver)\M',
    '\mviol(er|é|ée|e)?\M',
    -- chantage aux photos (sextorsion)
    '\mje\s+(vais|vas)\s+(publier|envoyer|diffuser|balancer|montrer)\s+(tes|ta|ton|vos)\s+(photos?|nudes?|vid[eé]os?|nus?)\M',
    -- anglais
    '\m(i''?ll|i will|gonna)\s+kill\s+(you|u)\M',
    '\mkill\s+(my|your)self\M',
    '\mkys\M',
    '\mi\s+want\s+to\s+die\M'
  ];
BEGIN
  IF p_texte IS NULL OR btrim(p_texte) = '' THEN RETURN; END IF;
  t := lower(replace(replace(p_texte, '’', ''''), '`', ''''));

  FOREACH pat IN ARRAY regles_mineur LOOP
    m := regexp_match(t, '(' || pat || ')');
    IF m IS NOT NULL THEN
      categorie := 'mineur'; mot := left(m[1], 80); RETURN NEXT; EXIT;
    END IF;
  END LOOP;
  IF categorie IS NULL THEN
    -- « né(e) en 2010 », « born in 2011 » : moins de 18 ans cette année
    m := regexp_match(t, '\m(n[eé]e?|born)\s+(en|in)\s+(20[0-2][0-9])\M');
    IF m IS NOT NULL THEN
      annee := m[3]::int;
      IF extract(year FROM now())::int - annee < 18 THEN
        categorie := 'mineur'; mot := m[1] || ' ' || m[2] || ' ' || m[3]; RETURN NEXT;
      END IF;
    END IF;
  END IF;

  FOREACH pat IN ARRAY regles_danger LOOP
    m := regexp_match(t, '(' || pat || ')');
    IF m IS NOT NULL THEN
      categorie := 'danger'; mot := left(m[1], 80); RETURN NEXT; EXIT;
    END IF;
  END LOOP;
END;
$$;

-- Crée l'alerte (sauf doublon : même personne, même catégorie, même
-- source en attente depuis moins de 10 min)
CREATE OR REPLACE FUNCTION public._creer_alerte(
  p_user uuid, p_categorie text, p_source text, p_extrait text, p_mot text,
  p_contexte jsonb DEFAULT NULL, p_conversation uuid DEFAULT NULL,
  p_groupe uuid DEFAULT NULL, p_message uuid DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM alertes_securite
              WHERE user_id = p_user AND categorie = p_categorie
                AND source = p_source AND statut = 'nouvelle'
                AND created_at > now() - interval '10 minutes') THEN
    RETURN;
  END IF;
  INSERT INTO alertes_securite (user_id, categorie, source, extrait, mot,
                                contexte, conversation_id, groupe_id, message_id)
  VALUES (p_user, p_categorie, p_source, left(p_extrait, 300), p_mot,
          p_contexte, p_conversation, p_groupe, p_message);
END;
$$;
REVOKE ALL ON FUNCTION public._creer_alerte(uuid, text, text, text, text, jsonb, uuid, uuid, uuid) FROM public, anon, authenticated;

-- ─── Messages privés ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alerte_message()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r record;
  v_ctx jsonb;
BEGIN
  BEGIN
    IF NEW.sender_id IS NULL OR COALESCE(NEW.type, 'text') <> 'text' THEN
      RETURN NEW;
    END IF;
    FOR r IN SELECT * FROM public._detecter_risque(NEW.content) LOOP
      SELECT jsonb_agg(x ORDER BY x.created_at) INTO v_ctx FROM (
        SELECT m.created_at, (m.sender_id = NEW.sender_id) AS auteur,
               left(m.content, 300) AS texte
          FROM messages m
         WHERE m.conversation_id = NEW.conversation_id
           AND m.id <> NEW.id AND m.created_at <= NEW.created_at
           AND COALESCE(m.type, 'text') = 'text'
         ORDER BY m.created_at DESC LIMIT 3) x;
      PERFORM public._creer_alerte(NEW.sender_id, r.categorie, 'message',
        NEW.content, r.mot, v_ctx, NEW.conversation_id, NULL, NEW.id);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- une erreur de détection ne doit jamais bloquer un message
  END;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_alerte_message ON public.messages;
CREATE TRIGGER trg_alerte_message
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.alerte_message();

-- ─── Messages de groupe ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.alerte_message_groupe()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r record;
  v_ctx jsonb;
BEGIN
  BEGIN
    IF NEW.sender_id IS NULL OR NEW.type <> 'texte' THEN RETURN NEW; END IF;
    FOR r IN SELECT * FROM public._detecter_risque(NEW.contenu) LOOP
      SELECT jsonb_agg(x ORDER BY x.created_at) INTO v_ctx FROM (
        SELECT g.created_at, (g.sender_id = NEW.sender_id) AS auteur,
               left(g.contenu, 300) AS texte
          FROM groupe_messages g
         WHERE g.groupe_id = NEW.groupe_id AND g.id <> NEW.id
           AND g.created_at <= NEW.created_at AND g.type = 'texte'
         ORDER BY g.created_at DESC LIMIT 3) x;
      PERFORM public._creer_alerte(NEW.sender_id, r.categorie, 'groupe',
        NEW.contenu, r.mot, v_ctx, NULL, NEW.groupe_id, NEW.id);
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_alerte_message_groupe ON public.groupe_messages;
CREATE TRIGGER trg_alerte_message_groupe
  AFTER INSERT ON public.groupe_messages
  FOR EACH ROW EXECUTE FUNCTION public.alerte_message_groupe();

-- ─── Profil : bio, nom, pseudo, date de naissance ───────────────────
CREATE OR REPLACE FUNCTION public.alerte_profil()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r record;
  v_age int;
BEGIN
  BEGIN
    IF TG_OP = 'INSERT' OR NEW.bio IS DISTINCT FROM OLD.bio THEN
      FOR r IN SELECT * FROM public._detecter_risque(NEW.bio) LOOP
        PERFORM public._creer_alerte(NEW.id, r.categorie, 'bio', NEW.bio, r.mot);
      END LOOP;
    END IF;
    IF TG_OP = 'INSERT' OR NEW.name IS DISTINCT FROM OLD.name THEN
      FOR r IN SELECT * FROM public._detecter_risque(NEW.name) LOOP
        PERFORM public._creer_alerte(NEW.id, r.categorie, 'nom', NEW.name, r.mot);
      END LOOP;
    END IF;
    IF TG_OP = 'INSERT' OR NEW.username IS DISTINCT FROM OLD.username THEN
      -- pseudo : seulement « mineur/minor » ou un âge collé (« lea15ans »)
      IF NEW.username ~* '(mineur|minor|1[0-7]ans|1[0-7]yo)' THEN
        PERFORM public._creer_alerte(NEW.id, 'mineur', 'pseudo', NEW.username,
          substring(lower(NEW.username) from '(mineur|minor|1[0-7]ans|1[0-7]yo)'));
      END IF;
    END IF;
    IF NEW.birthdate IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.birthdate IS DISTINCT FROM OLD.birthdate) THEN
      v_age := extract(year FROM age(now(), NEW.birthdate::date))::int;
      IF v_age < 18 THEN
        PERFORM public._creer_alerte(NEW.id, 'mineur', 'date_naissance',
          'Date de naissance : ' || to_char(NEW.birthdate::date, 'DD/MM/YYYY'),
          v_age || ' ans');
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_alerte_profil ON public.profiles;
CREATE TRIGGER trg_alerte_profil
  AFTER INSERT OR UPDATE OF bio, name, username, birthdate ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.alerte_profil();

-- ─── Panneau admin ──────────────────────────────────────────────────
-- Alertes (nouvelles par défaut), avec la personne et son nombre d'alertes
CREATE OR REPLACE FUNCTION public.admin_alertes(p_statut text DEFAULT 'nouvelle')
RETURNS TABLE (id uuid, user_id uuid, name text, username text, photo_url text,
               est_verifie boolean, is_banned boolean, categorie text,
               source text, extrait text, mot text, contexte jsonb,
               conversation_id uuid, groupe_id uuid, statut text,
               created_at timestamptz, traitee_le timestamptz,
               traitee_par text, nb_alertes bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT a.id, a.user_id, p.name::text, p.username::text, p.photo_url::text,
           COALESCE(p.est_verifie, false), COALESCE(p.is_banned, false),
           a.categorie, a.source, a.extrait, a.mot, a.contexte,
           a.conversation_id, a.groupe_id, a.statut, a.created_at,
           a.traitee_le, a.traitee_par,
           (SELECT count(*) FROM alertes_securite b WHERE b.user_id = a.user_id)
      FROM alertes_securite a
      JOIN profiles p ON p.id = a.user_id
     WHERE (p_statut IS NULL OR a.statut = p_statut)
     ORDER BY a.created_at DESC
     LIMIT 200;
END;
$$;

-- Les 3 messages qui ont suivi (s'ils existent encore)
CREATE OR REPLACE FUNCTION public.admin_alerte_suite(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  a alertes_securite;
  v jsonb;
BEGIN
  PERFORM public._exiger_admin();
  SELECT * INTO a FROM alertes_securite WHERE id = p_id;
  IF a.id IS NULL THEN RETURN '[]'::jsonb; END IF;
  IF a.conversation_id IS NOT NULL THEN
    SELECT jsonb_agg(x ORDER BY x.created_at) INTO v FROM (
      SELECT m.created_at, (m.sender_id = a.user_id) AS auteur,
             left(m.content, 300) AS texte
        FROM messages m
       WHERE m.conversation_id = a.conversation_id
         AND m.created_at > a.created_at - interval '1 second'
         AND m.id IS DISTINCT FROM a.message_id
         AND COALESCE(m.type, 'text') = 'text'
       ORDER BY m.created_at LIMIT 3) x;
  ELSIF a.groupe_id IS NOT NULL THEN
    SELECT jsonb_agg(x ORDER BY x.created_at) INTO v FROM (
      SELECT g.created_at, (g.sender_id = a.user_id) AS auteur,
             left(g.contenu, 300) AS texte
        FROM groupe_messages g
       WHERE g.groupe_id = a.groupe_id
         AND g.created_at > a.created_at - interval '1 second'
         AND g.id IS DISTINCT FROM a.message_id AND g.type = 'texte'
       ORDER BY g.created_at LIMIT 3) x;
  END IF;
  RETURN COALESCE(v, '[]'::jsonb);
END;
$$;

-- Marquer traitée / fausse alerte (ou remettre en nouvelle)
CREATE OR REPLACE FUNCTION public.admin_traiter_alerte(p_id uuid, p_statut text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  IF p_statut NOT IN ('nouvelle', 'traitee', 'fausse_alerte') THEN
    RAISE EXCEPTION 'statut_invalide' USING ERRCODE = 'P0001';
  END IF;
  UPDATE alertes_securite
     SET statut = p_statut,
         traitee_le = CASE WHEN p_statut = 'nouvelle' THEN NULL ELSE now() END,
         traitee_par = CASE WHEN p_statut = 'nouvelle' THEN NULL
                            ELSE auth.jwt() ->> 'email' END
   WHERE id = p_id;
END;
$$;

-- Toutes les alertes en attente d'une personne d'un coup (après un bannissement)
CREATE OR REPLACE FUNCTION public.admin_traiter_alertes_user(p_user uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  UPDATE alertes_securite
     SET statut = 'traitee', traitee_le = now(), traitee_par = auth.jwt() ->> 'email'
   WHERE user_id = p_user AND statut = 'nouvelle';
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_compter_alertes()
RETURNS TABLE (mineur bigint, danger bigint)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT count(*) FILTER (WHERE a.categorie = 'mineur'),
           count(*) FILTER (WHERE a.categorie = 'danger')
      FROM alertes_securite a WHERE a.statut = 'nouvelle';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_alertes(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_alerte_suite(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_traiter_alerte(uuid, text) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_traiter_alertes_user(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_compter_alertes() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_alertes(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_alerte_suite(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_traiter_alerte(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_traiter_alertes_user(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_compter_alertes() TO authenticated;

-- Temps réel : le panneau est prévenu à chaque nouvelle alerte
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                  WHERE pubname = 'supabase_realtime'
                    AND schemaname = 'public' AND tablename = 'alertes_securite') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.alertes_securite;
  END IF;
END $$;

-- Conservation : 12 mois au plus (politique de confidentialité),
-- purge chaque dimanche à 4 h
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purger-alertes-securite') THEN
    PERFORM cron.unschedule('purger-alertes-securite');
  END IF;
END $$;
SELECT cron.schedule('purger-alertes-securite', '0 4 * * 0',
  $$DELETE FROM public.alertes_securite WHERE created_at < now() - interval '12 months'$$);

COMMIT;

-- Pour tester la détection sans rien créer :
--   SELECT * FROM public._detecter_risque('slt moi j''ai 16 ans et toi');
--   SELECT * FROM public._detecter_risque('je vais te tuer');
