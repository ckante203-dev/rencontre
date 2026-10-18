-- ═══════════════════════════════════════════════════════════════════
-- Mode voyage : les plus grandes villes de chaque pays ouvert — 2026-10-18
-- À exécuter dans Supabase → SQL Editor. Ré-exécutable sans risque.
--
-- 1. Ajoute (ou réactive) jusqu'à 5 grandes villes par pays ouvert sur
--    Google Play (les pays décochés pour la sécurité des membres ne sont
--    pas proposés).
-- 2. Ordre de la liste : d'abord le pays où se trouve le membre, puis les
--    pays qui ont le plus de profils, puis l'ordre des villes. L'app
--    garde l'ordre reçu : effet immédiat, même pour les versions déjà
--    installées.
-- Pour retirer une ville : UPDATE villes_voyage SET actif = false
--                          WHERE nom = '…' AND pays = '…';
-- ═══════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.villes_voyage (nom, pays, drapeau, lat, lng, actif, ordre) VALUES
  -- ── Afrique de l'Ouest ──
  ('Dakar',          'Sénégal',        '🇸🇳', 14.7167, -17.4677, true, 1),
  ('Thiès',          'Sénégal',        '🇸🇳', 14.7910, -16.9256, true, 2),
  ('Saint-Louis',    'Sénégal',        '🇸🇳', 16.0326, -16.4818, true, 3),
  ('Touba',          'Sénégal',        '🇸🇳', 14.8500, -15.8833, true, 4),
  ('Ziguinchor',     'Sénégal',        '🇸🇳', 12.5833, -16.2719, true, 5),
  ('Bamako',         'Mali',           '🇲🇱', 12.6392,  -8.0029, true, 1),
  ('Sikasso',        'Mali',           '🇲🇱', 11.3176,  -5.6665, true, 2),
  ('Ségou',          'Mali',           '🇲🇱', 13.4317,  -6.2157, true, 3),
  ('Mopti',          'Mali',           '🇲🇱', 14.4843,  -4.1830, true, 4),
  ('Kayes',          'Mali',           '🇲🇱', 14.4469, -11.4445, true, 5),
  ('Ouagadougou',    'Burkina Faso',   '🇧🇫', 12.3714,  -1.5197, true, 1),
  ('Bobo-Dioulasso', 'Burkina Faso',   '🇧🇫', 11.1771,  -4.2979, true, 2),
  ('Koudougou',      'Burkina Faso',   '🇧🇫', 12.2526,  -2.3627, true, 3),
  ('Banfora',        'Burkina Faso',   '🇧🇫', 10.6333,  -4.7667, true, 4),
  ('Ouahigouya',     'Burkina Faso',   '🇧🇫', 13.5828,  -2.4216, true, 5),
  ('Conakry',        'Guinée',         '🇬🇳',  9.6412, -13.5784, true, 1),
  ('Kankan',         'Guinée',         '🇬🇳', 10.3854,  -9.3057, true, 2),
  ('Nzérékoré',      'Guinée',         '🇬🇳',  7.7562,  -8.8179, true, 3),
  ('Kindia',         'Guinée',         '🇬🇳', 10.0569, -12.8658, true, 4),
  ('Labé',           'Guinée',         '🇬🇳', 11.3182, -12.2833, true, 5),
  ('Lomé',           'Togo',           '🇹🇬',  6.1725,   1.2314, true, 1),
  ('Sokodé',         'Togo',           '🇹🇬',  8.9833,   1.1333, true, 2),
  ('Kara',           'Togo',           '🇹🇬',  9.5511,   1.1861, true, 3),
  ('Kpalimé',        'Togo',           '🇹🇬',  6.9000,   0.6333, true, 4),
  ('Atakpamé',       'Togo',           '🇹🇬',  7.5333,   1.1333, true, 5),
  ('Cotonou',        'Bénin',          '🇧🇯',  6.3703,   2.3912, true, 1),
  ('Porto-Novo',     'Bénin',          '🇧🇯',  6.4969,   2.6283, true, 2),
  ('Abomey-Calavi',  'Bénin',          '🇧🇯',  6.4485,   2.3557, true, 3),
  ('Parakou',        'Bénin',          '🇧🇯',  9.3372,   2.6303, true, 4),
  ('Djougou',        'Bénin',          '🇧🇯',  9.7085,   1.6660, true, 5),
  ('Niamey',         'Niger',          '🇳🇪', 13.5116,   2.1254, true, 1),
  ('Zinder',         'Niger',          '🇳🇪', 13.8072,   8.9881, true, 2),
  ('Maradi',         'Niger',          '🇳🇪', 13.5000,   7.1017, true, 3),
  ('Tahoua',         'Niger',          '🇳🇪', 14.8888,   5.2692, true, 4),
  ('Agadez',         'Niger',          '🇳🇪', 16.9733,   7.9911, true, 5),
  ('Accra',          'Ghana',          '🇬🇭',  5.6037,  -0.1870, true, 1),
  ('Kumasi',         'Ghana',          '🇬🇭',  6.6885,  -1.6244, true, 2),
  ('Tamale',         'Ghana',          '🇬🇭',  9.4008,  -0.8393, true, 3),
  ('Takoradi',       'Ghana',          '🇬🇭',  4.8845,  -1.7554, true, 4),
  ('Cape Coast',     'Ghana',          '🇬🇭',  5.1053,  -1.2466, true, 5),
  ('Lagos',          'Nigeria',        '🇳🇬',  6.5244,   3.3792, true, 1),
  ('Abuja',          'Nigeria',        '🇳🇬',  9.0765,   7.3986, true, 2),
  ('Port Harcourt',  'Nigeria',        '🇳🇬',  4.8156,   7.0498, true, 3),
  ('Ibadan',         'Nigeria',        '🇳🇬',  7.3775,   3.9470, true, 4),
  ('Enugu',          'Nigeria',        '🇳🇬',  6.4584,   7.5464, true, 5),
  ('Praia',          'Cap-Vert',       '🇨🇻', 14.9330, -23.5133, true, 1),
  ('Mindelo',        'Cap-Vert',       '🇨🇻', 16.8901, -24.9804, true, 2),
  -- ── Afrique centrale ──
  ('Douala',         'Cameroun',       '🇨🇲',  4.0511,   9.7679, true, 1),
  ('Yaoundé',        'Cameroun',       '🇨🇲',  3.8480,  11.5021, true, 2),
  ('Bafoussam',      'Cameroun',       '🇨🇲',  5.4778,  10.4176, true, 3),
  ('Bamenda',        'Cameroun',       '🇨🇲',  5.9631,  10.1591, true, 4),
  ('Garoua',         'Cameroun',       '🇨🇲',  9.3010,  13.3921, true, 5),
  ('Libreville',     'Gabon',          '🇬🇦',  0.4162,   9.4673, true, 1),
  ('Port-Gentil',    'Gabon',          '🇬🇦', -0.7193,   8.7815, true, 2),
  ('Franceville',    'Gabon',          '🇬🇦', -1.6333,  13.5833, true, 3),
  ('Oyem',           'Gabon',          '🇬🇦',  1.5995,  11.5793, true, 4),
  ('Moanda',         'Gabon',          '🇬🇦', -1.5667,  13.2000, true, 5),
  ('Brazzaville',    'Congo',          '🇨🇬', -4.2634,  15.2429, true, 1),
  ('Pointe-Noire',   'Congo',          '🇨🇬', -4.7761,  11.8635, true, 2),
  ('Dolisie',        'Congo',          '🇨🇬', -4.1990,  12.6666, true, 3),
  ('Nkayi',          'Congo',          '🇨🇬', -4.1833,  13.2833, true, 4),
  ('Ouesso',         'Congo',          '🇨🇬',  1.6136,  16.0517, true, 5),
  ('Kinshasa',       'RD Congo',       '🇨🇩', -4.4419,  15.2663, true, 1),
  ('Lubumbashi',     'RD Congo',       '🇨🇩',-11.6876,  27.5026, true, 2),
  ('Mbuji-Mayi',     'RD Congo',       '🇨🇩', -6.1360,  23.5898, true, 3),
  ('Kisangani',      'RD Congo',       '🇨🇩',  0.5153,  25.1910, true, 4),
  ('Goma',           'RD Congo',       '🇨🇩', -1.6585,  29.2205, true, 5),
  ('N''Djamena',     'Tchad',          '🇹🇩', 12.1348,  15.0557, true, 1),
  ('Moundou',        'Tchad',          '🇹🇩',  8.5667,  16.0833, true, 2),
  ('Abéché',         'Tchad',          '🇹🇩', 13.8292,  20.8324, true, 3),
  ('Sarh',           'Tchad',          '🇹🇩',  9.1429,  18.3923, true, 4),
  ('Kélo',           'Tchad',          '🇹🇩',  9.3086,  15.8066, true, 5),
  ('Bangui',         'Centrafrique',   '🇨🇫',  4.3947,  18.5582, true, 1),
  ('Bimbo',          'Centrafrique',   '🇨🇫',  4.2567,  18.4158, true, 2),
  ('Berbérati',      'Centrafrique',   '🇨🇫',  4.2612,  15.7922, true, 3),
  ('Bambari',        'Centrafrique',   '🇨🇫',  5.7679,  20.6757, true, 4),
  ('Bouar',          'Centrafrique',   '🇨🇫',  5.9340,  15.5960, true, 5),
  ('Malabo',         'Guinée équatoriale', '🇬🇶', 3.7504, 8.7371, true, 1),
  ('Bata',           'Guinée équatoriale', '🇬🇶', 1.8639, 9.7658, true, 2),
  -- ── Afrique de l'Est et australe ──
  ('Kigali',         'Rwanda',         '🇷🇼', -1.9441,  30.0619, true, 1),
  ('Huye',           'Rwanda',         '🇷🇼', -2.5967,  29.7394, true, 2),
  ('Rubavu',         'Rwanda',         '🇷🇼', -1.7022,  29.2564, true, 3),
  ('Musanze',        'Rwanda',         '🇷🇼', -1.4998,  29.6350, true, 4),
  ('Muhanga',        'Rwanda',         '🇷🇼', -2.0845,  29.7562, true, 5),
  ('Nairobi',        'Kenya',          '🇰🇪', -1.2921,  36.8219, true, 1),
  ('Mombasa',        'Kenya',          '🇰🇪', -4.0435,  39.6682, true, 2),
  ('Kisumu',         'Kenya',          '🇰🇪', -0.0917,  34.7680, true, 3),
  ('Nakuru',         'Kenya',          '🇰🇪', -0.3031,  36.0800, true, 4),
  ('Eldoret',        'Kenya',          '🇰🇪',  0.5143,  35.2698, true, 5),
  ('Addis-Abeba',    'Éthiopie',       '🇪🇹',  9.0300,  38.7400, true, 1),
  ('Dire Dawa',      'Éthiopie',       '🇪🇹',  9.6009,  41.8501, true, 2),
  ('Mekele',         'Éthiopie',       '🇪🇹', 13.4967,  39.4753, true, 3),
  ('Gondar',         'Éthiopie',       '🇪🇹', 12.6030,  37.4521, true, 4),
  ('Hawassa',        'Éthiopie',       '🇪🇹',  7.0621,  38.4764, true, 5),
  ('Lusaka',         'Zambie',         '🇿🇲',-15.3875,  28.3228, true, 1),
  ('Kitwe',          'Zambie',         '🇿🇲',-12.8024,  28.2132, true, 2),
  ('Ndola',          'Zambie',         '🇿🇲',-12.9587,  28.6366, true, 3),
  ('Livingstone',    'Zambie',         '🇿🇲',-17.8419,  25.8543, true, 4),
  ('Kabwe',          'Zambie',         '🇿🇲',-14.4469,  28.4464, true, 5),
  ('Luanda',         'Angola',         '🇦🇴', -8.8390,  13.2894, true, 1),
  ('Huambo',         'Angola',         '🇦🇴',-12.7761,  15.7392, true, 2),
  ('Lobito',         'Angola',         '🇦🇴',-12.3644,  13.5464, true, 3),
  ('Benguela',       'Angola',         '🇦🇴',-12.5763,  13.4055, true, 4),
  ('Lubango',        'Angola',         '🇦🇴',-14.9177,  13.4925, true, 5),
  ('Maputo',         'Mozambique',     '🇲🇿',-25.9692,  32.5732, true, 1),
  ('Matola',         'Mozambique',     '🇲🇿',-25.9622,  32.4589, true, 2),
  ('Beira',          'Mozambique',     '🇲🇿',-19.8436,  34.8389, true, 3),
  ('Nampula',        'Mozambique',     '🇲🇿',-15.1165,  39.2666, true, 4),
  ('Quelimane',      'Mozambique',     '🇲🇿',-17.8786,  36.8883, true, 5),
  ('Johannesburg',   'Afrique du Sud', '🇿🇦',-26.2041,  28.0473, true, 1),
  ('Le Cap',         'Afrique du Sud', '🇿🇦',-33.9249,  18.4241, true, 2),
  ('Durban',         'Afrique du Sud', '🇿🇦',-29.8587,  31.0218, true, 3),
  ('Pretoria',       'Afrique du Sud', '🇿🇦',-25.7479,  28.2293, true, 4),
  ('Gqeberha',       'Afrique du Sud', '🇿🇦',-33.9608,  25.6022, true, 5),
  ('Gaborone',       'Botswana',       '🇧🇼',-24.6282,  25.9231, true, 1),
  ('Francistown',    'Botswana',       '🇧🇼',-21.1700,  27.5072, true, 2),
  ('Windhoek',       'Namibie',        '🇳🇦',-22.5609,  17.0658, true, 1),
  ('Walvis Bay',     'Namibie',        '🇳🇦',-22.9576,  14.5053, true, 2),
  ('Antananarivo',   'Madagascar',     '🇲🇬',-18.8792,  47.5079, true, 1),
  ('Toamasina',      'Madagascar',     '🇲🇬',-18.1443,  49.3958, true, 2),
  ('Antsirabe',      'Madagascar',     '🇲🇬',-19.8659,  47.0333, true, 3),
  ('Mahajanga',      'Madagascar',     '🇲🇬',-15.7167,  46.3167, true, 4),
  ('Fianarantsoa',   'Madagascar',     '🇲🇬',-21.4536,  47.0858, true, 5),
  ('Port-Louis',     'Maurice',        '🇲🇺',-20.1609,  57.5012, true, 1),
  ('Curepipe',       'Maurice',        '🇲🇺',-20.3163,  57.5259, true, 2),
  ('Quatre Bornes',  'Maurice',        '🇲🇺',-20.2654,  57.4791, true, 3),
  ('Grand Baie',     'Maurice',        '🇲🇺',-20.0130,  57.5800, true, 4),
  ('Victoria',       'Seychelles',     '🇸🇨', -4.6191,  55.4513, true, 1),
  ('Tunis',          'Tunisie',        '🇹🇳', 36.8065,  10.1815, true, 1),
  ('Sfax',           'Tunisie',        '🇹🇳', 34.7406,  10.7603, true, 2),
  ('Sousse',         'Tunisie',        '🇹🇳', 35.8256,  10.6360, true, 3),
  ('Kairouan',       'Tunisie',        '🇹🇳', 35.6781,  10.0963, true, 4),
  ('Bizerte',        'Tunisie',        '🇹🇳', 37.2744,   9.8739, true, 5),
  -- ── Europe ──
  ('Paris',          'France',         '🇫🇷', 48.8566,   2.3522, true, 1),
  ('Marseille',      'France',         '🇫🇷', 43.2965,   5.3698, true, 2),
  ('Lyon',           'France',         '🇫🇷', 45.7640,   4.8357, true, 3),
  ('Toulouse',       'France',         '🇫🇷', 43.6047,   1.4442, true, 4),
  ('Lille',          'France',         '🇫🇷', 50.6292,   3.0573, true, 5),
  ('Pointe-à-Pitre', 'Outre-mer',      '🇫🇷', 16.2411, -61.5331, true, 1),
  ('Fort-de-France', 'Outre-mer',      '🇫🇷', 14.6161, -61.0588, true, 2),
  ('Saint-Denis (La Réunion)', 'Outre-mer', '🇫🇷', -20.8823, 55.4504, true, 3),
  ('Cayenne',        'Outre-mer',      '🇫🇷',  4.9224, -52.3135, true, 4),
  ('Bruxelles',      'Belgique',       '🇧🇪', 50.8503,   4.3517, true, 1),
  ('Anvers',         'Belgique',       '🇧🇪', 51.2194,   4.4025, true, 2),
  ('Liège',          'Belgique',       '🇧🇪', 50.6326,   5.5797, true, 3),
  ('Gand',           'Belgique',       '🇧🇪', 51.0543,   3.7174, true, 4),
  ('Charleroi',      'Belgique',       '🇧🇪', 50.4108,   4.4446, true, 5),
  ('Genève',         'Suisse',         '🇨🇭', 46.2044,   6.1432, true, 1),
  ('Zurich',         'Suisse',         '🇨🇭', 47.3769,   8.5417, true, 2),
  ('Lausanne',       'Suisse',         '🇨🇭', 46.5197,   6.6323, true, 3),
  ('Bâle',           'Suisse',         '🇨🇭', 47.5596,   7.5886, true, 4),
  ('Berne',          'Suisse',         '🇨🇭', 46.9480,   7.4474, true, 5),
  ('Luxembourg',     'Luxembourg',     '🇱🇺', 49.6116,   6.1319, true, 1),
  ('Londres',        'Royaume-Uni',    '🇬🇧', 51.5074,  -0.1278, true, 1),
  ('Manchester',     'Royaume-Uni',    '🇬🇧', 53.4808,  -2.2426, true, 2),
  ('Birmingham',     'Royaume-Uni',    '🇬🇧', 52.4862,  -1.8904, true, 3),
  ('Leeds',          'Royaume-Uni',    '🇬🇧', 53.8008,  -1.5491, true, 4),
  ('Glasgow',        'Royaume-Uni',    '🇬🇧', 55.8642,  -4.2518, true, 5),
  ('Dublin',         'Irlande',        '🇮🇪', 53.3498,  -6.2603, true, 1),
  ('Cork',           'Irlande',        '🇮🇪', 51.8985,  -8.4756, true, 2),
  ('Galway',         'Irlande',        '🇮🇪', 53.2707,  -9.0568, true, 3),
  ('Berlin',         'Allemagne',      '🇩🇪', 52.5200,  13.4050, true, 1),
  ('Hambourg',       'Allemagne',      '🇩🇪', 53.5511,   9.9937, true, 2),
  ('Munich',         'Allemagne',      '🇩🇪', 48.1351,  11.5820, true, 3),
  ('Cologne',        'Allemagne',      '🇩🇪', 50.9375,   6.9603, true, 4),
  ('Francfort',      'Allemagne',      '🇩🇪', 50.1109,   8.6821, true, 5),
  ('Rome',           'Italie',         '🇮🇹', 41.9028,  12.4964, true, 1),
  ('Milan',          'Italie',         '🇮🇹', 45.4642,   9.1900, true, 2),
  ('Naples',         'Italie',         '🇮🇹', 40.8518,  14.2681, true, 3),
  ('Turin',          'Italie',         '🇮🇹', 45.0703,   7.6869, true, 4),
  ('Bologne',        'Italie',         '🇮🇹', 44.4949,  11.3426, true, 5),
  ('Madrid',         'Espagne',        '🇪🇸', 40.4168,  -3.7038, true, 1),
  ('Barcelone',      'Espagne',        '🇪🇸', 41.3874,   2.1686, true, 2),
  ('Valence',        'Espagne',        '🇪🇸', 39.4699,  -0.3763, true, 3),
  ('Séville',        'Espagne',        '🇪🇸', 37.3891,  -5.9845, true, 4),
  ('Malaga',         'Espagne',        '🇪🇸', 36.7213,  -4.4214, true, 5),
  ('Lisbonne',       'Portugal',       '🇵🇹', 38.7223,  -9.1393, true, 1),
  ('Porto',          'Portugal',       '🇵🇹', 41.1579,  -8.6291, true, 2),
  ('Braga',          'Portugal',       '🇵🇹', 41.5454,  -8.4265, true, 3),
  ('Coimbra',        'Portugal',       '🇵🇹', 40.2033,  -8.4103, true, 4),
  ('Faro',           'Portugal',       '🇵🇹', 37.0194,  -7.9322, true, 5),
  ('Amsterdam',      'Pays-Bas',       '🇳🇱', 52.3676,   4.9041, true, 1),
  ('Rotterdam',      'Pays-Bas',       '🇳🇱', 51.9244,   4.4777, true, 2),
  ('La Haye',        'Pays-Bas',       '🇳🇱', 52.0705,   4.3007, true, 3),
  ('Utrecht',        'Pays-Bas',       '🇳🇱', 52.0907,   5.1214, true, 4),
  ('Eindhoven',      'Pays-Bas',       '🇳🇱', 51.4416,   5.4697, true, 5),
  ('Varsovie',       'Pologne',        '🇵🇱', 52.2297,  21.0122, true, 1),
  ('Cracovie',       'Pologne',        '🇵🇱', 50.0647,  19.9450, true, 2),
  ('Wrocław',        'Pologne',        '🇵🇱', 51.1079,  17.0385, true, 3),
  ('Gdańsk',         'Pologne',        '🇵🇱', 54.3520,  18.6466, true, 4),
  ('Łódź',           'Pologne',        '🇵🇱', 51.7592,  19.4560, true, 5),
  ('Vienne',         'Autriche',       '🇦🇹', 48.2082,  16.3738, true, 1),
  ('Graz',           'Autriche',       '🇦🇹', 47.0707,  15.4395, true, 2),
  ('Linz',           'Autriche',       '🇦🇹', 48.3069,  14.2858, true, 3),
  ('Copenhague',     'Danemark',       '🇩🇰', 55.6761,  12.5683, true, 1),
  ('Aarhus',         'Danemark',       '🇩🇰', 56.1629,  10.2039, true, 2),
  ('Odense',         'Danemark',       '🇩🇰', 55.4038,  10.4024, true, 3),
  ('Stockholm',      'Suède',          '🇸🇪', 59.3293,  18.0686, true, 1),
  ('Göteborg',       'Suède',          '🇸🇪', 57.7089,  11.9746, true, 2),
  ('Malmö',          'Suède',          '🇸🇪', 55.6050,  13.0038, true, 3),
  ('Oslo',           'Norvège',        '🇳🇴', 59.9139,  10.7522, true, 1),
  ('Bergen',         'Norvège',        '🇳🇴', 60.3913,   5.3221, true, 2),
  ('Helsinki',       'Finlande',       '🇫🇮', 60.1699,  24.9384, true, 1),
  ('Tampere',        'Finlande',       '🇫🇮', 61.4978,  23.7610, true, 2),
  -- ── Amériques ──
  ('Montréal',       'Canada',         '🇨🇦', 45.5017, -73.5673, true, 1),
  ('Toronto',        'Canada',         '🇨🇦', 43.6532, -79.3832, true, 2),
  ('Ottawa',         'Canada',         '🇨🇦', 45.4215, -75.6972, true, 3),
  ('Québec',         'Canada',         '🇨🇦', 46.8139, -71.2080, true, 4),
  ('Vancouver',      'Canada',         '🇨🇦', 49.2827,-123.1207, true, 5),
  ('New York',       'États-Unis',     '🇺🇸', 40.7128, -74.0060, true, 1),
  ('Los Angeles',    'États-Unis',     '🇺🇸', 34.0522,-118.2437, true, 2),
  ('Chicago',        'États-Unis',     '🇺🇸', 41.8781, -87.6298, true, 3),
  ('Houston',        'États-Unis',     '🇺🇸', 29.7604, -95.3698, true, 4),
  ('Atlanta',        'États-Unis',     '🇺🇸', 33.7490, -84.3880, true, 5),
  ('Port-au-Prince', 'Haïti',          '🇭🇹', 18.5944, -72.3074, true, 1),
  ('Cap-Haïtien',    'Haïti',          '🇭🇹', 19.7579, -72.2042, true, 2),
  ('São Paulo',      'Brésil',         '🇧🇷',-23.5505, -46.6333, true, 1),
  ('Rio de Janeiro', 'Brésil',         '🇧🇷',-22.9068, -43.1729, true, 2),
  ('Brasília',       'Brésil',         '🇧🇷',-15.7975, -47.8919, true, 3),
  ('Salvador',       'Brésil',         '🇧🇷',-12.9777, -38.5016, true, 4),
  ('Belo Horizonte', 'Brésil',         '🇧🇷',-19.9167, -43.9345, true, 5),
  ('Mexico',         'Mexique',        '🇲🇽', 19.4326, -99.1332, true, 1),
  ('Guadalajara',    'Mexique',        '🇲🇽', 20.6597,-103.3496, true, 2),
  ('Monterrey',      'Mexique',        '🇲🇽', 25.6866,-100.3161, true, 3),
  ('Puebla',         'Mexique',        '🇲🇽', 19.0414, -98.2063, true, 4),
  ('Cancún',         'Mexique',        '🇲🇽', 21.1619, -86.8515, true, 5),
  ('Bogotá',         'Colombie',       '🇨🇴',  4.7110, -74.0721, true, 1),
  ('Medellín',       'Colombie',       '🇨🇴',  6.2442, -75.5812, true, 2),
  ('Cali',           'Colombie',       '🇨🇴',  3.4516, -76.5320, true, 3),
  ('Barranquilla',   'Colombie',       '🇨🇴', 10.9685, -74.7813, true, 4),
  ('Carthagène',     'Colombie',       '🇨🇴', 10.3910, -75.4794, true, 5),
  ('Buenos Aires',   'Argentine',      '🇦🇷',-34.6037, -58.3816, true, 1),
  ('Córdoba',        'Argentine',      '🇦🇷',-31.4201, -64.1888, true, 2),
  ('Rosario',        'Argentine',      '🇦🇷',-32.9442, -60.6505, true, 3),
  ('Mendoza',        'Argentine',      '🇦🇷',-32.8895, -68.8458, true, 4),
  ('La Plata',       'Argentine',      '🇦🇷',-34.9205, -57.9536, true, 5),
  ('Santiago',       'Chili',          '🇨🇱',-33.4489, -70.6693, true, 1),
  ('Valparaíso',     'Chili',          '🇨🇱',-33.0472, -71.6127, true, 2),
  ('Concepción',     'Chili',          '🇨🇱',-36.8270, -73.0503, true, 3),
  ('Lima',           'Pérou',          '🇵🇪',-12.0464, -77.0428, true, 1),
  ('Arequipa',       'Pérou',          '🇵🇪',-16.4090, -71.5375, true, 2),
  ('Trujillo',       'Pérou',          '🇵🇪', -8.1091, -79.0215, true, 3),
  -- ── Asie et Océanie ──
  ('Sydney',         'Australie',      '🇦🇺',-33.8688, 151.2093, true, 1),
  ('Melbourne',      'Australie',      '🇦🇺',-37.8136, 144.9631, true, 2),
  ('Brisbane',       'Australie',      '🇦🇺',-27.4698, 153.0251, true, 3),
  ('Perth',          'Australie',      '🇦🇺',-31.9505, 115.8605, true, 4),
  ('Adélaïde',       'Australie',      '🇦🇺',-34.9285, 138.6007, true, 5),
  ('Auckland',       'Nouvelle-Zélande','🇳🇿',-36.8485, 174.7633, true, 1),
  ('Wellington',     'Nouvelle-Zélande','🇳🇿',-41.2865, 174.7762, true, 2),
  ('Tokyo',          'Japon',          '🇯🇵', 35.6762, 139.6503, true, 1),
  ('Osaka',          'Japon',          '🇯🇵', 34.6937, 135.5023, true, 2),
  ('Séoul',          'Corée du Sud',   '🇰🇷', 37.5665, 126.9780, true, 1),
  ('Bangkok',        'Thaïlande',      '🇹🇭', 13.7563, 100.5018, true, 1),
  ('Manille',        'Philippines',    '🇵🇭', 14.5995, 120.9842, true, 1),
  ('Hô Chi Minh-Ville','Viêt Nam',     '🇻🇳', 10.8231, 106.6297, true, 1),
  ('Hanoï',          'Viêt Nam',       '🇻🇳', 21.0278, 105.8342, true, 2),
  ('Mumbai',         'Inde',           '🇮🇳', 19.0760,  72.8777, true, 1),
  ('Delhi',          'Inde',           '🇮🇳', 28.7041,  77.1025, true, 2),
  ('Bangalore',      'Inde',           '🇮🇳', 12.9716,  77.5946, true, 3)
