-- ═══════════════════════════════════════════════════════════════════
-- Messages directs sans match — 2026-09-29
-- • Tout le monde peut écrire à tout le monde ; la conversation apparaît
--   directement chez les deux personnes (l'app ne cache plus les
--   conversations « pending »).
-- • Anti-spam : tant que le destinataire n'a pas répondu (et sans match),
--   l'initiateur peut envoyer au maximum 3 messages.
-- • Blocage efficace : impossible de créer une conversation ou d'envoyer
--   un message si l'un des deux a bloqué l'autre (donc plus de
--   notification non plus : le push part après l'insertion du message).
-- Le serveur décide du statut, quel que soit l'écran qui crée la
-- conversation. Ré-exécutable sans risque.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Vrai si a a bloqué b ou b a bloqué a (type de blocked_users indifférent)
CREATE OR REPLACE FUNCTION public.blocage_entre(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles p
    WHERE (p.id = a AND b::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
       OR (p.id = b AND a::text = ANY (COALESCE(p.blocked_users::text[], '{}')))
  );
$$;
REVOKE ALL ON FUNCTION public.blocage_entre(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.blocage_entre(uuid, uuid) TO authenticated;

-- Vrai si les deux personnes ont un match (like réciproque)
CREATE OR REPLACE FUNCTION public.ont_un_match(a uuid, b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM matches m
                 WHERE m.user1_id = LEAST(a, b) AND m.user2_id = GREATEST(a, b))
      OR (EXISTS (SELECT 1 FROM likes WHERE from_user_id = a AND to_user_id = b)
          AND EXISTS (SELECT 1 FROM likes WHERE from_user_id = b AND to_user_id = a));
$$;
REVOKE ALL ON FUNCTION public.ont_un_match(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.ont_un_match(uuid, uuid) TO authenticated;

-- ───────────────────────────────────────────────────────────────────
-- 1. Création de conversation : statut décidé par le serveur
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.controle_nouvelle_conversation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF public.blocage_entre(NEW.user1_id, NEW.user2_id) THEN
    RAISE EXCEPTION 'bloque' USING ERRCODE = '42501',
      HINT = 'Une des deux personnes a bloqué l''autre';
  END IF;

  NEW.initiated_by := auth.uid();
  NEW.request_status := CASE
    WHEN public.ont_un_match(NEW.user1_id, NEW.user2_id) THEN 'accepted'
    ELSE 'pending'
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_controle_nouvelle_conversation ON public.conversations;
CREATE TRIGGER trg_controle_nouvelle_conversation
  BEFORE INSERT ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.controle_nouvelle_conversation();

-- L'initiateur ne peut pas passer lui-même sa conversation en « acceptée »
-- (sinon il contournerait la limite). Le passage se fait automatiquement
-- quand l'autre répond (section 2).
CREATE OR REPLACE FUNCTION public.protege_statut_conversation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user IN ('authenticated', 'anon')
     AND NEW.request_status IS DISTINCT FROM OLD.request_status
     AND auth.uid() IS NOT DISTINCT FROM OLD.initiated_by THEN
    NEW.request_status := OLD.request_status;
  END IF;
  IF current_user IN ('authenticated', 'anon') THEN
    NEW.initiated_by := OLD.initiated_by;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protege_statut_conversation ON public.conversations;
CREATE TRIGGER trg_protege_statut_conversation
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.protege_statut_conversation();

-- ───────────────────────────────────────────────────────────────────
-- 2. Envoi de message : blocage + limite de 3 sans réponse
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.controle_envoi_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c conversations%ROWTYPE;
  destinataire uuid;
  deja_envoyes integer;
BEGIN
  -- SECURITY DEFINER : current_user = propriétaire ; on teste le rôle
  -- de l'appelant via le JWT.
  IF COALESCE(auth.role(), '') NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  SELECT * INTO c FROM conversations WHERE id = NEW.conversation_id;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;
  destinataire := CASE WHEN c.user1_id = NEW.sender_id THEN c.user2_id ELSE c.user1_id END;

  IF public.blocage_entre(NEW.sender_id, destinataire) THEN
    RAISE EXCEPTION 'bloque' USING ERRCODE = '42501',
      HINT = 'Une des deux personnes a bloqué l''autre';
  END IF;

  IF c.request_status = 'pending' THEN
    IF NEW.sender_id IS DISTINCT FROM c.initiated_by THEN
      -- Le destinataire répond : la conversation devient normale
      UPDATE conversations SET request_status = 'accepted' WHERE id = c.id;
    ELSIF NOT public.ont_un_match(c.user1_id, c.user2_id) THEN
      SELECT count(*) INTO deja_envoyes
      FROM messages
      WHERE conversation_id = c.id AND sender_id = NEW.sender_id;
      IF deja_envoyes >= 3 THEN
        RAISE EXCEPTION 'limite_sans_reponse' USING ERRCODE = 'P0001',
          HINT = 'Attends sa réponse pour envoyer d''autres messages';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_controle_envoi_message ON public.messages;
CREATE TRIGGER trg_controle_envoi_message
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.controle_envoi_message();

-- Conversations existantes : celles où le destinataire a déjà répondu,
-- ou avec un match, deviennent normales.
UPDATE public.conversations c
SET request_status = 'accepted'
WHERE c.request_status = 'pending'
  AND (
    public.ont_un_match(c.user1_id, c.user2_id)
    OR EXISTS (SELECT 1 FROM public.messages m
               WHERE m.conversation_id = c.id
                 AND m.sender_id IS DISTINCT FROM c.initiated_by)
  );

COMMIT;
