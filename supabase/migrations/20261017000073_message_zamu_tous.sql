-- ═══════════════════════════════════════════════════════════════════
-- Message de « Zamu » à tous les inscrits — 2026-10-17
-- À exécuter dans Supabase → SQL Editor APRÈS le script 072.
-- Ré-exécutable sans risque.
--
-- Panneau admin → « Messages Zamu » → « Écrire à tout le monde » :
-- le message arrive dans la conversation Zamu de chaque inscrit (créée si
-- besoin), avec la notification push habituelle d'un message.
-- {prenom} est remplacé par le prénom de chaque personne.
-- Exclus : comptes suspendus, inscriptions pas terminées, personnes qui
-- ont bloqué Zamu.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Nombre de personnes qui recevront le message (affiché avant l'envoi)
CREATE OR REPLACE FUNCTION public.admin_compter_destinataires_zamu()
RETURNS int
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_off uuid;
BEGIN
  PERFORM public._exiger_admin();
  SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN RETURN 0; END IF;
  RETURN (SELECT count(*)::int FROM profiles p
           WHERE p.id <> v_off
             AND COALESCE(p.onboarding_complete, false)
             AND NOT COALESCE(p.is_suspended, false)
             AND NOT COALESCE(p.est_officiel, false)
             AND NOT public.blocage_entre(p.id, v_off));
END;
$$;

-- Envoi. p_test = true : seulement à l'admin connecté (pour vérifier le
-- rendu dans l'app avant d'envoyer à tout le monde).
CREATE OR REPLACE FUNCTION public.admin_message_zamu_tous(p_texte text, p_test boolean DEFAULT true)
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_off   uuid;
  v_conv  uuid;
  v_txt   text := left(btrim(COALESCE(p_texte, '')), 2000);
  v_n     int := 0;
  r       record;
BEGIN
  PERFORM public._exiger_admin();
  IF v_txt = '' THEN RAISE EXCEPTION 'texte_vide' USING ERRCODE = 'P0001'; END IF;
  SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
  IF v_off IS NULL THEN
    RAISE EXCEPTION 'compte_zamu_absent' USING ERRCODE = 'P0001',
      HINT = 'Exécute d''abord le script 072 (profil officiel « Zamu »)';
  END IF;

  FOR r IN
    SELECT p.id, p.name FROM profiles p
     WHERE p.id <> v_off
       AND COALESCE(p.onboarding_complete, false)
       AND NOT COALESCE(p.is_suspended, false)
       AND NOT COALESCE(p.est_officiel, false)
       AND NOT public.blocage_entre(p.id, v_off)
       AND (NOT p_test OR p.id = auth.uid())
  LOOP
    BEGIN
      SELECT c.id INTO v_conv FROM conversations c
       WHERE (c.user1_id = v_off AND c.user2_id = r.id)
          OR (c.user1_id = r.id AND c.user2_id = v_off)
       ORDER BY c.created_at LIMIT 1;
      IF v_conv IS NULL THEN
        INSERT INTO conversations (user1_id, user2_id, request_status, initiated_by)
        VALUES (v_off, r.id, 'accepted', v_off)
        RETURNING id INTO v_conv;
      END IF;
      INSERT INTO messages (conversation_id, sender_id, type, content, status)
      VALUES (v_conv, v_off, 'text',
              replace(v_txt, '{prenom}', COALESCE(NULLIF(btrim(r.name), ''), '')),
              'sent');
      UPDATE conversations SET updated_at = now() WHERE id = v_conv;
      v_n := v_n + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;   -- une personne en erreur ne bloque pas les autres
    END;
    v_conv := NULL;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_compter_destinataires_zamu() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_message_zamu_tous(text, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_compter_destinataires_zamu() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_message_zamu_tous(text, boolean) TO authenticated;

COMMIT;
