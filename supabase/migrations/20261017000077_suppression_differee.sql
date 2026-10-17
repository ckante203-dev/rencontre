-- ═══════════════════════════════════════════════════════════════════
-- Suppression de compte différée (30 jours) — 2026-10-17
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Avant : « Supprimer mon compte » effaçait tout immédiatement.
-- Maintenant (app 1.1.9) :
--   1. la demande MASQUE le compte tout de suite (is_suspended : il
--      disparaît de l'Accueil, de la carte, des Likes…) et note la date ;
--   2. si la personne se reconnecte dans les 30 jours, l'app lui propose
--      de garder son compte (annulation) ;
--   3. chaque nuit, pg_cron supprime définitivement les comptes demandés
--      depuis plus de 30 jours (fonction delete-account, secret de purge).
-- Plus tard (chantier) : e-mails de confirmation, export des données.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS suppression_le timestamptz,
  ADD COLUMN IF NOT EXISTS suspendu_par_suppression boolean NOT NULL DEFAULT false;

-- Demande de suppression (par la personne elle-même)
CREATE OR REPLACE FUNCTION public.demander_suppression_compte()
RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'non_connecte' USING ERRCODE = '42501'; END IF;
  UPDATE profiles
     SET suppression_le = COALESCE(suppression_le, now()),
         -- Un compte déjà suspendu par un admin le reste après annulation
         suspendu_par_suppression = CASE WHEN COALESCE(is_suspended, false)
                                         THEN suspendu_par_suppression ELSE true END,
         is_suspended = true,
         is_online = false
   WHERE id = v_uid;
  RETURN (SELECT suppression_le + interval '30 days' FROM profiles WHERE id = v_uid);
END;
$$;

-- Annulation (reconnexion dans les 30 jours)
CREATE OR REPLACE FUNCTION public.annuler_suppression_compte()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  UPDATE profiles
     SET suppression_le = NULL,
         is_suspended = CASE WHEN suspendu_par_suppression THEN false ELSE is_suspended END,
         suspendu_par_suppression = false
   WHERE id = auth.uid() AND suppression_le IS NOT NULL;
END;
$$;

-- Date de suppression prévue (null = rien de prévu)
CREATE OR REPLACE FUNCTION public.ma_suppression_prevue()
RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT suppression_le + interval '30 days' FROM profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.demander_suppression_compte() FROM public, anon;
REVOKE ALL ON FUNCTION public.annuler_suppression_compte() FROM public, anon;
REVOKE ALL ON FUNCTION public.ma_suppression_prevue() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.demander_suppression_compte() TO authenticated;
GRANT EXECUTE ON FUNCTION public.annuler_suppression_compte() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ma_suppression_prevue() TO authenticated;

-- Suppression définitive des comptes demandés depuis plus de 30 jours
CREATE OR REPLACE FUNCTION public.purger_comptes_supprimes()
RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r record;
  n int := 0;
BEGIN
  FOR r IN SELECT id FROM profiles
            WHERE suppression_le IS NOT NULL AND suppression_le < now() - interval '30 days'
            LIMIT 50
  LOOP
    PERFORM net.http_post(
      url := 'https://flixcyjefjcyjwvjdiny.supabase.co/functions/v1/delete-account',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        -- clé publique (anon) pour passer la passerelle ; le vrai contrôle
        -- est le secret de purge
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZsaXhjeWplZmpjeWp3dmpkaW55Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0MTM4MDMsImV4cCI6MjEwMzk4OTgwM30.2LcUPXgP47xsWr70CdaAOuwu-PZMNl3hcwTIV8cmpz4',
        'x-purge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'purge_secret')),
      body := jsonb_build_object('user_id', r.id),
      timeout_milliseconds := 60000);
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;
REVOKE ALL ON FUNCTION public.purger_comptes_supprimes() FROM public, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purger-comptes-supprimes') THEN
    PERFORM cron.unschedule('purger-comptes-supprimes');
  END IF;
END $$;
SELECT cron.schedule('purger-comptes-supprimes', '30 3 * * *', 'SELECT public.purger_comptes_supprimes()');

COMMIT;

-- Vérification : suppressions en attente
SELECT id, name, suppression_le, suppression_le + interval '30 days' AS suppression_definitive
  FROM public.profiles WHERE suppression_le IS NOT NULL ORDER BY suppression_le;
