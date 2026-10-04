-- ═══════════════════════════════════════════════════════════════════
-- Discussions de groupe — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 035. Ré-exécutable.
--
-- • groupes : créés par les utilisateurs (50 membres max) ou
--   automatiquement pour chaque événement publié (sans limite : tous
--   ceux qui disent « J'y vais » / « Intéressé » y entrent).
-- • groupe_membres : rôle admin / membre, dernier message lu, sourdine.
-- • groupe_messages : texte, photo (bucket privé « groupes »), GIF /
--   sticker GIPHY, messages système (« X a rejoint le groupe »).
--   Gardés 7 jours ; groupe d'événement : supprimé 3 jours après la fin.
-- • Notification push à chaque message (edge function groupe-message),
--   au plus une toutes les 5 minutes par personne et par groupe.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Tables ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.groupes (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nom               text NOT NULL CHECK (char_length(btrim(nom)) BETWEEN 1 AND 60),
  description       text CHECK (description IS NULL OR char_length(description) <= 300),
  photo_url         text CHECK (photo_url IS NULL OR photo_url ~ '^https://'),
  createur_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  evenement_id      uuid UNIQUE REFERENCES public.evenements(id) ON DELETE CASCADE,
  created_at        timestamptz NOT NULL DEFAULT now(),
  derniere_activite timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.groupe_membres (
  groupe_id   uuid NOT NULL REFERENCES public.groupes(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'membre' CHECK (role IN ('admin', 'membre')),
  rejoint_le  timestamptz NOT NULL DEFAULT now(),
  dernier_lu  timestamptz NOT NULL DEFAULT now(),
  sourdine    boolean NOT NULL DEFAULT false,
  notifie_le  timestamptz,
  PRIMARY KEY (groupe_id, user_id)
);
CREATE INDEX IF NOT EXISTS groupe_membres_user_idx ON public.groupe_membres (user_id);

CREATE TABLE IF NOT EXISTS public.groupe_messages (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  groupe_id  uuid NOT NULL REFERENCES public.groupes(id) ON DELETE CASCADE,
  sender_id  uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  type       text NOT NULL DEFAULT 'texte'
             CHECK (type IN ('texte', 'image', 'giphy', 'systeme')),
  contenu    text CHECK (contenu IS NULL OR char_length(contenu) <= 2000),
  media_path text,   -- photo : chemin dans le bucket privé « groupes »
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (type <> 'giphy' OR contenu ~ '^https://media[0-9]*\.giphy\.com/'),
  CHECK (type <> 'texte' OR char_length(btrim(COALESCE(contenu, ''))) >= 1),
  CHECK (type <> 'image' OR media_path IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS groupe_messages_groupe_idx
  ON public.groupe_messages (groupe_id, created_at DESC);

-- ── 2. Fonctions d'aide ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.est_membre_groupe(p_groupe uuid, p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM groupe_membres
                 WHERE groupe_id = p_groupe AND user_id = p_user);
$$;
REVOKE ALL ON FUNCTION public.est_membre_groupe(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.est_membre_groupe(uuid, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.est_admin_groupe(p_groupe uuid, p_user uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM groupe_membres
                 WHERE groupe_id = p_groupe AND user_id = p_user
                   AND role = 'admin');
$$;
REVOKE ALL ON FUNCTION public.est_admin_groupe(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.est_admin_groupe(uuid, uuid) TO authenticated;

-- Message système (« X a rejoint le groupe ») : sans notification
CREATE OR REPLACE FUNCTION public._message_systeme(p_groupe uuid, p_texte text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  INSERT INTO groupe_messages (groupe_id, sender_id, type, contenu)
  VALUES (p_groupe, NULL, 'systeme', left(p_texte, 2000));
$$;
REVOKE ALL ON FUNCTION public._message_systeme(uuid, text) FROM public, anon, authenticated;

-- ── 3. Règles d'accès ──────────────────────────────────────────────
ALTER TABLE public.groupes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groupe_membres ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groupe_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS groupes_select ON public.groupes;
CREATE POLICY groupes_select ON public.groupes FOR SELECT TO authenticated
  USING (public.est_membre_groupe(id, auth.uid()) OR public.is_admin());

-- Les groupes se créent par creer_groupe() ; seuls les admins du groupe
-- modifient le nom, la photo, la description (pas un groupe d'événement)
DROP POLICY IF EXISTS groupes_update ON public.groupes;
CREATE POLICY groupes_update ON public.groupes FOR UPDATE TO authenticated
  USING (public.est_admin_groupe(id, auth.uid()) AND evenement_id IS NULL)
  WITH CHECK (public.est_admin_groupe(id, auth.uid()) AND evenement_id IS NULL);

DROP POLICY IF EXISTS groupes_admin ON public.groupes;
CREATE POLICY groupes_admin ON public.groupes FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS groupe_membres_select ON public.groupe_membres;
CREATE POLICY groupe_membres_select ON public.groupe_membres FOR SELECT TO authenticated
  USING (public.est_membre_groupe(groupe_id, auth.uid()) OR public.is_admin());

-- Ma ligne : dernier lu, sourdine (le rôle est protégé par un trigger)
DROP POLICY IF EXISTS groupe_membres_update ON public.groupe_membres;
CREATE POLICY groupe_membres_update ON public.groupe_membres FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- Quitter le groupe, ou un admin retire quelqu'un (groupe d'amis)
DROP POLICY IF EXISTS groupe_membres_delete ON public.groupe_membres;
CREATE POLICY groupe_membres_delete ON public.groupe_membres FOR DELETE TO authenticated
  USING (user_id = auth.uid()
         OR (public.est_admin_groupe(groupe_id, auth.uid())
             AND NOT EXISTS (SELECT 1 FROM groupes g
                             WHERE g.id = groupe_id AND g.evenement_id IS NOT NULL)));

DROP POLICY IF EXISTS groupe_messages_select ON public.groupe_messages;
CREATE POLICY groupe_messages_select ON public.groupe_messages FOR SELECT TO authenticated
  USING (public.est_membre_groupe(groupe_id, auth.uid()) OR public.is_admin());

DROP POLICY IF EXISTS groupe_messages_insert ON public.groupe_messages;
CREATE POLICY groupe_messages_insert ON public.groupe_messages FOR INSERT TO authenticated
  WITH CHECK (sender_id = auth.uid() AND type <> 'systeme'
              AND public.est_membre_groupe(groupe_id, auth.uid()));

-- Supprimer son message (ou un admin du groupe / de Zamu)
DROP POLICY IF EXISTS groupe_messages_delete ON public.groupe_messages;
CREATE POLICY groupe_messages_delete ON public.groupe_messages FOR DELETE TO authenticated
  USING (sender_id = auth.uid() OR public.est_admin_groupe(groupe_id, auth.uid())
         OR public.is_admin());

-- Le rôle ne se change pas soi-même (seulement via promouvoir_membre)
CREATE OR REPLACE FUNCTION public.proteger_role_groupe()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role
     AND COALESCE(current_setting('zamu.groupe_role', true), '') <> 'oui' THEN
    NEW.role := OLD.role;
  END IF;
  NEW.notifie_le := CASE
    WHEN COALESCE(current_setting('zamu.groupe_role', true), '') = 'oui'
    THEN NEW.notifie_le ELSE OLD.notifie_le END;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_proteger_role_groupe ON public.groupe_membres;
CREATE TRIGGER trg_proteger_role_groupe
  BEFORE UPDATE ON public.groupe_membres
  FOR EACH ROW EXECUTE FUNCTION public.proteger_role_groupe();

-- Le dernier admin d'un groupe d'amis s'en va : le plus ancien membre
-- devient admin (le groupe n'est jamais bloqué) ; groupe vide supprimé.
CREATE OR REPLACE FUNCTION public.apres_depart_groupe()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  nom_parti text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM groupes WHERE id = OLD.groupe_id) THEN
    RETURN NULL; -- groupe supprimé (cascade)
  END IF;
  IF NOT EXISTS (SELECT 1 FROM groupe_membres WHERE groupe_id = OLD.groupe_id) THEN
    DELETE FROM groupes WHERE id = OLD.groupe_id AND evenement_id IS NULL;
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM groupes WHERE id = OLD.groupe_id AND evenement_id IS NULL) THEN
    SELECT name INTO nom_parti FROM profiles WHERE id = OLD.user_id;
    PERFORM public._message_systeme(OLD.groupe_id,
      COALESCE(nom_parti, 'Quelqu''un') || ' a quitté le groupe');
    IF NOT EXISTS (SELECT 1 FROM groupe_membres
                   WHERE groupe_id = OLD.groupe_id AND role = 'admin') THEN
      PERFORM set_config('zamu.groupe_role', 'oui', true);
      UPDATE groupe_membres SET role = 'admin'
      WHERE groupe_id = OLD.groupe_id
        AND user_id = (SELECT user_id FROM groupe_membres
                       WHERE groupe_id = OLD.groupe_id
                       ORDER BY rejoint_le LIMIT 1);
      PERFORM set_config('zamu.groupe_role', '', true);
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_apres_depart_groupe ON public.groupe_membres;
CREATE TRIGGER trg_apres_depart_groupe
  AFTER DELETE ON public.groupe_membres
  FOR EACH ROW EXECUTE FUNCTION public.apres_depart_groupe();

-- ── 4. Actions (RPC) ───────────────────────────────────────────────
-- Créer un groupe d'amis : moi (admin) + les membres choisis (49 max)
CREATE OR REPLACE FUNCTION public.creer_groupe(p_nom text, p_membres uuid[])
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  g uuid;
  nom_moi text;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'non_connecte'; END IF;
  IF char_length(btrim(COALESCE(p_nom, ''))) < 1 THEN
    RAISE EXCEPTION 'nom_vide' USING ERRCODE = 'P0001';
  END IF;
  IF COALESCE(array_length(p_membres, 1), 0) > 49 THEN
    RAISE EXCEPTION 'trop_de_membres' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO groupes (nom, createur_id) VALUES (left(btrim(p_nom), 60), auth.uid())
  RETURNING id INTO g;
  INSERT INTO groupe_membres (groupe_id, user_id, role) VALUES (g, auth.uid(), 'admin');
  INSERT INTO groupe_membres (groupe_id, user_id)
  SELECT g, m FROM unnest(p_membres) AS m
  JOIN profiles pr ON pr.id = m
  WHERE m <> auth.uid()
    AND NOT COALESCE(pr.is_suspended, false)
    AND NOT public.blocage_entre(m, auth.uid())
  ON CONFLICT DO NOTHING;
  SELECT name INTO nom_moi FROM profiles WHERE id = auth.uid();
  PERFORM public._message_systeme(g, COALESCE(nom_moi, 'Quelqu''un') || ' a créé le groupe');
  RETURN g;
END;
$$;
REVOKE ALL ON FUNCTION public.creer_groupe(text, uuid[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.creer_groupe(text, uuid[]) TO authenticated;

-- Ajouter des membres (admin d'un groupe d'amis, 50 au total)
CREATE OR REPLACE FUNCTION public.ajouter_membres_groupe(p_groupe uuid, p_membres uuid[])
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  n int;
  places int;
BEGIN
  IF NOT public.est_admin_groupe(p_groupe, auth.uid()) THEN
    RAISE EXCEPTION 'pas_admin' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM groupes WHERE id = p_groupe AND evenement_id IS NOT NULL) THEN
    RAISE EXCEPTION 'groupe_evenement' USING ERRCODE = 'P0001';
  END IF;
  SELECT 50 - count(*) INTO places FROM groupe_membres WHERE groupe_id = p_groupe;
  WITH ajout AS (
    INSERT INTO groupe_membres (groupe_id, user_id)
    SELECT p_groupe, m FROM (
      SELECT DISTINCT m FROM unnest(p_membres) AS m
      JOIN profiles pr ON pr.id = m
      WHERE NOT COALESCE(pr.is_suspended, false)
        AND NOT public.blocage_entre(m, auth.uid())
        AND NOT public.est_membre_groupe(p_groupe, m)
      LIMIT GREATEST(places, 0)) x
    ON CONFLICT DO NOTHING
    RETURNING user_id)
  SELECT count(*) INTO n FROM ajout;
  IF n > 0 THEN
    PERFORM public._message_systeme(p_groupe,
      n || CASE WHEN n > 1 THEN ' personnes ont été ajoutées'
                ELSE ' personne a été ajoutée' END);
  END IF;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.ajouter_membres_groupe(uuid, uuid[]) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.ajouter_membres_groupe(uuid, uuid[]) TO authenticated;

-- Nommer un autre admin
CREATE OR REPLACE FUNCTION public.promouvoir_membre_groupe(p_groupe uuid, p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.est_admin_groupe(p_groupe, auth.uid()) THEN
    RAISE EXCEPTION 'pas_admin' USING ERRCODE = 'P0001';
  END IF;
  PERFORM set_config('zamu.groupe_role', 'oui', true);
  UPDATE groupe_membres SET role = 'admin'
  WHERE groupe_id = p_groupe AND user_id = p_user;
  PERFORM set_config('zamu.groupe_role', '', true);
END;
$$;
REVOKE ALL ON FUNCTION public.promouvoir_membre_groupe(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.promouvoir_membre_groupe(uuid, uuid) TO authenticated;

-- Mes groupes : dernier message, non lus, sourdine
DROP FUNCTION IF EXISTS public.mes_groupes();
CREATE FUNCTION public.mes_groupes()
RETURNS TABLE (id uuid, nom text, photo_url text, evenement_id uuid,
               nb_membres int, mon_role text, sourdine boolean,
               dernier_type text, dernier_contenu text, dernier_auteur text,
               derniere_activite timestamptz, non_lus int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT g.id, g.nom, g.photo_url, g.evenement_id,
         (SELECT count(*)::int FROM groupe_membres x WHERE x.groupe_id = g.id),
         m.role, m.sourdine,
         dm.type, dm.contenu, pr.name::text,
         g.derniere_activite,
         (SELECT count(*)::int FROM groupe_messages gm
           WHERE gm.groupe_id = g.id AND gm.created_at > m.dernier_lu
             AND gm.sender_id IS DISTINCT FROM auth.uid()
             AND gm.type <> 'systeme')
  FROM groupe_membres m
  JOIN groupes g ON g.id = m.groupe_id
  LEFT JOIN LATERAL (SELECT * FROM groupe_messages gm
                     WHERE gm.groupe_id = g.id
                     ORDER BY gm.created_at DESC LIMIT 1) dm ON true
  LEFT JOIN profiles pr ON pr.id = dm.sender_id
  WHERE m.user_id = auth.uid()
  ORDER BY g.derniere_activite DESC;
$$;
REVOKE ALL ON FUNCTION public.mes_groupes() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mes_groupes() TO authenticated;

-- ── 5. Activité du groupe + notification push ──────────────────────
CREATE OR REPLACE FUNCTION public.apres_message_groupe()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  cle text;
BEGIN
  UPDATE groupes SET derniere_activite = NEW.created_at WHERE id = NEW.groupe_id;
  -- L'auteur a « lu » jusqu'à son propre message
  IF NEW.sender_id IS NOT NULL THEN
    UPDATE groupe_membres SET dernier_lu = NEW.created_at
    WHERE groupe_id = NEW.groupe_id AND user_id = NEW.sender_id;
  END IF;
  IF NEW.type = 'systeme' THEN RETURN NULL; END IF;

  SELECT decrypted_secret INTO cle
  FROM vault.decrypted_secrets WHERE name = 'notif_secret' LIMIT 1;
  IF cle IS NULL THEN RETURN NULL; END IF;
  PERFORM net.http_post(
    url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/groupe-message',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cle,
      'apikey', cle),
    body := jsonb_build_object('message_id', NEW.id)
  );
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- Une notification ratée ne bloque jamais l'envoi du message
  RAISE WARNING 'apres_message_groupe : %', SQLERRM;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_apres_message_groupe ON public.groupe_messages;
CREATE TRIGGER trg_apres_message_groupe
  AFTER INSERT ON public.groupe_messages
  FOR EACH ROW EXECUTE FUNCTION public.apres_message_groupe();

-- Destinataires d'une notification (appelé par l'edge function) : tous
-- les membres sauf l'auteur, en sourdine, suspendus, bloqués, et ceux
-- déjà prévenus il y a moins de 5 minutes pour ce groupe.
CREATE OR REPLACE FUNCTION public.destinataires_message_groupe(p_message uuid)
RETURNS TABLE (user_id uuid, fcm_token text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  msg groupe_messages;
BEGIN
  SELECT * INTO msg FROM groupe_messages WHERE id = p_message;
  IF NOT FOUND THEN RETURN; END IF;
  PERFORM set_config('zamu.groupe_role', 'oui', true);
  RETURN QUERY
  WITH maj AS (
  UPDATE groupe_membres gm SET notifie_le = now()
  FROM profiles pr
  WHERE gm.groupe_id = msg.groupe_id
    AND pr.id = gm.user_id
    AND gm.user_id IS DISTINCT FROM msg.sender_id
    AND NOT gm.sourdine
    AND (gm.notifie_le IS NULL OR gm.notifie_le < now() - interval '5 minutes')
    AND COALESCE(pr.fcm_token, '') <> ''
    AND NOT COALESCE(pr.is_suspended, false)
    AND COALESCE(pr.notif_messages, true)
    AND (msg.sender_id IS NULL OR NOT public.blocage_entre(gm.user_id, msg.sender_id))
  RETURNING gm.user_id AS uid, pr.fcm_token::text AS jeton)
  SELECT maj.uid, maj.jeton FROM maj;
  PERFORM set_config('zamu.groupe_role', '', true);
END;
$$;
REVOKE ALL ON FUNCTION public.destinataires_message_groupe(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.destinataires_message_groupe(uuid) TO service_role;

-- ── 6. Groupe automatique de chaque événement ──────────────────────
CREATE OR REPLACE FUNCTION public.groupe_de_evenement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.statut = 'publie' THEN
    INSERT INTO groupes (nom, photo_url, evenement_id)
    VALUES (left(NEW.titre, 60), NEW.image_url, NEW.id)
    ON CONFLICT (evenement_id)
    DO UPDATE SET nom = EXCLUDED.nom, photo_url = EXCLUDED.photo_url;
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_groupe_de_evenement ON public.evenements;
CREATE TRIGGER trg_groupe_de_evenement
  AFTER INSERT OR UPDATE OF statut, titre, image_url ON public.evenements
  FOR EACH ROW EXECUTE FUNCTION public.groupe_de_evenement();

-- Participer = entrer dans le groupe ; ne plus participer = en sortir
CREATE OR REPLACE FUNCTION public.participant_groupe_evenement()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  g uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM groupe_membres m USING groupes gr
    WHERE gr.evenement_id = OLD.evenement_id AND m.groupe_id = gr.id
      AND m.user_id = OLD.user_id;
    RETURN NULL;
  END IF;
  SELECT id INTO g FROM groupes WHERE evenement_id = NEW.evenement_id;
  IF g IS NULL THEN RETURN NULL; END IF;
  INSERT INTO groupe_membres (groupe_id, user_id) VALUES (g, NEW.user_id)
  ON CONFLICT DO NOTHING;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_participant_groupe_evenement ON public.evenement_participants;
CREATE TRIGGER trg_participant_groupe_evenement
  AFTER INSERT OR DELETE ON public.evenement_participants
  FOR EACH ROW EXECUTE FUNCTION public.participant_groupe_evenement();

-- Rattrapage : événements déjà publiés et leurs participants
INSERT INTO public.groupes (nom, photo_url, evenement_id)
SELECT left(e.titre, 60), e.image_url, e.id FROM public.evenements e
WHERE e.statut = 'publie'
ON CONFLICT (evenement_id) DO NOTHING;
INSERT INTO public.groupe_membres (groupe_id, user_id)
SELECT g.id, p.user_id
FROM public.evenement_participants p
JOIN public.groupes g ON g.evenement_id = p.evenement_id
ON CONFLICT DO NOTHING;

-- Id du groupe d'un événement (si j'en fais partie)
CREATE OR REPLACE FUNCTION public.groupe_evenement(p_ev uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT g.id FROM groupes g
  WHERE g.evenement_id = p_ev AND public.est_membre_groupe(g.id, auth.uid());
$$;
REVOKE ALL ON FUNCTION public.groupe_evenement(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.groupe_evenement(uuid) TO authenticated;

-- ── 7. Photos (bucket privé : dossier = id du groupe) ───────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('groupes', 'groupes', false, 10485760,
        ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET public = false;

DROP POLICY IF EXISTS groupes_photos_lecture ON storage.objects;
CREATE POLICY groupes_photos_lecture ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'groupes'
         AND public.est_membre_groupe(((storage.foldername(name))[1])::uuid, auth.uid()));

DROP POLICY IF EXISTS groupes_photos_envoi ON storage.objects;
CREATE POLICY groupes_photos_envoi ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'groupes'
              AND public.est_membre_groupe(((storage.foldername(name))[1])::uuid, auth.uid()));

-- ── 8. Nettoyage : messages > 7 jours, groupes d'événement finis ────
CREATE OR REPLACE FUNCTION public.purger_groupes()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Fichiers des photos supprimées : file d'attente de purge-expired
  INSERT INTO storage_a_supprimer (bucket, path)
  SELECT 'groupes', m.media_path FROM groupe_messages m
  WHERE m.media_path IS NOT NULL AND m.created_at < now() - interval '7 days'
  ON CONFLICT DO NOTHING;
  DELETE FROM groupe_messages WHERE created_at < now() - interval '7 days';

  INSERT INTO storage_a_supprimer (bucket, path)
  SELECT 'groupes', m.media_path FROM groupe_messages m
  JOIN groupes g ON g.id = m.groupe_id
  JOIN evenements e ON e.id = g.evenement_id
  WHERE m.media_path IS NOT NULL
    AND public.fin_evenement(e) < now() - interval '3 days'
  ON CONFLICT DO NOTHING;
  DELETE FROM groupes g USING evenements e
  WHERE e.id = g.evenement_id
    AND public.fin_evenement(e) < now() - interval '3 days';
END;
$$;
REVOKE ALL ON FUNCTION public.purger_groupes() FROM public, anon, authenticated;

COMMIT;

-- Tous les jours à 3 h
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purger-groupes') THEN
    PERFORM cron.unschedule('purger-groupes');
  END IF;
END $$;
SELECT cron.schedule('purger-groupes', '0 3 * * *', 'SELECT public.purger_groupes()');

-- Temps réel : nouveaux messages et membres
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.groupe_messages;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.groupe_membres;
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;
END $$;

NOTIFY pgrst, 'reload schema';
