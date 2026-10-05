-- ═══════════════════════════════════════════════════════════════════
-- Cloche 🔔 : « vu » à l'ouverture + nettoyage — 2026-10-05
-- À exécuter dans Supabase → SQL Editor, APRÈS 026. Ré-exécutable.
--
-- marquer_notifications_lues() : appelée quand on ouvre l'écran
-- Notifications. Marque toutes MES notifications comme lues (le badge
-- de la cloche repart à 0) et supprime celles de plus de 30 jours.
-- SECURITY DEFINER : fonctionne quelles que soient les politiques RLS de
-- la table notifications (avant, la mise à jour pouvait ne rien faire).
-- Compatible 1.0.11 : nouvelle fonction seulement.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.marquer_notifications_lues()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;

  UPDATE notifications
     SET is_read = true
   WHERE user_id = auth.uid() AND NOT COALESCE(is_read, false);

  DELETE FROM notifications
   WHERE user_id = auth.uid()
     AND created_at < now() - interval '30 days';
END;
$$;
REVOKE ALL ON FUNCTION public.marquer_notifications_lues() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.marquer_notifications_lues() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
