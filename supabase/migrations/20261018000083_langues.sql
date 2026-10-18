-- ═══════════════════════════════════════════════════════════════════
-- Plusieurs langues — 2026-10-18 (app 1.1.10)
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- 1. profiles.langue et annonces_app.langue acceptent n'importe quel code
--    de langue à 2 lettres (avant : seulement 'fr' et 'en'), pour pouvoir
--    ajouter l'espagnol, le portugais… sans toucher à la base.
-- 2. Message de bienvenue de Zamu en anglais pour les inscrits qui ont
--    choisi l'anglais (avant : toujours en français).
-- Compatible avec toutes les versions de l'app.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

-- ─── 1. Codes de langue ─────────────────────────────────────────────
DO $$
DECLARE
  c record;
BEGIN
  FOR c IN
    SELECT conrelid::regclass AS tbl, conname
      FROM pg_constraint
     WHERE contype = 'c'
       AND conrelid IN ('public.profiles'::regclass, 'public.annonces_app'::regclass)
       AND pg_get_constraintdef(oid) ILIKE '%langue%'
       AND pg_get_constraintdef(oid) ILIKE '%''en''%'
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', c.tbl, c.conname);
  END LOOP;
END $$;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_langue_code;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_langue_code CHECK (langue ~ '^[a-z]{2}$');
ALTER TABLE public.annonces_app DROP CONSTRAINT IF EXISTS annonces_app_langue_code;
ALTER TABLE public.annonces_app
  ADD CONSTRAINT annonces_app_langue_code CHECK (langue IS NULL OR langue ~ '^[a-z]{2}$');

-- ─── 2. Message de bienvenue en anglais ─────────────────────────────
ALTER TABLE public.app_config ADD COLUMN IF NOT EXISTS message_bienvenue_en text;
UPDATE public.app_config
   SET message_bienvenue_en = COALESCE(message_bienvenue_en,
'Welcome to Zamu, {prenom} 💜

You have 48 h of free Premium: see who liked you, discover more profiles and get your profile featured.

A few tips:
📸 a photo where your face is visible
✅ get your profile verified (blue badge)
👣 check out "Crossed paths" on the Home screen

An idea, a problem, a question? Reply here, we read everything 🙂
— The Zamu team')
 WHERE id = 'config';

-- Même déclencheur que le script 072, avec le choix de la langue
CREATE OR REPLACE FUNCTION public._message_bienvenue()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_off  uuid;
  v_conv uuid;
  v_txt  text;
BEGIN
  IF COALESCE(NEW.est_officiel, false) THEN RETURN NEW; END IF;
  IF COALESCE(NEW.onboarding_complete, false)
     AND (TG_OP = 'INSERT' OR NOT COALESCE(OLD.onboarding_complete, false))
     AND NEW.created_at > now() - interval '7 days' THEN
    SELECT id INTO v_off FROM profiles WHERE est_officiel ORDER BY created_at LIMIT 1;
    IF v_off IS NULL OR v_off = NEW.id THEN RETURN NEW; END IF;
    -- Anglais si la personne a choisi l'anglais (et qu'un texte existe),
    -- sinon le message français
    SELECT CASE WHEN NEW.langue = 'en'
                     AND COALESCE(btrim(message_bienvenue_en), '') <> ''
                THEN message_bienvenue_en ELSE message_bienvenue END
      INTO v_txt FROM app_config WHERE id = 'config';
    IF COALESCE(btrim(v_txt), '') = '' THEN RETURN NEW; END IF;
    -- Une seule fois par personne
    IF EXISTS (SELECT 1 FROM conversations
                WHERE (user1_id = v_off AND user2_id = NEW.id)
                   OR (user1_id = NEW.id AND user2_id = v_off)) THEN
      RETURN NEW;
    END IF;
    INSERT INTO conversations (user1_id, user2_id, request_status, initiated_by)
    VALUES (v_off, NEW.id, 'accepted', v_off)
    RETURNING id INTO v_conv;
    INSERT INTO messages (conversation_id, sender_id, type, content, status)
    VALUES (v_conv, v_off, 'text',
            replace(v_txt, '{prenom}', COALESCE(NULLIF(btrim(NEW.name), ''), '')),
            'sent');
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RETURN NEW;   -- jamais bloquer une inscription
END;
$$;

COMMIT;
