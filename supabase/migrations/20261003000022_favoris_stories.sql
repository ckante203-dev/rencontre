-- ═══════════════════════════════════════════════════════════════════
-- Favoris ⭐ : alerte quand un favori publie une story — 2026-10-03
-- À exécuter dans Supabase → SQL Editor (tout le fichier d'un coup),
-- APRÈS 20261002000021_favoris.sql (réutilise _alerte_favori).
-- Ré-exécutable sans risque.
--
-- « ⭐ X a publié une story » (dynamic-processor, type favori_story),
-- au plus 1 fois par heure et par favori (plusieurs stories d'affilée =
-- une seule alerte).
-- Seulement si la story est VISIBLE par tous :
--   • visibilité « public » (pas les stories réservées aux amis) ;
--   • modération : pas encore analysée (NULL), approuvée ou « unchecked ».
--     Une story « pending » déclenche l'alerte au moment où elle est
--     validée (UPDATE de moderation_status).
-- Respecte le réglage « Alertes de mes favoris » et les blocages.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.alerte_story_favoris()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  n jsonb := to_jsonb(NEW);
  o jsonb;
  visible boolean;
  visible_avant boolean := false;
  f record;
BEGIN
  visible := COALESCE(n->>'visibility', 'public') = 'public'
    AND (n->>'moderation_status' IS NULL
         OR n->>'moderation_status' IN ('approved', 'unchecked'))
    AND (NEW.expires_at IS NULL OR NEW.expires_at > now());

  IF TG_OP = 'UPDATE' THEN
    o := to_jsonb(OLD);
    visible_avant := COALESCE(o->>'visibility', 'public') = 'public'
      AND (o->>'moderation_status' IS NULL
           OR o->>'moderation_status' IN ('approved', 'unchecked'));
  END IF;

  -- Alerte seulement quand la story DEVIENT visible
  IF NOT visible OR visible_avant THEN
    RETURN NULL;
  END IF;

  FOR f IN
    SELECT fv.user_id
    FROM favoris fv
    JOIN profiles p ON p.id = fv.user_id
    WHERE fv.favori_id = NEW.user_id
      AND COALESCE(p.notif_favoris, true)
      AND NOT public.blocage_entre(NEW.user_id, fv.user_id)
  LOOP
    PERFORM public._alerte_favori(f.user_id, NEW.user_id, 'favori_story',
                                  interval '1 hour');
  END LOOP;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_alerte_story_favoris ON public.stories;
CREATE TRIGGER trg_alerte_story_favoris
  AFTER INSERT OR UPDATE OF moderation_status ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.alerte_story_favoris();

COMMIT;
