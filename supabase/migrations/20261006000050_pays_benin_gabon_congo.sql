-- ═══════════════════════════════════════════════════════════════════
-- Ouverture : Bénin, Gabon, Congo-Brazzaville — 2026-10-06
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- Villes du mode voyage (Premium) de ces 3 pays, actives tout de suite.
-- Pays retenus : francophones, en FCFA, où les relations entre personnes
-- du même sexe ne sont pas punies par la loi. Les villes préparées des
-- pays qui les punissent (Sénégal, Mali, Burkina Faso, Togo, Guinée…)
-- restent désactivées.
-- Côté Play Console : Production → Pays/régions → ajouter les 3 pays.
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.villes_voyage (nom, pays, drapeau, lat, lng, actif, ordre) VALUES
  ('Cotonou',        'Bénin',  '🇧🇯',  6.3703,  2.3912, true, 70),
  ('Abomey-Calavi',  'Bénin',  '🇧🇯',  6.4485,  2.3557, true, 71),
  ('Porto-Novo',     'Bénin',  '🇧🇯',  6.4969,  2.6289, true, 72),
  ('Parakou',        'Bénin',  '🇧🇯',  9.3372,  2.6303, true, 73),
  ('Libreville',     'Gabon',  '🇬🇦',  0.4162,  9.4673, true, 75),
  ('Port-Gentil',    'Gabon',  '🇬🇦', -0.7193,  8.7815, true, 76),
  ('Franceville',    'Gabon',  '🇬🇦', -1.6333, 13.5833, true, 77),
  ('Brazzaville',    'Congo',  '🇨🇬', -4.2634, 15.2429, true, 80),
  ('Pointe-Noire',   'Congo',  '🇨🇬', -4.7761, 11.8635, true, 81),
  ('Dolisie',        'Congo',  '🇨🇬', -4.1989, 12.6666, true, 82)
ON CONFLICT (nom, pays) DO UPDATE SET actif = true, ordre = EXCLUDED.ordre;

-- Par sécurité : pays où c'est interdit = jamais actifs
UPDATE public.villes_voyage SET actif = false
 WHERE pays IN ('Sénégal', 'Mali', 'Burkina Faso', 'Togo', 'Guinée',
                'Cameroun', 'Tchad', 'Burundi', 'Mauritanie', 'Comores');

COMMIT;

-- Vérification : villes actives par pays
SELECT pays, count(*) AS villes FROM public.villes_voyage
 WHERE actif GROUP BY pays ORDER BY min(ordre);
