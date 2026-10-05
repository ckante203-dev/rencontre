# Suivi Zamu — à faire au retour

Mis à jour le 04/10/2026.

**Fait le 30/09 :** scripts `000010`, `000011` et `000012` appliqués ; fonction `moderate-image` déployée (clés Sightengine vérifiées).

**Fait le 30/09 :** script `000014` appliqué (sourdine par conversation, signalement des messages) et `smooth-action` redéployée.

**Version avancée (test interne, pas en production) — 02/10 :** formules Premium semaine / 1 mois / 3 mois / 12 mois (offre RevenueCat `premium_v2`) et Boost 1h / 2h / 24h (produits `boost_1h`, `boost_2h`, `boost_24h`, offre RevenueCat `boosts`). L'offre RevenueCat « default » reste inchangée pour la 1.0.11. **Configuré le 02/10 :** script `20261002000015_boost.sql` appliqué (vérifié) ; Play Console : offres de base `monthly` (1 990), `quarterly` (4 990), `yearly` (14 900) actives + 3 produits Boost (300 / 500 / 1 500) ; RevenueCat : produits importés, `monthly`/`quarterly`/`yearly` rattachés à `zamu_premium`, offres `premium_v2` (4 formules) et `boosts` (3 packages) créées. Webhook `swift-service` déjà redéployé (gère les Boosts). **Reste :** tester en test interne (4 formules affichées, achat d'un Boost puis rachat, profil mis en avant, webhook 200).

**Prochaine session :** fonction « Offrir Premium à quelqu'un ». Piste : produit Google Play **non renouvelable** (pass 1 semaine / 1 mois, acheté par celui qui offre), puis une fonction serveur qui accorde le Premium au destinataire (droit promotionnel RevenueCat ou date de fin Premium dans Supabase), avec une notification « X t'a offert Premium ». Prix Premium actuel : **650 FCFA / semaine** (offre `weekly2`, voulu). Premier vrai paiement validé le 01/10 (test interne 1.0.12). Prochaine version : 1.0.14 (correctif prix « / semaine »).

**Play Store :** version 1.0.11 (2021) envoyée pour examen le 30/09, Côte d'Ivoire uniquement (choix de lancement). Pages légales (confidentialité, suppression de compte) sur GitHub Pages et déclarées dans la Play Console. Si rien au bout de 7 jours : Play Console > Aide > Contacter l'assistance.

**Modération des photos (Sightengine, offre gratuite : 2 000 photos/mois, 500/jour) :** clés enregistrées sur le serveur le 30/09.
- Plus tard, quand presque tout le monde a la nouvelle version : `20260930000013_moderation_verrouillage.sql` (empêche de contourner la modération).
- Photos « pending » (douteuses) : cachées, à valider (requêtes en tête du script 000012, en attendant le panneau admin).
- Photos « unchecked » : publiées sans analyse (quota dépassé, vidéos) — à contrôler de temps en temps. Les signalements de stories arrivent dans la table `reports` avec `story_id` rempli : les traiter vite, la story et son fichier sont purgés à l'expiration.

**État :** tous les scripts SQL (000000 à 000009) sont appliqués ; toutes les fonctions serveur sont déployées (notifications testées OK le 29/09) ; commit `7723aed`. Restent les points 4 et 5.

## 0. Prochaine version — Google Play (préparé le 04/10)

**Nouveautés de la version (test interne d'abord, la production reste en 1.0.11) :** recherche @pseudo + QR code, « Dispo maintenant », relances de 19 h, stories Amis proches / Amis / Masquer à, caméra Zamu (photo, vidéo, selfie miroir), stickers / emoji / GIF / textes sur les stories, événements (J'y vais / Intéressé / sur place / stories / propositions / rappels), discussions de groupe, système d'amis + compte privé, cloche 🔔 sur l'Accueil, bulles de messages, thèmes pro (Zamu par défaut).

