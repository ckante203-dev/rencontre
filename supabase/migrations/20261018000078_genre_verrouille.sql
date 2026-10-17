-- 078 : le genre choisi à l'inscription ne peut plus être modifié par
-- l'utilisateur (même avec une ancienne version de l'app).
-- • Tant que l'inscription n'est pas terminée (onboarding_complete = false),
--   on peut encore revenir en arrière et changer.
-- • Un profil sans genre (« non précisé » / vide) peut le choisir une fois.
-- • Les admins (table admins, panneau admin) et les fonctions serveur
--   (service_role) peuvent toujours le corriger.
BEGIN;

CREATE OR REPLACE FUNCTION public.verrouiller_genre()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.gender IS DISTINCT FROM OLD.gender
     AND OLD.gender IN ('homme', 'femme')
     AND COALESCE(OLD.onboarding_complete, false)
     AND COALESCE(auth.role(), '') = 'authenticated'
     AND NOT EXISTS (SELECT 1 FROM admins
                     WHERE email = auth.jwt() ->> 'email') THEN
    NEW.gender := OLD.gender; -- on garde l'ancien, sans erreur
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS genre_verrouille ON public.profiles;
CREATE TRIGGER genre_verrouille
  BEFORE UPDATE OF gender ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.verrouiller_genre();

COMMIT;
