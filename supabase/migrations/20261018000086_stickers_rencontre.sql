-- ═══════════════════════════════════════════════════════════════════
-- Stickers de rencontre sur les stories — 2026-10-18 (app 1.2.0)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
--   📍 Ma ville      : ma_ville() → la grande ville la plus proche de ma
--                      position (table villes_voyage), sans service externe.
--   🔥 Vibe check    : sondage à 2 choix (story_votes).
--   💘 Crush anonyme : « j'ai un crush sur toi » sans dire qui (story_crushs).
--                      L'auteur reçoit une notification anonyme. Si un jour
--                      il like la personne, le like réciproque est créé tout
--                      seul → c'est un match et l'identité est révélée.
--   🙋 Dispo ce soir : réponse en message privé (rien à stocker ici).
-- Les anciennes versions de l'app ignorent ces stickers.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 📍 Ma ville ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ma_ville()
RETURNS TABLE (nom text, pays text, drapeau text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.nom, v.pays, v.drapeau
    FROM villes_voyage v, profiles p
   WHERE p.id = auth.uid()
     AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL
     AND v.actif
     AND public._distance_km(v.lat, v.lng, p.latitude, p.longitude) <= 60
   ORDER BY public._distance_km(v.lat, v.lng, p.latitude, p.longitude)
   LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.ma_ville() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.ma_ville() TO authenticated;

-- ─── 🔥 Vibe check (sondage) ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_votes (
  story_id   text NOT NULL,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  choix      smallint NOT NULL CHECK (choix IN (0, 1)),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, user_id)
);
ALTER TABLE public.story_votes ENABLE ROW LEVEL SECURITY;
-- Aucune politique : tout passe par les fonctions ci-dessous