**Scripts SQL appliqués le 04/10 :** `027` à `038` (vérifiés depuis l'app). **Fonctions déployées :** `relance-quotidienne`, `rappel-evenements`, `groupe-message`, `dynamic-processor` (types ami_demande / ami_accepte), `moderate-image` (kind « groupe »).

**Conformité Google Play — déjà fait dans l'app (commit `1adda79`) :**
- plus de permission « toutes les photos / vidéos » (`READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` retirées : sélecteur de photos Android) ;
- plus de services de premier plan typés (geolocator « location », awesome_notifications « phoneCall » retirés) ;
- groupes : signaler un message, bloquer, photos analysées par la modération ;
- permissions restantes : caméra, micro, position, notifications, facturation ; cible Android 36.

### À faire — pages légales (maintenant)
- [x] Politique de confidentialité à jour en ligne (4 octobre 2026).
- [ ] Conditions d'utilisation : renvoyer `legal/conditions-utilisation.html` sur le dépôt GitHub `zamu-legal` (en ligne : encore la version du 30 septembre).

### À faire — Play Console, LE JOUR où on envoie la nouvelle version (même en test interne)
1. **Contenu de l'appli → Sécurité des données** : ajouter
   - photos et vidéos : photos des discussions de groupe et de l'album privé ;
   - messages : messages de groupe ;
   - position : approximative et précise, pour les fonctionnalités de l'app (profils / événements proches, « Je suis sur place ») ;
   - contacts / relations : liste d'amis, groupes.
2. **Classification du contenu** : refaire le questionnaire → les utilisateurs peuvent échanger du contenu, partager leur position.
3. **Suppression des comptes** : vérifier le lien `https://supportsnapmeet-jpg.github.io/zamu-legal/suppression-compte.html`.
4. Version : passer le numéro dans `pubspec.yaml` (déjà fait : `1.1.0+10100`), `flutter build appbundle`, envoyer en **test interne**.

### À faire — Prix des Boosts (Play Console, quand tu veux : pas besoin de nouvelle version)
Monétiser avec Play → Produits → Produits ponctuels (ou « Produits intégrés ») → chaque produit → Prix → Côte d'Ivoire (XOF), convertir pour les autres pays, Enregistrer, produit Actif :
- [ ] `boost_1h` → **1 000 FCFA**
- [ ] `boost_2h` → **1 500 FCFA**
- [ ] `boost_24h` → **5 000 FCFA**
Vérifier ensuite dans l'app (Accueil → ⚡). Suivre les ventes 2–3 semaines dans RevenueCat avant d'ajuster.
- [x] Exécuter le script SQL `20261005000041_bilan_boost.sql` (bilan du Boost + notification de fin).
- [x] Puis `20261005000042_boost_offert_premium.sql` (1 Boost d'1 h offert par mois aux Premium).
- [x] Puis `20261005000043_boost_droits_premium.sql` (Boost en cours = droits Premium : qui m'a liké / vu, proposer un événement).
- [x] Puis `20261005000044_croises_evenement.sql` (« Tu as croisé… » le lendemain d'un événement ; rappel-evenements déjà déployé).
- [x] Puis `20261005000045_notifications_lues.sql` (cloche : tout est « vu » à l'ouverture, historique 30 jours).
- [x] Puis `20261005000046_notifications_24h.sql` (notification supprimée 24 h après avoir été vue, tâche pg_cron horaire).
- [x] Puis `20261006000047_positions_arrondies.sql` (sécurité : positions arrondies à ~500 m en base ; la requête de vérification en fin de script doit donner 0).

### À faire — APRÈS la mise en production de la nouvelle version (quand la 1.0.11 n'existe plus nulle part)
- **Contenu de l'appli → Autorisations photos et vidéos** : déclarer que l'app n'utilise plus `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (ne pas le faire avant : la 1.0.11 les utilise encore).

### À vérifier (tests à deux téléphones)
- [ ] Notification de demande d'ami (non reçue au 1er test) → si rien : requête `net._http_response` (voir §2).
- [ ] Groupes : messages, photos, notifications « 👥 », signaler / bloquer.
- [ ] Événements : J'y vais / Intéressé, « Je suis sur place », discussion du groupe, rappels (veille / 2 h avant).
- [ ] Relances de 19 h : `SELECT * FROM cron.job_run_details WHERE jobid = 2 ORDER BY start_time DESC LIMIT 3;`
- [ ] Stories « Amis » / « Proches » / « Masquer à » vues depuis un autre compte.
- [ ] 2 photos de profil cassées (comptes `9195fd31…`, `f67ed1c9…`) et le « 1 non lu » mystère.

### Plus tard
- Mode clair (fond blanc) : chantier dédié après la sortie.
- Écran « Nouveautés » affiché une fois après la mise à jour.
- **Offrir Premium** (après la sortie de la 1.1.0) : produits Play Console à paiement unique « Offrir 1 semaine / 1 mois » (pas l'abonnement : non transférable), le serveur crédite les jours au destinataire (comme le Boost), notification « 🎁 X t'a offert Premium » + message dans la discussion, bouton « Offrir » sur le profil et la discussion. Paiement Google Play / RevenueCat uniquement.
- Parrainage (jours de Premium offerts).

## 1. Vérifier quels scripts SQL sont déjà passés

Colle cette requête dans le SQL Editor. Chaque ligne dit `oui` si le script correspondant est déjà appliqué.

```sql
SELECT '000001 connexion par nom d''utilisateur' AS script,
       EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'profiles_select_anon_login') AS applique
UNION ALL SELECT '000002 réponse aux stories',
       NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname = 'conversations_insert'
                   AND with_check ILIKE '%request_status%')
UNION ALL SELECT '000003 table matches + likes de story',
       EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'set_story_like')
UNION ALL SELECT '000004 read_at (messages éphémères)',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'messages' AND column_name = 'read_at')
UNION ALL SELECT '000005 purge automatique (cron)',
       EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-expired')
UNION ALL SELECT '000006 colonnes de la carte',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'map_visible')
UNION ALL SELECT '000007 préférences des Paramètres',
       EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'notif_son')
UNION ALL SELECT '000008 protections Premium',
       EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'qui_m_a_like');
```

Pour chaque ligne à `false`, ouvre le fichier `supabase/migrations/2026092…_<nom>.sql` correspondant, copie **tout** le fichier dans une nouvelle requête et clique sur Run. Ordre : du plus petit numéro au plus grand.

- `000007` : à faire **avant** d'installer la nouvelle version de l'app (sinon la carte ne charge pas).
- `000008` : ne pas exécuter la « section 3 » en commentaire à la fin du fichier (elle viendra plus tard, voir §5).

## 2. Tester les notifications (déployées le 29/09 à 00:16 UTC)

1. Envoie un message et un like entre deux comptes de test.
2. Vérifie que les notifications arrivent sur le téléphone.
3. Dans le SQL Editor :

```sql
SELECT id, status_code, left(content, 60) AS debut, created
FROM net._http_response
WHERE content NOT LIKE '%"stories"%'
ORDER BY id DESC LIMIT 3;
```

Il faut `200` sur les lignes datées après le 29/09 00:16. Si tu vois `401` : prévenir Claude, il remet l'ancienne version.

## 3. Déploiements restants (PowerShell, dans `c:\Applications\rencontre`)

Un par un, dans cet ordre :

```powershell
supabase functions deploy purge-expired --no-verify-jwt --project-ref flixcyjefjcyjwvjdiny
supabase functions deploy delete-account --project-ref flixcyjefjcyjwvjdiny
supabase functions deploy swift-service --no-verify-jwt --project-ref flixcyjefjcyjwvjdiny
supabase functions deploy moderate-image --no-verify-jwt --project-ref flixcyjefjcyjwvjdiny
```

- `purge-expired` : supprime aussi les snaps ouverts et les anciens messages « mode éphémère ».
- `delete-account` : efface enfin les photos et toutes les données à la suppression d'un compte.
- `swift-service` : webhook RevenueCat corrigé (restaurer un achat, identifiants anonymes). Après le déploiement, dans RevenueCat → Webhooks, clique « Send test event » : il doit répondre 200.
- `moderate-image` : sécurisé, mais pas encore appelé par l'app.

**Ne jamais déployer** `send-notification`, `notify-all-users` (versions du panneau admin, déjà en ligne), `send-push-notification`, `send-like-notification` (anciennes, inutilisées).

## 4. Nouvelle version de l'app

Après les étapes 1 et 3 : `flutter build appbundle`, puis publication sur Google Play. À tester avant :

- connexion par nom d'utilisateur, déconnexion puis connexion avec un autre compte ;
- profil : carrousel de photos, carte « Profil complété », chiffres Matchs / Likes / Vues, carte Premium ;
- Paramètres : les interrupteurs s'enregistrent seuls, « Nous contacter », version de l'app ;
- conversation : mention « Les messages disparaissent 24h après avoir été vus », plus de bouton « Éphémère » ;
- liste des conversations : « Aucun nouveau message » quand tout a expiré ;
- changer de thème : plus d'éléments qui restent roses (vérifier aussi le bouton « Supprimer » du dialogue de suppression de photo, qui suit maintenant la couleur du thème) ;
- carte : la recherche de ville trouve enfin des résultats ;
- accueil : grille en 3 colonnes (retour à l'ancienne grille le 30/09) ;
- menu Story : stories texte affichées, traits de progression, vues/likes de mes stories, point « en ligne » et distance, bouton « Publier ma story » si vide ;
- modération : changer de photo de profil, ajouter une photo à la galerie, photo d'inscription, publier une story photo → message si refusée / en vérification ;
- signaler une story (bouton ⋮ en haut, dans le menu Story et dans le visualiseur) : elle disparaît pour la personne qui la signale ;
- menu Story : toutes les stories de chaque personne, regroupées (avant : une seule) ;
- répondre à une story texte : le texte apparaît dans la conversation (nécessite le script `000010`) ;
- menu ⋮ d'une conversation : en-tête (appui → profil), couper les notifications (plus de push de cette conversation), appel vidéo grisé « Bientôt », fond d'écran (6 choix, gardé par conversation), signaler / bloquer la personne, effacer l'historique (ne revient plus en rouvrant, aperçu de la liste vidé), supprimer l'échange ;
- liste des messages : loupe en haut à droite (recherche), filtres Tous / Non lus / En ligne ; appui long sur une conversation : marquer lu / non lu et épingler (gardés après redémarrage), couper les notifications (icône 🔕 sur la conversation) ;
- appui long sur un message reçu > Signaler : choix du motif puis confirmation ;
- messages directs sans match : le destinataire voit la conversation, limite de 3 messages sans réponse, blocage efficace ;
- Paramètres > mot de passe : la jauge de force suit les couleurs du thème.

## 5. Plus tard

- **Pages légales** (fait le 30/09) : hébergées sur GitHub Pages, compte `supportsnapmeet-jpg`, dépôt `zamu-legal` (sources dans `legal/`). Conditions : https://supportsnapmeet-jpg.github.io/zamu-legal/conditions-utilisation.html — Confidentialité : https://supportsnapmeet-jpg.github.io/zamu-legal/politique-confidentialite.html. **À faire :** coller l'adresse de la politique dans la Play Console (Contenu de l'appli > Règles de confidentialité). Pour modifier un texte : éditer le fichier dans `legal/` puis le renvoyer sur le dépôt.
- **Section 3 de `000008`** (réserver aux Premium la liste « Qui m'a vu ») : à exécuter seulement quand presque tous les utilisateurs ont la nouvelle version de l'app.
- **Plusieurs langues (anglais…)** : prévu plus tard (ouverture pays anglophones / diaspora / App Store). Méthode : traductions GetX (`'cle'.tr`, fichiers fr/en), choix « Langue » dans Paramètres, langue mémorisée pour les notifications serveur, pages légales et fiche Play Store traduites. ~800-1000 textes.
- **Colonne `is_pinned`** des stories : inutile depuis le retrait des publications épinglées ; supprimable plus tard avec `ALTER TABLE public.stories DROP COLUMN IF EXISTS is_pinned;`.
- **Commit git** : rien n'est encore enregistré dans git depuis le début des corrections.

## 6. Version iPhone (commencée le 30/09)

Construction via **Codemagic** (pas de Mac). Identifiant : `com.vybestyle.zamu`.

Déjà fait dans le code : nom « Zamu », textes des autorisations (caméra, photos, micro, position), portrait uniquement, notifications en arrière-plan, Podfile (iOS 13, autorisations), capacités push + Apple, bouton « Continuer avec Apple » (iPhone seulement), Premium désactivé sur iPhone tant que la clé RevenueCat iOS est vide (`kRevenueCatIosApiKey`).

**Construction iPhone vérifiée le 01/10** sur Codemagic (build n° 4, commit `e355813`, workflow « iOS - vérification », Flutter 3.38.5). Relancer : Start new build > **Build branch** `main` (pas « Build commit ») > workflow.

Reste à faire :
1. Créer le compte Apple Developer (99 $/an).
2. ~~Firebase : app iOS + `GoogleService-Info.plist`~~ (fait le 01/10) ; reste la clé APNs (Apple) à envoyer dans Firebase > Cloud Messaging.
3. ~~Google Cloud : client OAuth iOS « Zamu iOS » dans `Info.plist`~~ (fait le 01/10) ; Supabase > Auth > Google : ajouter l'ID client iOS aux Client IDs et activer « Skip nonce checks ».
4. Apple : App ID avec « Sign in with Apple » et « Push Notifications » ; Supabase > Auth > Providers > Apple (Client ID `com.vybestyle.zamu`).
5. App Store Connect : créer l'app, l'abonnement Premium ; RevenueCat : app iOS → clé `appl_…` dans `kRevenueCatIosApiKey`.
6. Codemagic : relier le dépôt GitHub, clé API App Store Connect, fichier `codemagic.yaml`, puis envoi sur TestFlight.