ON CONFLICT (nom, pays) DO UPDATE
  SET drapeau = EXCLUDED.drapeau, lat = EXCLUDED.lat, lng = EXCLUDED.lng,
      actif = true, ordre = EXCLUDED.ordre;

-- ─── Ordre de la liste ──────────────────────────────────────────────
-- 1. le pays de la ville la plus proche du membre (son pays)
-- 2. les pays qui ont le plus de profils
-- 3. l'ordre des villes dans le pays
CREATE OR REPLACE FUNCTION public.villes_voyage_disponibles()
RETURNS TABLE (
  nom text, pays text, drapeau text,
  lat double precision, lng double precision, nb_profils bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH moi AS (
    SELECT latitude AS la, longitude AS lo FROM profiles WHERE id = auth.uid()
  ),
  mon_pays AS (
    SELECT v.pays FROM villes_voyage v, moi
     WHERE v.actif AND moi.la IS NOT NULL AND moi.lo IS NOT NULL
     ORDER BY public._distance_km(v.lat, v.lng, moi.la, moi.lo)
     LIMIT 1
  ),
  villes AS (
    SELECT v.nom, v.pays, v.drapeau, v.lat, v.lng, v.ordre,
      (SELECT count(*) FROM profiles p
       WHERE p.latitude IS NOT NULL AND p.longitude IS NOT NULL
         AND p.id IS DISTINCT FROM auth.uid()
         AND NOT COALESCE((to_jsonb(p)->>'is_suspended')::boolean, false)
         -- boîte rapide (~30 km) puis distance exacte
         AND p.latitude BETWEEN v.lat - 0.3 AND v.lat + 0.3
         AND p.longitude BETWEEN v.lng - 0.3 AND v.lng + 0.3
         AND public._distance_km(v.lat, v.lng, p.latitude, p.longitude) <= 30
      ) AS nb
    FROM villes_voyage v
    WHERE v.actif
  ),
  par_pays AS (
    SELECT pays, sum(nb) AS total FROM villes GROUP BY pays
  )
  SELECT v.nom, v.pays, v.drapeau, v.lat, v.lng, v.nb
    FROM villes v
    JOIN par_pays pp ON pp.pays = v.pays
   ORDER BY (v.pays = (SELECT pays FROM mon_pays)) DESC NULLS LAST,
            pp.total DESC, v.pays, v.ordre, v.nom;
$$;
REVOKE ALL ON FUNCTION public.villes_voyage_disponibles() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.villes_voyage_disponibles() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
