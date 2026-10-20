# Chantier « Version iPhone » — état de préparation

*Rédigé le 15/10/2026. Objectif : lancer dès l'inscription au programme Apple Developer.*

---

## 1. Déjà prêt dans le projet ✅

| Élément | Où | État |
|---|---|---|
| Code Flutter commun | `lib/` | Le même code tourne sur iPhone |
| Identifiant de l'app | `ios/Runner.xcodeproj` | `com.vybestyle.zamu` (identique à Android) |
| Firebase iOS | `ios/Runner/GoogleService-Info.plist` | Présent |
| Autorisations iOS | `ios/Runner/Info.plist` | Caméra, micro, photos (lecture + ajout), localisation « pendant l'utilisation » |
| Notifications en arrière-plan | `Info.plist` → `UIBackgroundModes` | `fetch`, `remote-notification` |
| Droits (entitlements) | `ios/Runner/Runner.entitlements` | Notifications push (`aps-environment`), Connexion avec Apple |
| Connexion Google sur iOS | `Info.plist` → `CFBundleURLSchemes` | Schéma `com.googleusercontent.apps…` présent |
| **Connexion avec Apple** | `auth_controller.dart` → `signInWithApple()` | Code déjà écrit (paquet `sign_in_with_apple`) — **obligatoire chez Apple** puisqu'on propose Google |
| Version minimale | `ios/Podfile` | iOS 15.5 (exigé par ML Kit, 20/10/2026) |
| Construction sans Mac | `codemagic.yaml` → workflow `ios-verification` | Compile l'app iPhone **sans signature** (vérifie que tout compile) |
| RevenueCat | `revenue_cat_service.dart` | Choix automatique de la clé selon la plateforme ; constante `kRevenueCatIosApiKey` prête (vide) |
| Identifiant d'appareil (bannissement) | `appareil_service.dart` | Protégé : ne s'exécute que sur Android (`Platform.isAndroid`) |

---

## 2. À faire AVANT le compte Apple (possible maintenant, sans payer)

- [x] **Liens `zamu://profil/...`** (20/10/2026) : schéma `zamu` ajouté dans `Info.plist` et canal `zamu/liens` dans `AppDelegate.swift` (même contrat qu'Android : `initial` puis `lien`). À vérifier sur TestFlight. Penser aussi à la page web `p.html` : sur iPhone, renvoyer vers l'App Store au lieu du Play Store quand l'app n'est pas installée.
- [x] **Découpe vidéo des stories** (20/10/2026) : canal `zamu/video` dans `AppDelegate.swift` (AVAssetExportSession « passthrough », sans réencodage). Sans lui, la vidéo entière était envoyée (le lecteur ne jouait que le passage choisi).
- [x] Appels aux canaux natifs protégés : `liens_profil.dart` (`try/catch` → pas de plantage, les liens ne marchent simplement pas encore sur iPhone) et `appareil_service.dart` (`Platform.isAndroid`). Vérifié le 15/10/2026.
- [ ] **Captures d'écran** : Android les bloque (`FLAG_SECURE` dans `MainActivity.kt`). iOS ne permet pas de bloquer une capture ; on peut **masquer l'app dans le sélecteur d'applis** (vue floutée dans `AppDelegate` quand l'app passe en arrière-plan) et **détecter** une capture (`UIApplication.userDidTakeScreenshotNotification`) pour prévenir l'autre personne (comme Snapchat).
- [ ] Préparer les **textes et captures App Store** (FR + EN), l'**icône 1024×1024** sans transparence, la **politique de confidentialité** (déjà en ligne) et les **« étiquettes de confidentialité »** Apple (équivalent de la Sécurité des données Google).
- [ ] Lancer le workflow Codemagic `ios-verification` pour confirmer que tout compile.
- [ ] L'utilisateur : créer son **identifiant Apple** (nom exact de la pièce d'identité) avec la **validation en deux étapes**.

---

## 3. Le jour de l'inscription Apple Developer (99 $/an)

1. **Inscription** au programme (vérification d'identité : quelques jours).
2. **App Store Connect** : créer l'app `com.vybestyle.zamu`, nom « Zamu », catégorie *Rencontres*, classification **17+**.
3. **Clé push APNs** (fichier `.p8`) : la créer chez Apple, l'ajouter dans **Firebase → Paramètres → Cloud Messaging** (sans ça, aucune notification sur iPhone).
4. **Connexion avec Apple dans Supabase** : Authentication → Providers → Apple (Services ID, clé, Team ID).
5. **Achats intégrés** dans App Store Connect : recréer les abonnements (`weekly2`, `monthly`, `quarterly`, `yearly`) et les Boosts (`boost_1h`, `boost_2h`, `boost_24h`) avec les mêmes durées ; prix par pays.
6. **RevenueCat** : ajouter l'app iOS, relier les produits à l'entitlement `zamu_premium` et aux offres `premium_v2` / `boosts`, copier la clé `appl_…` dans `kRevenueCatIosApiKey`.
7. **Webhook RevenueCat** (`swift-service`) : rien à changer, il reçoit aussi les événements iOS.
8. **Codemagic** : ajouter un workflow `ios-testflight` (signature automatique + envoi sur TestFlight).
9. **TestFlight** : tester sur un vrai iPhone (inscription, Google, Apple, photos, notifications, achat en mode test, stories, appels de canaux natifs).
10. **Envoi pour examen** : compte de test pour Apple (comme `test.zamu@gmail.com`), notes expliquant la modération, le signalement, le blocage et la suppression de compte (Apple est strict sur les applis de rencontre).

---

## 4. Points de vigilance spécifiques à Apple

- **Connexion avec Apple obligatoire** (déjà codée) — le bouton doit être aussi visible que Google.
- **Suppression de compte** depuis l'app : déjà présente (fonction `delete-account`).
- **Contenu généré par les utilisateurs** : signalement, blocage, modération, conditions d'utilisation acceptées → déjà en place ; à rappeler dans les notes d'examen.
- **Achats** : tout achat numérique doit passer par Apple (pas de lien vers un paiement externe) — même règle que Google, déjà respectée.
- **Photos sensibles** (chantier futur, voir notes groupes privés) : Apple est **plus strict que Google** ; prévoir de désactiver cette option sur iOS si l'examen la refuse.

---

## 5. Estimation

- Préparation sans compte (section 2) : 2 à 3 jours de travail.
- Après l'inscription (section 3) : 1 à 2 semaines (configuration, tests TestFlight), puis l'examen Apple (quelques jours, parfois plusieurs allers-retours).
