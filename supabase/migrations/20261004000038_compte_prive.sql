-- ═══════════════════════════════════════════════════════════════════
-- Compte privé : refuser les demandes d'ami — 2026-10-04
-- À exécuter dans Supabase → SQL Editor, APRÈS 037. Ré-exécutable.
--
-- profiles.accepte_demandes_ami (par défaut oui). Désactivé (Paramètres →
-- Confidentialité) : personne ne peut m'envoyer de demande ; le bouton
-- affiche « 🔒 Compte privé ». Je peux toujours demander les autres, et
-- accepter une demande qu'on m'avait faite avant.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS accepte_demandes_ami boolean NOT NULL DEFAULT true;

-- Statut : aucun, envoyee, recue, amis, ou prive (compte fermé aux demandes)
CREATE OR REPLACE FUNCTION public.statut_ami(p_user uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT CASE WHEN statut = 'acceptee' THEN 'amis'
                 WHEN demandeur_id = auth.uid() THEN 'envoyee'
                 ELSE 'recue' END
     FROM amities
     WHERE user_a = LEAST(auth.uid(), p_user)
       AND user_b = GREATEST(auth.uid(), p_user)),
    (SELECT 'prive' FROM profiles
     WHERE id = p_user AND NOT accepte_demandes_ami),
    'aucun');
$$;

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
  SELECT * INTO ligne FROM amities
  WHERE user_a = LEAST(moi, p_user) AND user_b = GREATEST(moi, p_user);
  IF FOUND THEN
    IF ligne.statut = 'acceptee' THEN RETURN 'amis'; END IF;
    IF ligne.demandeur_id = moi THEN RETURN 'envoyee'; END IF;
    -- L'autre m'avait demandé : on devient amis (même si je suis privé)
    UPDATE amities SET statut = 'acceptee', acceptee_le = now()
    WHERE user_a = ligne.user_a AND user_b = ligne.user_b;
    PERFORM public._push_ami('ami_accepte', moi, p_user);
    RETURN 'amis';
  END IF;
  -- Compte privé : pas de nouvelle demande
  IF EXISTS (SELECT 1 FROM profiles WHERE id = p_user
             AND NOT accepte_demandes_ami) THEN
    RETURN 'prive';
  END IF;
  -- Anti-spam : 50 demandes en attente maximum
  IF (SELECT count(*) FROM amities
      WHERE demandeur_id = moi AND statut = 'en_attente') >= 50 THEN
    RAISE EXCEPTION 'trop_de_demandes' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO amities (user_a, user_b, demandeur_id)
  VALUES (LEAST(moi, p_user), GREATEST(moi, p_user), moi);
  PERFORM public._push_ami('ami_demande', moi, p_user);
  RETURN 'envoyee';
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
