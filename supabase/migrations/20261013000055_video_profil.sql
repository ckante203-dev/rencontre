-- ═══════════════════════════════════════════════════════════════════
-- 055 : vidéo de profil (15 s) modérée par un admin
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
--
-- • La personne dépose une vidéo (profiles.video_url) : elle passe
--   automatiquement « en_attente » et n'est montrée à personne.
-- • Un admin la valide ou la refuse (panneau admin → Vidéos de profil).
-- • Personne d'autre ne peut changer video_statut (trigger).
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS video_url        text,
  ADD COLUMN IF NOT EXISTS video_statut     text,
  ADD COLUMN IF NOT EXISTS video_soumise_le timestamptz,
  ADD COLUMN IF NOT EXISTS video_motif      text;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_video_statut;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_video_statut
  CHECK (video_statut IS NULL OR video_statut IN ('en_attente', 'validee', 'refusee'));
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_video_url;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_video_url
  CHECK (video_url IS NULL OR video_url LIKE '%/storage/v1/object/public/profile-photos/%');

CREATE OR REPLACE FUNCTION public.proteger_video_profil()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Fonctions serveur / admin : pas de contrôle
  IF current_user NOT IN ('authenticated', 'anon') OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  IF NEW.video_url IS DISTINCT FROM OLD.video_url THEN
    -- Nouvelle vidéo (ou suppression) : repart en modération
    NEW.video_statut := CASE WHEN NEW.video_url IS NULL THEN NULL ELSE 'en_attente' END;
    NEW.video_soumise_le := CASE WHEN NEW.video_url IS NULL THEN NULL ELSE now() END;
    NEW.video_motif := NULL;
  ELSE
    NEW.video_statut := OLD.video_statut;
    NEW.video_soumise_le := OLD.video_soumise_le;
    NEW.video_motif := OLD.video_motif;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_proteger_video_profil ON public.profiles;
CREATE TRIGGER trg_proteger_video_profil
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.proteger_video_profil();

-- Décision de l'admin
CREATE OR REPLACE FUNCTION public.admin_traiter_video(
  p_user uuid, p_valider boolean, p_motif text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin requis' USING ERRCODE = '42501';
  END IF;
  UPDATE profiles
     SET video_statut = CASE WHEN p_valider THEN 'validee' ELSE 'refusee' END,
         video_motif  = CASE WHEN p_valider THEN NULL ELSE p_motif END
   WHERE id = p_user AND video_url IS NOT NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_traiter_video(uuid, boolean, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_traiter_video(uuid, boolean, text) TO authenticated;

COMMIT;
