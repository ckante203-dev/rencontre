-- ═══════════════════════════════════════════════════════════════════
-- 058 : Boost offert du mois programmé (lancé à l'heure choisie)
-- À exécuter dans le SQL Editor de Supabase. Ré-exécutable sans risque.
-- Nécessite le script 042 (Boost offert Premium).
-- ═══════════════════════════════════════════════════════════════════
BEGIN;

CREATE TABLE IF NOT EXISTS public.boosts_programmes (
  user_id     uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  a_lancer_le timestamptz NOT NULL,
  cree_le     timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.boosts_programmes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS boosts_programmes_moi ON public.boosts_programmes;
CREATE POLICY boosts_programmes_moi ON public.boosts_programmes
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid()
              AND a_lancer_le > now()
              AND a_lancer_le < now() + interval '8 days');

-- Toutes les 5 minutes : lance les Boosts arrivés à l'heure
-- (même vérifications que utiliser_boost_offert : Premium, 1 par mois)
CREATE OR REPLACE FUNCTION public.lancer_boosts_programmes()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  r record;
  v_cle text;
BEGIN
  FOR r IN SELECT * FROM boosts_programmes WHERE a_lancer_le <= now() LOOP
    BEGIN
      IF EXISTS (SELECT 1 FROM profiles
                  WHERE id = r.user_id AND COALESCE(is_premium, false)
                    AND NOT COALESCE(is_suspended, false)) THEN
        v_cle := public._cle_boost_offert(r.user_id);
        IF NOT EXISTS (SELECT 1 FROM boost_achats WHERE transaction_id = v_cle) THEN
          PERFORM public.appliquer_boost(r.user_id, v_cle, 'offert_premium', 60);
        END IF;
      END IF;
    EXCEPTION WHEN others THEN
      RAISE LOG 'boost programmé % non lancé : %', r.user_id, SQLERRM;
    END;
    DELETE FROM boosts_programmes WHERE user_id = r.user_id;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.lancer_boosts_programmes() FROM public, anon, authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'boosts-programmes') THEN
    PERFORM cron.unschedule('boosts-programmes');
  END IF;
END $$;
SELECT cron.schedule('boosts-programmes', '*/5 * * * *',
  $cron$SELECT public.lancer_boosts_programmes()$cron$);

COMMIT;
