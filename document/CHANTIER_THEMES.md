# Chantier « Thèmes » — notes de préparation

*Rédigé le 15/10/2026. À démarrer après le gel des nouveautés (début décembre 2026).*
*Référence visuelle : Snapchat → Paramètres → « Thèmes de l'application ».*

---

## 1. Objectif

Faire des thèmes un **vrai point fort de Zamu** :
- personnalisation forte (l'utilisateur se sent « chez lui ») ;
- **événements marketing** (« Nouveau thème Saint-Valentin 💘 disponible ! ») ;
- **argument Premium** (certains thèmes réservés aux abonnés).

---

## 2. Ce qui existe déjà (les bases sont solides)

| Élément | Fichier | Rôle |
|---|---|---|
| `AppPalette` | `lib/core/theme/app_palette.dart` | Une palette = `id`, `label`, 12 couleurs (bg, surface, surface2, border, accent, accent2, accent3, yellow, textPrimary, textMuted, online, error), `clair` (fond clair ou non), dégradés `gradientPink` / `gradientFull`, `barreSysteme` |
| Palettes proposées | `AppPalettes.all` | Zamu (défaut), Minuit, Graphite, Saphir, Émeraude, Champagne |
| Palette en préparation | `AppPalettes.enPreparation` | « Blanc » (fond blanc, boutons noirs) — non proposée |
| Anciens thèmes | `AppPalettes.resoudre` + `_anciens` | Redirige les anciens thèmes néon vers les nouveaux |
| `ThemeController` | `lib/core/theme/theme_controller.dart` | Palette réactive ; enregistrée dans GetStorage (`app_theme_id`) **et** dans `profiles.theme` (suit l'utilisateur d'un téléphone à l'autre) ; `applyRemote` ; `Get.forceAppUpdate()` pour tout redessiner sans redémarrer |
| `AppColors` | `lib/core/theme/app_theme.dart` | Les écrans lisent les couleurs ici (getters vers la palette) + couleurs **par rôle** : `surAccent`, `surMedia`, `voileMedia`, `barreSysteme` |
| `AppTheme.buildFrom(palette)` | `app_theme.dart` | Construit le thème Flutter (clair/sombre, ColorScheme, barre d'état) |
| Choix du thème | `lib/features/profil/vue/ecran_parametres.dart` (≈ ligne 708) | Liste des palettes dans les Paramètres |
| Test de lisibilité | `test/theme_test.dart` | Vérifie le contraste de chaque palette |
| Outil | `tool/fix_const_theme.dart` | Retire les `const` devenus invalides (couleurs lues à l'exécution) |
| Statistiques | Panneau admin → « Versions & thèmes » | Répartition des thèmes utilisés |

**Points d'attention connus**
- Environ **327** `Colors.white` / `Colors.black` restent dans `lib/` : à remplacer par les couleurs par rôle avant d'ouvrir le fond clair (règle dans `CLAUDE.md`).
- Les écrans plein écran photo/vidéo (lecteur de stories, caméra) restent noirs dans tous les thèmes : c'est voulu.

---

## 3. Ce que fait Snapchat (observé le 15/10/2026)

1. **Trois modes de base** : *Système* (suit le téléphone), *Clair*, *Sombre*.
2. **Thèmes unis** avec un nom évocateur : ex. « Cerise noire » = fond bordeaux presque noir + accent fuchsia (très proche de l'identité Zamu).
3. **Thèmes illustrés** : un **fond dessiné** derrière les listes (« Champ de citrouilles », « Zone de fraîcheur » = eau de piscine, « Lettre d'amour » = motifs roses) + **couleur d'accent assortie** (boutons, bouton +, compteurs) + une **petite illustration** en haut.
4. **Aperçu en direct** : une fausse liste de conversations se met à jour quand on touche un rond ; rien n'est appliqué avant « Appliquer le thème ».
5. **Thèmes de saison** (Halloween…) qui reviennent à certaines périodes.

---

## 4. Ce qu'on veut pour Zamu (par étapes)

### Étape 1 — Modes Clair / Sombre / Système
- Finir le **fond blanc** (palette `blanc`) : remplacer les `Colors.white/black` restants, vérifier chaque écran.
- Ajouter un réglage **Apparence : Système / Clair / Sombre**, indépendant de la couleur choisie.
  - Idée de modèle : séparer **la couleur d'accent** (Zamu, Saphir, Émeraude…) et **la luminosité** (clair / sombre). Chaque palette aurait une variante claire et une variante sombre.
  - « Système » écoute `MediaQuery.platformBrightness` / `WidgetsBindingObserver.didChangePlatformBrightness`.

### Étape 2 — Écran de choix avec aperçu
- Nouvel écran « Thèmes » (au lieu d'une simple liste dans les Paramètres) :
  - **aperçu en direct** d'un faux Accueil / fausse liste de messages avec la palette sélectionnée (sans l'appliquer) ;
  - ronds de couleur défilants + nom du thème ;
  - bouton « Appliquer ».
- Technique : rendre l'aperçu à partir d'une `AppPalette` passée en paramètre (ne pas passer par `ThemeController` tant que ce n'est pas appliqué).

### Étape 3 — Noms évocateurs
- Renommer les `label` (en gardant les `id` pour la compatibilité) : ex. « Nuit d'Abidjan », « Cerise noire », « Lagune », « Coucher de soleil », « Saphir », « Émeraude ».
- Traductions anglaises dans `traductions.dart`.

### Étape 4 — Thèmes illustrés et de saison
- Ajouter à `AppPalette` (champs facultatifs, rétrocompatibles) :
  - `fondImage` (asset ou URL) + opacité ;
  - `illustration` (petite image en haut de l'Accueil / des Messages) ;
  - `disponibleDu` / `disponibleAu` (thème de saison) ;
  - `premium` (bool).
- Les thèmes de saison pourraient être **pilotés depuis le panneau admin** (table `themes` dans Supabase) pour les activer sans nouvelle version.
- Calendrier possible : Saint-Valentin (février), Fête des mères, Été, Halloween, Fêtes de fin d'année.

### Étape 5 — Premium
- Thèmes marqués `premium` : visibles pour tous en aperçu, appliquables seulement avec Premium (ou pendant un Boost / les 48 h offertes).
- Le choix est conservé si l'abonnement expire ? → décision à prendre (Snapchat+ revient au thème par défaut).

---

## 5. Règles à respecter (dès maintenant, pour tout nouveau code)

- Jamais `Colors.white` / `Colors.black` pour un texte ou une icône posé sur le **fond** : utiliser `AppColors.textPrimary` / `textMuted` / `surface`…
- Couleurs fixes seulement par **rôle** : `AppColors.surMedia` (texte sur photo/vidéo), `AppColors.surAccent` (texte sur bouton accent/dégradé), `AppColors.voileMedia`, `AppColors.barreSysteme`.
- Chaque nouvelle palette doit passer `test/theme_test.dart` (contraste).
- Toujours garder les anciens `id` résolubles (`resoudre` / `_anciens`) : un utilisateur ne doit jamais perdre son thème après une mise à jour.

---

## 6. Questions à trancher au démarrage

1. Combien de thèmes au lancement (6 unis + 2 illustrés ?) ?
2. Lesquels réservés au Premium ?
3. Thèmes de saison : pilotés depuis le panneau admin ou intégrés à l'app ?
4. Que devient un thème Premium quand l'abonnement s'arrête ?

---

## 7. Avancement (16/10/2026, branche `chantier-themes`)

Décision : **tous les thèmes sont gratuits** (pas de Premium).

- ✅ Étape 2 : `lib/features/profil/vue/ecran_themes.dart` (aperçu en direct, sections Classiques / Illustrés / De saison, bouton Appliquer) ; entrée « Thèmes » dans les Paramètres.
- ✅ Étape 3 : Minuit → « Cerise noire », Graphite → « Indigo » (id inchangés) + traductions.
- ✅ Étape 4 : `Motif` + `emoji` + `saisonDebut/saisonFin` dans `AppPalette` ; thèmes Lettre d'amour, Lagune, Nuit étoilée, Halloween (15/10–5/11), Fêtes (1/12–6/1) ; motif dessiné en code (`lib/core/theme/fond_theme.dart`, `FondTheme`) derrière Messages et Likes.
- 🟡 Étape 1 (bases) : `ThemeController.choix` (couleur choisie) / `apparence` (Système / Sombre / Clair) / `palette` (affichée). Réglage « Apparence (test) » visible **en debug seulement**. Messages et Accueil déjà corrects en clair.
- Reste pour l'étape 1 : passer chaque écran en clair (≈ 50 `Colors.white/black` hors écrans photo/vidéo, qui restent noirs : story_screen, discover_feed_viewer, caméra…) ; variante claire de chaque couleur (aujourd'hui le clair = palette « Blanc » unique, l'aperçu montre encore la couleur sombre) ; puis retirer `kDebugMode` du réglage.
