-- ═══════════════════════════════════════════════════════════════════
-- Prénom au lieu du début du mail — 2026-10-02
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup).
-- Ré-exécutable sans risque.
--
-- Problème : le trigger handle_new_user (sur auth.users, créé dans le
-- tableau de bord, absent des migrations) mettait comme nom le début de
-- l'adresse mail : « bambasamuel465 » pour bambasamuel465@gmail.com.
-- Avec Google, l'app trouvait ensuite le profil déjà créé et n'y écrivait
-- jamais le prénom → le début du mail restait affiché (et le dévoilait).
--
-- 1. handle_new_user prend le prénom donné à l'inscription (champ « name »
--    de l'inscription par email, ou nom Google), sinon « Utilisateur ».
--    Plus jamais de bout d'adresse mail.
-- 2. Réparation des profils existants qui ont encore le début du mail.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ───────────────────────────────────────────────────────────────────
-- 1. Création du profil à l'inscription
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  nom text := nullif(trim(coalesce(
    new.raw_user_meta_data->>'name',
    new.raw_user_meta_data->>'full_name',
    '')), '');
BEGIN
  INSERT INTO public.profiles (id, name)
  VALUES (new.id, coalesce(split_part(nom, ' ', 1), 'Utilisateur'))
  ON CONFLICT (id) DO NOTHING;
  RETURN new;
END;
$$;

-- ───────────────────────────────────────────────────────────────────
-- 2. Profils existants : début du mail → prénom Google / d'inscription
-- ───────────────────────────────────────────────────────────────────
UPDATE public.profiles p
SET name = split_part(trim(coalesce(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name')), ' ', 1)
FROM auth.users u
WHERE u.id = p.id
  AND lower(p.name) = lower(split_part(u.email, '@', 1))
  AND nullif(trim(coalesce(
      u.raw_user_meta_data->>'full_name',
      u.raw_user_meta_data->>'name', '')), '') IS NOT NULL;

COMMIT;

-- ───────────────────────────────────────────────────────────────────
-- Vérification : profils qui ont ENCORE le début du mail (aucun prénom
-- connu). À regarder au cas par cas ; pour les remplacer par
-- « Utilisateur », décommenter l'UPDATE ci-dessous.
-- ───────────────────────────────────────────────────────────────────
SELECT p.id, p.name, u.email
FROM public.profiles p
JOIN auth.users u ON u.id = p.id
WHERE lower(p.name) = lower(split_part(u.email, '@', 1));

-- UPDATE public.profiles p SET name = 'Utilisateur'
-- FROM auth.users u
-- WHERE u.id = p.id AND lower(p.name) = lower(split_part(u.email, '@', 1));
