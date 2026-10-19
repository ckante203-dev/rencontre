-- ═══════════════════════════════════════════════════════════════════
-- Présence « en ligne » allégée — 2026-10-19
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Chaque téléphone met à jour profiles.last_seen toutes les minutes
-- (heartbeat), et chaque mise à jour de profil est diffusée en temps réel
-- à TOUS les téléphones connectés (pastilles « en ligne ») : avec 50
-- personnes en ligne, 2 500 envois par minute → serveur saturé.
-- Or « en ligne » = actif dans les 30 dernières minutes : une mise à jour
-- toutes les 4 minutes suffit largement.
--
-- Ici : une mise à jour qui ne change QUE last_seen / updated_at, moins de
-- 4 minutes après la précédente et sans changer is_online, est ignorée
-- (aucune écriture, donc aucune diffusion). Effet immédiat pour toutes les
-- versions de l'app. Tout autre changement passe normalement.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.alleger_presence()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.last_seen IS NOT NULL
     AND OLD.last_seen IS NOT NULL
     AND NEW.is_online IS NOT DISTINCT FROM OLD.is_online
     AND NEW.last_seen >= OLD.last_seen
     AND NEW.last_seen - OLD.last_seen < interval '4 minutes'
     AND (to_jsonb(NEW) - 'last_seen' - 'updated_at')
         = (to_jsonb(OLD) - 'last_seen' - 'updated_at') THEN
    RETURN NULL; -- simple « toujours là » trop rapproché : on ignore
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS a_trg_alleger_presence ON public.profiles;
-- Nom en « a_ » : passe avant les autres déclencheurs BEFORE UPDATE
-- (ordre alphabétique), qui n'ont donc rien à faire pour un heartbeat ignoré
CREATE TRIGGER a_trg_alleger_presence
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.alleger_presence();
