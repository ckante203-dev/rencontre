# Suivi Zamu — à faire au retour

Mis à jour le 29/09/2026.

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
- accueil : grille en 2 colonnes (pour revenir à 3 : `_colonnesGrille` / `_ratioCarte` dans home_screen.dart) ;
- messages directs sans match : le destinataire voit la conversation, limite de 3 messages sans réponse, blocage efficace ;
- Paramètres > mot de passe : la jauge de force suit les couleurs du thème.

## 5. Plus tard

- **Politique de confidentialité** : envoyer le lien à Claude (obligatoire sur Google Play). Mettre aussi à jour le lien des conditions d'utilisation, qui pointe encore vers `snapmeet.notion.site`.
- **Section 3 de `000008`** (réserver aux Premium la liste « Qui m'a vu ») : à exécuter seulement quand presque tous les utilisateurs ont la nouvelle version de l'app.
- **Colonne `is_pinned`** des stories : inutile depuis le retrait des publications épinglées ; supprimable plus tard avec `ALTER TABLE public.stories DROP COLUMN IF EXISTS is_pinned;`.
- **Commit git** : rien n'est encore enregistré dans git depuis le début des corrections.
