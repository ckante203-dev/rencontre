# Suivi Zamu — à faire au retour

Mis à jour le 30/09/2026.

**Fait le 30/09 :** scripts `000010`, `000011` et `000012` appliqués ; fonction `moderate-image` déployée (clés Sightengine vérifiées).

**Fait le 30/09 :** script `000014` appliqué (sourdine par conversation, signalement des messages) et `smooth-action` redéployée.

**Modération des photos (Sightengine, offre gratuite : 2 000 photos/mois, 500/jour) :** clés enregistrées sur le serveur le 30/09.
- Plus tard, quand presque tout le monde a la nouvelle version : `20260930000013_moderation_verrouillage.sql` (empêche de contourner la modération).
- Photos « pending » (douteuses) : cachées, à valider (requêtes en tête du script 000012, en attendant le panneau admin).
- Photos « unchecked » : publiées sans analyse (quota dépassé, vidéos) — à contrôler de temps en temps. Les signalements de stories arrivent dans la table `reports` avec `story_id` rempli : les traiter vite, la story et son fichier sont purgés à l'expiration.

**État :** tous les scripts SQL (000000 à 000009) sont appliqués ; toutes les fonctions serveur sont déployées (notifications testées OK le 29/09) ; commit `7723aed`. Restent les points 4 et 5.

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
- **Colonne `is_pinned`** des stories : inutile depuis le retrait des publications épinglées ; supprimable plus tard avec `ALTER TABLE public.stories DROP COLUMN IF EXISTS is_pinned;`.
- **Commit git** : rien n'est encore enregistré dans git depuis le début des corrections.
