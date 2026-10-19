-- ═══════════════════════════════════════════════════════════════════
-- ⚡ Liste des conversations en UNE requête — 2026-10-19 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Avant : l'app faisait 2 requêtes PAR conversation (dernier message +
-- nombre de non-lus), soit ~100 requêtes pour 50 conversations, répétées
-- toutes les 2 min. Ici tout est calculé par le serveur en un seul appel,
-- avec le même format qu'avant. Les personnes bloquées (dans un sens ou
-- dans l'autre) sont exclues. Les anciennes versions de l'app ne
-- l'appellent pas ; la nouvelle revient à l'ancienne méthode si la
-- fonction n'existe pas encore.
-- ═══════════════════════════════════════════════════════════════════

-- Dernier message d'une conversation : lecture directe par l'index
CREATE INDEX IF NOT EXISTS messages_conversation_date_idx
  ON public.messages (conversation_id, created_at DESC);

-- Non-lus : seuls les messages pas encore lus sont indexés (petit index)
CREATE INDEX IF NOT EXISTS messages_non_lus_idx
  ON public.messages (conversation_id, sender_id)
  WHERE is_read = false;

CREATE OR REPLACE FUNCTION public.liste_conversations()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'updated_at', c.updated_at,
      'user1_id', c.user1_id,
      'user2_id', c.user2_id,
      'request_status', c.request_status,
      'initiated_by', c.initiated_by,
      'flamme_compte', c.flamme_compte,
      'flamme_dernier_jour', c.flamme_dernier_jour,
      'user1_profile', (
        SELECT jsonb_build_object('id', p.id, 'name', p.name,
          'photo_url', p.photo_url, 'is_online', p.is_online,
          'last_seen', p.last_seen)
        FROM profiles p WHERE p.id = c.user1_id),
      'user2_profile', (
        SELECT jsonb_build_object('id', p.id, 'name', p.name,
          'photo_url', p.photo_url, 'is_online', p.is_online,
          'last_seen', p.last_seen)
        FROM profiles p WHERE p.id = c.user2_id),
      -- Dernier message encore visible (ni disparu, ni lu depuis > 24 h)
      '_last_message', (
        SELECT jsonb_build_object('id', m.id,
          'conversation_id', m.conversation_id, 'type', m.type,
          'content', m.content, 'sender_id', m.sender_id,
          'created_at', m.created_at, 'status', m.status,
          'is_read', m.is_read, 'is_opened', m.is_opened,
          'audio_duration', m.audio_duration)
        FROM messages m
        WHERE m.conversation_id = c.id
          AND (m.disappears_at IS NULL OR m.disappears_at > now())
          AND (m.read_at IS NULL OR m.read_at > now() - interval '24 hours')
        ORDER BY m.created_at DESC
        LIMIT 1),
      '_unread_count', (
        SELECT count(*)
        FROM messages m
        WHERE m.conversation_id = c.id
          AND m.sender_id <> auth.uid()
          AND m.is_read = false
          AND m.status <> 'read')
    ) ORDER BY c.updated_at DESC NULLS LAST), '[]'::jsonb)
  FROM conversations c
  WHERE (c.user1_id = auth.uid() OR c.user2_id = auth.uid())
    AND NOT blocage_entre(c.user1_id, c.user2_id);
$$;

REVOKE ALL ON FUNCTION public.liste_conversations() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.liste_conversations() TO authenticated;

NOTIFY pgrst, 'reload schema';
