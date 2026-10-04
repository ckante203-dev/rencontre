-- ═══════════════════════════════════════════════════════════════════
-- Système d'Amis (façon Snapchat) — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 036. Ré-exécutable.
--
-- • amities : une ligne par paire (user_a < user_b), demande puis
--   acceptation. Demander quelqu'un qui m'a déjà demandé = accepter.
-- • RPC : demander_ami, accepter_ami, retirer_ami (refuser / annuler /
--   supprimer), statut_ami, mes_amis, demandes_amis_recues.
-- • Notifications : push (dynamic-processor, types ami_demande /
--   ami_accepte) + cloche.
-- • Stories « 👥 Amis » (visibility = 'amis') : seulement mes amis.
-- • Blocage : bloquer quelqu'un supprime l'amitié.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.amities (
  user_a       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_b       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  demandeur_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  statut       text NOT NULL DEFAULT 'en_attente'
               CHECK (statut IN ('en_attente', 'acceptee')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  acceptee_le  timestamptz,
  PRIMARY KEY (user_a, user_b),
  CHECK (user_a < user_b),
  CHECK (demandeur_id IN (user_a, user_b))
);
CREATE INDEX IF NOT EXISTS amities_b_idx ON public.amities (user_b);

ALTER TABLE public.amities ENABLE ROW LEVEL SECURITY;
-- Lecture de mes propres liens ; écriture uniquement par les RPC
DROP POLICY IF EXISTS amities_select ON public.amities;
CREATE POLICY amities_select ON public.amities FOR SELECT TO authenticated
  USING (auth.uid() IN (user_a, user_b) OR public.is_admin());

CREATE OR REPLACE FUNCTION public.sont_amis(p1 uuid, p2 uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (SELECT 1 FROM amities
                 WHERE user_a = LEAST(p1, p2) AND user_b = GREATEST(p1, p2)
                   AND statut = 'acceptee');
$$;
REVOKE ALL ON FUNCTION public.sont_amis(uuid, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.sont_amis(uuid, uuid) TO authenticated;

-- Push via dynamic-processor (même mécanisme que les alertes favoris)
CREATE OR REPLACE FUNCTION public._push_ami(p_type text, p_de uuid, p_pour uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  cle text;
BEGIN
  PERFORM public._cloche(p_pour, p_de, p_type, NULL, interval '10 minutes');
  SELECT decrypted_secret INTO cle
  FROM vault.decrypted_secrets WHERE name = 'notif_secret' LIMIT 1;
  IF cle IS NULL THEN RETURN; END IF;
  PERFORM net.http_post(
    url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/dynamic-processor',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cle,
      'apikey', cle),
    body := jsonb_build_object('type', p_type,
                               'from_user_id', p_de, 'to_user_id', p_pour));
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '_push_ami : %', SQLERRM;
END;
$$;
REVOKE ALL ON FUNCTION public._push_ami(text, uuid, uuid) FROM public, anon, authenticated;

-- Statut vis-à-vis de quelqu'un : aucun, envoyee, recue, amis
CREATE OR REPLACE FUNCTION public.statut_ami(p_user uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT CASE WHEN statut = 'acceptee' THEN 'amis'
                WHEN demandeur_id = auth.uid() THEN 'envoyee'
                ELSE 'recue' END
    FROM amities
    WHERE user_a = LEAST(auth.uid(), p_user)
      AND user_b = GREATEST(auth.uid(), p_user)), 'aucun');
$$;
REVOKE ALL ON FUNCTION public.statut_ami(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.statut_ami(uuid) TO authenticated;

-- Demander (ou accepter si l'autre m'a déjà demandé). Renvoie le statut.
CREATE OR REPLACE FUNCTION public.demander_ami(p_user uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  moi uuid := auth.uid();
  ligne amities;
BEGIN
  IF moi IS NULL OR p_user IS NULL OR p_user = moi THEN RETURN 'aucun'; END IF;
  IF public.blocage_entre(moi, p_user)
     OR EXISTS (SELECT 1 FROM profiles WHERE id = p_user
                AND COALESCE(is_suspended, false)) THEN
    RETURN 'aucun';
  END IF;
  -- Anti-spam : 50 demandes en attente maximum
  IF (SELECT count(*) FROM amities
      WHERE demandeur_id = moi AND statut = 'en_attente') >= 50 THEN
    RAISE EXCEPTION 'trop_de_demandes' USING ERRCODE = 'P0001';
  END IF;
  SELECT * INTO ligne FROM amities
  WHERE user_a = LEAST(moi, p_user) AND user_b = GREATEST(moi, p_user);
  IF FOUND THEN
    IF ligne.statut = 'acceptee' THEN RETURN 'amis'; END IF;
    IF ligne.demandeur_id = moi THEN RETURN 'envoyee'; END IF;
    -- L'autre m'avait demandé : on devient amis
    UPDATE amities SET statut = 'acceptee', acceptee_le = now()
    WHERE user_a = ligne.user_a AND user_b = ligne.user_b;
    PERFORM public._push_ami('ami_accepte', moi, p_user);
    RETURN 'amis';
  END IF;
  INSERT INTO amities (user_a, user_b, demandeur_id)
  VALUES (LEAST(moi, p_user), GREATEST(moi, p_user), moi);
  PERFORM public._push_ami('ami_demande', moi, p_user);
  RETURN 'envoyee';
END;
$$;
REVOKE ALL ON FUNCTION public.demander_ami(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.demander_ami(uuid) TO authenticated;

-- Accepter une demande reçue
CREATE OR REPLACE FUNCTION public.accepter_ami(p_user uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  moi uuid := auth.uid();
BEGIN
  UPDATE amities SET statut = 'acceptee', acceptee_le = now()
  WHERE user_a = LEAST(moi, p_user) AND user_b = GREATEST(moi, p_user)
    AND statut = 'en_attente' AND demandeur_id = p_user;
  IF NOT FOUND THEN RETURN public.statut_ami(p_user); END IF;
  PERFORM public._push_ami('ami_accepte', moi, p_user);
  RETURN 'amis';
END;
$$;
REVOKE ALL ON FUNCTION public.accepter_ami(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.accepter_ami(uuid) TO authenticated;

-- Refuser / annuler ma demande / retirer un ami (sans prévenir l'autre)
CREATE OR REPLACE FUNCTION public.retirer_ami(p_user uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  DELETE FROM amities
  WHERE user_a = LEAST(auth.uid(), p_user)
    AND user_b = GREATEST(auth.uid(), p_user);
$$;
REVOKE ALL ON FUNCTION public.retirer_ami(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.retirer_ami(uuid) TO authenticated;

-- Mes amis (et demandes reçues / envoyées) avec leur profil
DROP FUNCTION IF EXISTS public.mes_amis();
CREATE FUNCTION public.mes_amis()
RETURNS TABLE (id uuid, name text, photo_url text, username text,
               en_ligne boolean, statut text, depuis timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT pr.id, pr.name::text, pr.photo_url::text, pr.username::text,
         COALESCE(pr.last_seen > now() - interval '30 minutes', false),
         CASE WHEN a.statut = 'acceptee' THEN 'amis'
              WHEN a.demandeur_id = auth.uid() THEN 'envoyee'
              ELSE 'recue' END,
         COALESCE(a.acceptee_le, a.created_at)
  FROM amities a
  JOIN profiles pr ON pr.id = CASE WHEN a.user_a = auth.uid()
                                   THEN a.user_b ELSE a.user_a END
  WHERE auth.uid() IN (a.user_a, a.user_b)
    AND NOT COALESCE(pr.is_suspended, false)
    AND NOT public.blocage_entre(pr.id, auth.uid())
  ORDER BY pr.name;
$$;
REVOKE ALL ON FUNCTION public.mes_amis() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mes_amis() TO authenticated;

-- Bloquer quelqu'un supprime l'amitié (et la demande)
CREATE OR REPLACE FUNCTION public.blocage_supprime_amitie()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.blocked_users IS DISTINCT FROM OLD.blocked_users THEN
    DELETE FROM amities a
    WHERE NEW.id IN (a.user_a, a.user_b)
      AND (CASE WHEN a.user_a = NEW.id THEN a.user_b ELSE a.user_a END)::text
          = ANY (COALESCE(NEW.blocked_users::text[], '{}'));
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_blocage_supprime_amitie ON public.profiles;
CREATE TRIGGER trg_blocage_supprime_amitie
  AFTER UPDATE OF blocked_users ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.blocage_supprime_amitie();

-- ── Stories « 👥 Amis » : seulement mes amis ──────────────────────
DROP POLICY IF EXISTS stories_amis ON public.stories;
CREATE POLICY stories_amis ON public.stories
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(visibility, 'public') <> 'amis'
    OR user_id = auth.uid()
    OR public.sont_amis(user_id, auth.uid())
    OR public.is_admin()
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
