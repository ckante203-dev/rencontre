-- ═══════════════════════════════════════════════════════════════════
-- Cloche 🔔 : toute l'activité — 2026-10-04
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- Avant : la cloche ne montrait que les likes de story (like_story) et les
-- nouvelles stories des ABONNÉS (new_story, via follows) — les abonnements
-- ont été retirés de l'app, plus rien n'arrivait depuis le 1er octobre.
--
-- Désormais (table notifications, lue par l'écran « Notifications ») :
--   like          ❤️ quelqu'un m'a liké (anonyme dans l'app pour un gratuit)
--   match         💘 nouveau match (les deux personnes)
--   favori_story  ⭐ un de mes favoris a publié une story (visible)
--   album         🔓 quelqu'un m'a ouvert son album privé
--   like_story    ❤️ like de story (inchangé)
-- Pas d'entrée en cas de blocage. Chaque ajout est protégé : une erreur
-- ici ne bloque jamais le like / match / story lui-même.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Ajout dans la cloche (anti-doublon : même type + même auteur < délai)
CREATE OR REPLACE FUNCTION public._cloche(
  p_user uuid, p_acteur uuid, p_type text, p_ref text, p_delai interval)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_user IS NULL OR p_user = p_acteur
     OR public.blocage_entre(p_user, p_acteur) THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM notifications
             WHERE user_id = p_user AND actor_id = p_acteur
               AND type = p_type AND created_at > now() - p_delai) THEN
    RETURN;
  END IF;
  INSERT INTO notifications (user_id, actor_id, type, reference_id)
  VALUES (p_user, p_acteur, p_type, p_ref);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'cloche % : %', p_type, SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public._cloche(uuid, uuid, text, text, interval)
  FROM public, anon, authenticated;

-- ── Like de profil ──
CREATE OR REPLACE FUNCTION public.cloche_like()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._cloche(NEW.to_user_id, NEW.from_user_id, 'like', NULL,
                         interval '1 day');
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cloche_like ON public.likes;
CREATE TRIGGER trg_cloche_like
  AFTER INSERT ON public.likes
  FOR EACH ROW EXECUTE FUNCTION public.cloche_like();

-- ── Match (les deux personnes) ──
CREATE OR REPLACE FUNCTION public.cloche_match()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._cloche(NEW.user1_id, NEW.user2_id, 'match', NULL, interval '1 day');
  PERFORM public._cloche(NEW.user2_id, NEW.user1_id, 'match', NULL, interval '1 day');
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cloche_match ON public.matches;
CREATE TRIGGER trg_cloche_match
  AFTER INSERT ON public.matches
  FOR EACH ROW EXECUTE FUNCTION public.cloche_match();

-- ── Album privé ouvert ──
CREATE OR REPLACE FUNCTION public.cloche_album()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._cloche(NEW.viewer_id, NEW.owner_id, 'album', NULL, interval '1 day');
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cloche_album ON public.album_acces;
CREATE TRIGGER trg_cloche_album
  AFTER INSERT ON public.album_acces
  FOR EACH ROW EXECUTE FUNCTION public.cloche_album();

-- ── Story d'un favori ⭐ (même règle de visibilité que l'alerte push) ──
CREATE OR REPLACE FUNCTION public.cloche_story_favori()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  n jsonb := to_jsonb(NEW);
  o jsonb;
  visible boolean;
  visible_avant boolean := false;
  f record;
BEGIN
  visible := COALESCE(n->>'visibility', 'public') = 'public'
    AND (n->>'moderation_status' IS NULL
         OR n->>'moderation_status' IN ('approved', 'unchecked'));
  IF TG_OP = 'UPDATE' THEN
    o := to_jsonb(OLD);
    visible_avant := COALESCE(o->>'visibility', 'public') = 'public'
      AND (o->>'moderation_status' IS NULL
           OR o->>'moderation_status' IN ('approved', 'unchecked'));
  END IF;
  IF NOT visible OR visible_avant THEN
    RETURN NULL;
  END IF;
  FOR f IN SELECT user_id FROM favoris WHERE favori_id = NEW.user_id LOOP
    PERFORM public._cloche(f.user_id, NEW.user_id, 'favori_story',
                           NEW.id::text, interval '1 hour');
  END LOOP;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_cloche_story_favori ON public.stories;
CREATE TRIGGER trg_cloche_story_favori
  AFTER INSERT OR UPDATE OF moderation_status ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.cloche_story_favori();

-- ── « Nouvelle story des abonnés » : abonnements retirés de l'app ──
DROP TRIGGER IF EXISTS trg_notify_new_story ON public.stories;

COMMIT;