-- Voter (ou changer d'avis) puis renvoyer les résultats
CREATE OR REPLACE FUNCTION public.voter_story(p_story text, p_choix int)
RETURNS TABLE (votes_0 bigint, votes_1 bigint, mon_choix int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'non_connecte'; END IF;
  IF p_choix NOT IN (0, 1) THEN RAISE EXCEPTION 'choix_invalide'; END IF;
  -- Story active, visible, et pas la mienne
  IF NOT EXISTS (SELECT 1 FROM stories s
                  WHERE s.id::text = p_story AND s.expires_at > now()
                    AND s.user_id <> auth.uid()
                    AND NOT public.blocage_entre(auth.uid(), s.user_id)) THEN
    RAISE EXCEPTION 'story_indisponible';
  END IF;
  INSERT INTO story_votes (story_id, user_id, choix)
  VALUES (p_story, auth.uid(), p_choix)
  ON CONFLICT (story_id, user_id) DO UPDATE SET choix = EXCLUDED.choix;
  RETURN QUERY SELECT * FROM public.resultats_story(p_story);
END;
$$;

CREATE OR REPLACE FUNCTION public.resultats_story(p_story text)
RETURNS TABLE (votes_0 bigint, votes_1 bigint, mon_choix int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*) FILTER (WHERE v.choix = 0),
         count(*) FILTER (WHERE v.choix = 1),
         (SELECT m.choix::int FROM story_votes m
           WHERE m.story_id = p_story AND m.user_id = auth.uid())
    FROM story_votes v
   WHERE v.story_id = p_story;
$$;

-- L'auteur voit qui a voté quoi
CREATE OR REPLACE FUNCTION public.votants_story(p_story text)
RETURNS TABLE (user_id uuid, name text, photo_url text, choix int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.user_id, p.name::text, p.photo_url::text, v.choix::int
    FROM story_votes v
    JOIN profiles p ON p.id = v.user_id
    JOIN stories s ON s.id::text = v.story_id
   WHERE v.story_id = p_story AND s.user_id = auth.uid()
   ORDER BY v.created_at DESC
   LIMIT 300;
$$;

REVOKE ALL ON FUNCTION public.voter_story(text, int) FROM public, anon;
REVOKE ALL ON FUNCTION public.resultats_story(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.votants_story(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.voter_story(text, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.resultats_story(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.votants_story(text) TO authenticated;

-- ─── 💘 Crush anonyme ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.story_crushs (
  from_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_user_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  story_id     text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  revele_le    timestamptz,
  PRIMARY KEY (from_user_id, to_user_id)
);
CREATE INDEX IF NOT EXISTS story_crushs_to_idx ON public.story_crushs (to_user_id);
ALTER TABLE public.story_crushs ENABLE ROW LEVEL SECURITY;
-- Aucune politique : personne ne peut lire qui a envoyé un crush

-- Envoyer un crush depuis une story. Renvoie 'envoye', 'deja' ou une erreur.
CREATE OR REPLACE FUNCTION public.envoyer_crush_story(p_story text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_moi    uuid := auth.uid();
  v_auteur uuid;
  cle      text;
BEGIN
  IF v_moi IS NULL THEN RAISE EXCEPTION 'non_connecte'; END IF;
  SELECT s.user_id INTO v_auteur FROM stories s
   WHERE s.id::text = p_story AND s.expires_at > now();
  IF v_auteur IS NULL OR v_auteur = v_moi
     OR public.blocage_entre(v_moi, v_auteur) THEN
    RAISE EXCEPTION 'story_indisponible';
  END IF;
  -- Anti-abus : 10 crushs par jour
  IF (SELECT count(*) FROM story_crushs
       WHERE from_user_id = v_moi AND created_at > now() - interval '1 day') >= 10 THEN
    RAISE EXCEPTION 'trop_de_crushs';
  END IF;
  INSERT INTO story_crushs (from_user_id, to_user_id, story_id)
  VALUES (v_moi, v_auteur, p_story)
  ON CONFLICT (from_user_id, to_user_id) DO NOTHING;
  IF NOT FOUND THEN RETURN 'deja'; END IF;

  -- Déjà liké par l'auteur ? Alors c'est réciproque tout de suite
  IF EXISTS (SELECT 1 FROM likes WHERE from_user_id = v_auteur AND to_user_id = v_moi) THEN
    INSERT INTO likes (from_user_id, to_user_id) VALUES (v_moi, v_auteur)
    ON CONFLICT DO NOTHING;
    UPDATE story_crushs SET revele_le = now()
     WHERE from_user_id = v_moi AND to_user_id = v_auteur;
    RETURN 'reciproque';
  END IF;

  -- Notification anonyme à l'auteur (dynamic-processor, type crush_story)
  BEGIN
    SELECT decrypted_secret INTO cle
      FROM vault.decrypted_secrets WHERE name = 'notif_secret' LIMIT 1;
    IF cle IS NOT NULL THEN
      PERFORM net.http_post(
        url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/dynamic-processor',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || cle,
          'apikey', cle),
        body := jsonb_build_object(
          'type', 'crush_story',
          'from_user_id', v_moi,
          'to_user_id', v_auteur));
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- la notification est un bonus, jamais bloquante
  END;
  RETURN 'envoye';
END;
$$;

-- Nombre de crushs anonymes reçus (encore secrets)
CREATE OR REPLACE FUNCTION public.mes_crushs_secrets()
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*) FROM story_crushs
   WHERE to_user_id = auth.uid() AND revele_le IS NULL;
$$;

REVOKE ALL ON FUNCTION public.envoyer_crush_story(text) FROM public, anon;
REVOKE ALL ON FUNCTION public.mes_crushs_secrets() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.envoyer_crush_story(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mes_crushs_secrets() TO authenticated;

-- Révélation : quand l'auteur like quelqu'un qui avait un crush sur lui,
-- le like réciproque est créé → match (l'app le détecte et l'annonce).
CREATE OR REPLACE FUNCTION public.reveler_crush()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  BEGIN
    IF EXISTS (SELECT 1 FROM story_crushs
                WHERE from_user_id = NEW.to_user_id
                  AND to_user_id = NEW.from_user_id
                  AND revele_le IS NULL) THEN
      UPDATE story_crushs SET revele_le = now()
       WHERE from_user_id = NEW.to_user_id AND to_user_id = NEW.from_user_id;
      INSERT INTO likes (from_user_id, to_user_id)
      VALUES (NEW.to_user_id, NEW.from_user_id)
      ON CONFLICT DO NOTHING;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- ne jamais bloquer un like
  END;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_reveler_crush ON public.likes;
CREATE TRIGGER trg_reveler_crush
  AFTER INSERT ON public.likes
  FOR EACH ROW EXECUTE FUNCTION public.reveler_crush();

COMMIT;
