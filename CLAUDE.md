# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter dating + social app, branded **Zamu** (Dart package name `rencontre`; older names SnapMeet/`com.snapmeet.app` still appear, e.g. Android `namespace`, while `applicationId` is `com.vybestyle.zamu`). Android is the primary target (RevenueCat is configured with an Android key only). Code comments, UI strings, and some folder/file names are in French (e.g. `features/profil/controleur/`, `vue/ecran_*.dart`) — follow the existing naming within each feature.

## Commands

```bash
flutter pub get
flutter run                         # run on connected device/emulator
flutter analyze                     # lints (flutter_lints)
flutter test                        # all tests (test/widget_test.dart — model unit tests)
flutter test --plain-name "distanceLabel"   # single test by name
flutter build apk --release         # / flutter build appbundle
dart run tool/fix_const_theme.dart  # strips `const` made invalid by runtime theme colors across lib/
dart run flutter_launcher_icons     # regenerate Android icon from assets/images/logo.png
supabase functions deploy <name>    # deploy an edge function from supabase/functions/
```

## Architecture

**State/DI/routing: GetX.** `GetMaterialApp` with named routes in [lib/core/utils/app_routes.dart](lib/core/utils/app_routes.dart) (`AppRoutes` constants + `pages`). Navigation uses `Get.toNamed(route, arguments: {...})`. Controllers are `GetxController`s with `Rx`/`.obs` fields consumed via `Obx`. Most feature controllers (`HomeController`, `ChatListController`, `LikeController`, `ProfileInsightsController`, `ControleurProfil`, `NavigationController`) are registered `permanent: true` in [main_navigation.dart](lib/features/home/view/main_navigation.dart) when the main shell mounts; `AuthController` and `ThemeController` are put in `main.dart`; `RevenueCatService` is a `GetxService` put asynchronously.

**Startup ([lib/main.dart](lib/main.dart)):** initializes Supabase, Firebase, GetStorage in parallel; loads the theme before `runApp`; picks the initial route by reading the user's `profiles` row (`onboarding_complete`, `birthdate`, provider = google) → `/main`, `/onboarding/birthdate`, or `/onboarding/photo`. Non-critical init (notifications, RevenueCat login, FCM token, app version, permissions) runs after `runApp` in `_initEnArrierePlan`, each step wrapped in try/catch.

**Backend: Supabase** (URL + anon key hardcoded in `main.dart`). The global `supabase` client and the `SupabaseService` singleton live in [supabase_service.dart](lib/core/services/supabase_service.dart), which holds the shared data access (profiles fetch/filter/distance, presence heartbeat, conversations, message requests, messages). Controllers also query `Supabase.instance.client` directly. Main tables: `profiles` (also holds `blocked_users` array, `fcm_token`, `theme`, `app_version`, `is_suspended`, premium flag), `matches`, `conversations`, `messages`, stories. Realtime is done with `.channel(...).onPostgresChanges(...)` in controllers (chat list, typing, presence, conversation, online profiles, stories) — remember to unsubscribe in `onClose`. Online status is derived from `last_seen` < 30 min (`SupabaseService.isReallyOnline`), not trusted from `is_online` alone.

**Edge functions** (Deno/TypeScript, [supabase/functions/](supabase/functions/)). Folder name = deployed slug (project ref `flixcyjefjcyjwvjdiny`); always diff against the live code (`supabase functions download <slug> --workdir <tmp>`) before deploying, some were edited in the dashboard:
- `smooth-action` — message push; called by SQL function `notify_new_message` (trigger on `messages`) with the project secret key (`sb_secret_…`), code rejects any other caller.
- `dynamic-processor` — like / match / follow push; called by SQL functions `notify_new_like` / `notify_new_follow` (match computed in SQL), same secret-key check.
- `send-notification`, `notify-all-users` — admin-only senders used by the external admin panel (`requireAdmin`).
- `swift-service` — RevenueCat webhook (display name `revenuecat-webhook`), deploy with `--no-verify-jwt`.
- `purge-expired` — called every 15 min by pg_cron (job `purge-expired`, secret in Vault `purge_secret` = env `PURGE_SECRET`): deletes expired stories and messages read > 24h (rows + Storage files) and the `storage_a_supprimer` queue. `--no-verify-jwt`.
- `delete-account` (app, user JWT), `moderate-image` (`--no-verify-jwt`, checks JWT in code, not called by the app yet).
- `send-push-notification`, `send-like-notification` are old, not deployed, not called — do not deploy.

SQL changes live in [supabase/migrations/](supabase/migrations/) but are applied by hand in the SQL Editor (no CLI link to the DB).

**Notifications:** FCM (`firebase_messaging`) delivers pushes; they are displayed with `awesome_notifications` (channel `messages`) via [notification_service.dart](lib/core/services/notification_service.dart). `/chat/conversation` expects a `ConversationModel` as argument; push taps go through `NotificationService.handlePushTap` / `showFromPush`, which dispatch on `data['type']` (message / like / match). The background handler in `main.dart` must stay a top-level `@pragma('vm:entry-point')` function.

**Premium:** [revenue_cat_service.dart](lib/core/services/revenue_cat_service.dart) exposes `isPremium` (entitlement `zamu_premium`); the RevenueCat app user id is the Supabase user id. Server-side, `revenuecat-webhook` syncs the entitlement into the database. Premium-gated UI: paywall (`/premium/paywall`), likes insights/details ("who viewed/liked me"), `PremiumBadge`.

**Theming:** multiple palettes in [app_palette.dart](lib/core/theme/app_palette.dart); `ThemeController.to.palette` is reactive, persisted in GetStorage and in `profiles.theme`, and `AppTheme.buildFrom(palette)` rebuilds the whole app. Because colors come from the runtime palette, widgets using them cannot be `const` (hence `tool/fix_const_theme.dart`).

## Notes

- `document/` holds Word docs (architecture, DB schema, deployment guide, update procedure) — the DB schema is not versioned as SQL in this repo.
- `firebase_secret.env` is a secret and is git-ignored; do not commit it.
