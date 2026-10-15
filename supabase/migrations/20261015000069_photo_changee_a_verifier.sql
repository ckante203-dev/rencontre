-- ═══════════════════════════════════════════════════════════════════
-- Badge vérifié : photo principale changée → à revoir par un admin
-- 2026-10-15 · À exécuter dans Supabase → SQL Editor. Ré-exécutable.
--
-- Remplace le retrait AUTOMATIQUE du badge (script 066) : la personne
-- garde son badge, et le changement arrive dans la page « Vérifications »
-- du panneau (ancienne photo, nouvelle photo, autres photos). L'admin
-- choisit « Même personne » (rien ne change) ou « Retirer le badge ».
-- La personne n'a pas à refaire de selfie.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- Le retrait automatique (066) est supprimé
DROP TRIGGER IF EXISTS trg_retrait_badge_photo ON public.profiles;

CREATE TABLE IF NOT EXISTS public.photos_changees (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ancienne_url  text,
  nouvelle_url  text,
  statut        text NOT NULL DEFAULT 'en_attente',   -- en_attente | gardee | retiree
  created_at    timestamptz NOT NULL DEFAULT now(),
  traitee_le    timestamptz
);
CREATE INDEX IF NOT EXISTS photos_changees_attente
  ON public.photos_changees (created_at) WHERE statut = 'en_attente';
ALTER TABLE public.photos_changees ENABLE ROW LEVEL SECURITY;  -- admins seulement, via les fonctions

CREATE OR REPLACE FUNCTION public._noter_photo_changee()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF COALESCE(NEW.est_verifie, false)
     AND NEW.photo_url IS NOT NULL
     AND NEW.photo_url IS DISTINCT FROM OLD.photo_url THEN
    -- une seule demande en attente par personne : on garde la plus récente
    DELETE FROM photos_changees WHERE user_id = NEW.id AND statut = 'en_attente';
    INSERT INTO photos_changees (user_id, ancienne_url, nouvelle_url)
    VALUES (NEW.id, OLD.photo_url, NEW.photo_url);
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;   -- ne jamais bloquer un changement de photo
END;
$$;

DROP TRIGGER IF EXISTS trg_photo_changee ON public.profiles;
CREATE TRIGGER trg_photo_changee
  AFTER UPDATE OF photo_url ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public._noter_photo_changee();

-- Liste pour le panneau
CREATE OR REPLACE FUNCTION public.admin_photos_changees()
RETURNS TABLE (id uuid, user_id uuid, name text, ancienne_url text, nouvelle_url text,
               photo_urls jsonb, est_verifie boolean, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public._exiger_admin();
  RETURN QUERY
    SELECT c.id, c.user_id, p.name::text, c.ancienne_url, c.nouvelle_url,
           to_jsonb(p.photo_urls), COALESCE(p.est_verifie, false), c.created_at
      FROM photos_changees c
      JOIN profiles p ON p.id = c.user_id
     WHERE c.statut = 'en_attente'
     ORDER BY c.created_at
     LIMIT 200;
END;
$$;

-- Décision : p_garder = true → « Même personne », false → badge retiré
CREATE OR REPLACE FUNCTION public.admin_traiter_photo_changee(p_id uuid, p_garder boolean)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user uuid;
BEGIN
  PERFORM public._exiger_admin();
  UPDATE photos_changees
     SET statut = CASE WHEN p_garder THEN 'gardee' ELSE 'retiree' END,
         traitee_le = now()
   WHERE id = p_id AND statut = 'en_attente'
  RETURNING user_id INTO v_user;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'introuvable_ou_deja_traitee' USING ERRCODE = 'P0001';
  END IF;
  IF NOT p_garder THEN
    UPDATE profiles SET est_verifie = false WHERE id = v_user;
  END IF;
  RETURN v_user;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_photos_changees() FROM public, anon;
REVOKE ALL ON FUNCTION public.admin_traiter_photo_changee(uuid, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_photos_changees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_traiter_photo_changee(uuid, boolean) TO authenticated;

COMMIT;
