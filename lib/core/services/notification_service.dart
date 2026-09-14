import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // ═══════════════════════════════════════════════════════════════
  // INITIALISATION
  // ═══════════════════════════════════════════════════════════════

  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null,
      [
        NotificationChannel(
          channelKey: 'messages',
          channelName: 'Messages',
          channelDescription: 'Notifications de nouveaux messages',
          defaultColor: const Color(0xFFFF3CAC),
          ledColor: const Color(0xFFFF3CAC),
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          soundSource: 'resource://raw/message_sound',
          enableVibration: true,
          vibrationPattern: highVibrationPattern,
        ),
        NotificationChannel(
          channelKey: 'likes',
          channelName: 'Likes',
          channelDescription: 'Notifications de likes et matchs',
          defaultColor: const Color(0xFFFF3CAC),
          ledColor: const Color(0xFFFF3CAC),
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
        ),
        NotificationChannel(
          channelKey: 'matches',
          channelName: 'Matchs',
          channelDescription: 'Notifications de nouveaux matchs',
          defaultColor: const Color(0xFF7B2FFF),
          ledColor: const Color(0xFF7B2FFF),
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
        ),
        NotificationChannel(
          channelKey: 'annonces',
          channelName: 'Annonces',
          channelDescription: 'Nouvelles annonces',
          defaultColor: const Color(0xFFFFD700),
          ledColor: const Color(0xFFFFD700),
          importance: NotificationImportance.Default,
          channelShowBadge: true,
          playSound: false,
        ),
        // ✅ Nouveau canal — notifications intelligentes
        NotificationChannel(
          channelKey: 'smart',
          channelName: 'Activité',
          channelDescription: 'Résumé d\'activité et alertes intelligentes',
          defaultColor: const Color(0xFF7B2FFF),
          ledColor: const Color(0xFF7B2FFF),
          importance: NotificationImportance.Default,
          channelShowBadge: true,
          playSound: false,
          enableVibration: false,
        ),
        // ✅ Nouveau canal — alertes en ligne
        NotificationChannel(
          channelKey: 'online_alert',
          channelName: 'En ligne',
          channelDescription: 'Alertes quand quelqu\'un est en ligne',
          defaultColor: const Color(0xFF00d68f),
          ledColor: const Color(0xFF00d68f),
          importance: NotificationImportance.Default,
          channelShowBadge: false,
          playSound: false,
          enableVibration: false,
        ),
      ],
      debug: false,
    );

    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  // ═══════════════════════════════════════════════════════════════
  // NOTIFICATIONS EXISTANTES (inchangées)
  // ═══════════════════════════════════════════════════════════════

  static Future<void> showMessageNotification({
    required String senderName,
    required String message,
    String? senderPhoto,
    required String conversationId,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    final preview =
        message.length > 100 ? '${message.substring(0, 97)}...' : message;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: conversationId.hashCode.abs() % 2147483647,
        channelKey: 'messages',
        title: senderName,
        body: preview,
        largeIcon: senderPhoto,
        notificationLayout: NotificationLayout.Messaging,
        category: NotificationCategory.Message,
        wakeUpScreen: true,
        autoDismissible: false,
        payload: {
          'type': 'message',
          'conversationId': conversationId,
          'senderName': senderName,
          'senderPhoto': senderPhoto ?? '',
        },
      ),
    );
  }

  static Future<void> showLikeNotification({
    required String userName,
    String? userPhoto,
    required String fromUserId,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: fromUserId.hashCode.abs() % 2147483647,
        channelKey: 'likes',
        title: '❤️ Nouveau like !',
        body: '$userName t\'a liké !',
        largeIcon: userPhoto,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
        badge: 1,
        payload: {
          'type': 'like',
          'fromUserId': fromUserId,
          'userName': userName,
          'userPhoto': userPhoto ?? '',
        },
      ),
    );
  }

  static Future<void> showMatchNotification({
    required String userName,
    String? userPhoto,
    String? fromUserId,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: (fromUserId ?? userName).hashCode.abs() % 2147483647,
        channelKey: 'matches',
        title: '💘 Nouveau match !',
        body: '$userName veut te parler !',
        largeIcon: userPhoto,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
        badge: 1,
        payload: {
          'type': 'match',
          'fromUserId': fromUserId ?? '',
          'userName': userName,
          'userPhoto': userPhoto ?? '',
        },
      ),
    );
  }

  static Future<void> showAnnonceNotification({
    required String title,
    required String body,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'annonces',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: false,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ NOTIFICATIONS INTELLIGENTES
  // ═══════════════════════════════════════════════════════════════

  /// Notif "X personnes ont vu ton profil"
  /// À appeler depuis l'Edge Function ou depuis home_controller
  static Future<void> showProfileViewsNotification({
    required int viewCount,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed || viewCount <= 0) return;

    final String body = viewCount == 1
        ? '👁️ 1 personne a visité ton profil ce matin'
        : '👁️ $viewCount personnes ont visité ton profil ce matin';

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 10001,
        channelKey: 'smart',
        title: 'Ton profil est populaire 🔥',
        body: body,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: false,
        payload: {'type': 'profile_views'},
      ),
    );
  }

  /// Notif "X nouveaux likes depuis hier"
  static Future<void> showNewLikesSummaryNotification({
    required int likeCount,
    String? topLikerName,
    String? topLikerPhoto,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed || likeCount <= 0) return;

    final String title = likeCount == 1
        ? '❤️ 1 nouveau like !'
        : '❤️ $likeCount nouveaux likes !';

    final String body = topLikerName != null
        ? '$topLikerName et ${likeCount - 1} autre${likeCount > 2 ? 's' : ''} t\'ont liké'
        : '$likeCount personne${likeCount > 1 ? 's t\'ont liké' : ' t\'a liké'} depuis hier';

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 10002,
        channelKey: 'smart',
        title: title,
        body: body,
        largeIcon: topLikerPhoto,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: false,
        payload: {'type': 'likes_summary'},
      ),
    );
  }

  /// Notif "X est en ligne maintenant"
  /// À appeler quand un utilisateur suivi passe en ligne
  static Future<void> showUserOnlineNotification({
    required String userName,
    required String userId,
    String? userPhoto,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: userId.hashCode.abs() % 2147483647,
        channelKey: 'online_alert',
        title: '$userName est en ligne 🟢',
        body: 'C\'est le bon moment pour lui envoyer un message !',
        largeIcon: userPhoto,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: false,
        payload: {
          'type': 'user_online',
          'userId': userId,
          'userName': userName,
        },
      ),
    );
  }

  /// Notif "Tu n'as pas ouvert l'app depuis X jours"
  /// Rappel de réengagement
  static Future<void> showReEngagementNotification() async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    final messages = [
      (
        'Des profils t\'attendent 💕',
        'De nouvelles personnes se sont inscrites près de toi !'
      ),
      (
        'Tu manques à la communauté 🔥',
        'Reviens voir ce qui se passe sur SnapMeet'
      ),
      (
        'Nouvelles annonces disponibles 📢',
        'Des gens cherchent quelqu\'un comme toi'
      ),
      ('Tes matchs t\'attendent 💬', 'Tu as des conversations non lues'),
    ];

    final pick = messages[DateTime.now().millisecond % messages.length];

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: 10003,
        channelKey: 'smart',
        title: pick.$1,
        body: pick.$2,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: false,
        payload: {'type': 'reengagement'},
      ),
    );
  }

  /// ✅ Vérification intelligente — à appeler au démarrage de l'app
  /// Vérifie les stats et envoie les notifs appropriées
  static Future<void> checkAndSendSmartNotifications() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;

      final bool isAllowed =
          await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) return;

      final yesterday = DateTime.now().subtract(const Duration(hours: 24));

      // ✅ 1. Vues du profil depuis hier
      await _checkProfileViews(sb, uid, yesterday);

      // ✅ 2. Nouveaux likes depuis hier
      await _checkNewLikes(sb, uid, yesterday);
    } catch (e) {
      debugPrint('checkAndSendSmartNotifications error: $e');
    }
  }

  static Future<void> _checkProfileViews(
      SupabaseClient sb, String uid, DateTime since) async {
    try {
      final data = await sb
          .from('profile_views')
          .select('id')
          .eq('viewed_id', uid)
          .gte('created_at', since.toIso8601String());

      final count = (data as List).length;
      if (count >= 3) {
        await showProfileViewsNotification(viewCount: count);
      }
    } catch (_) {
      // Table profile_views peut ne pas exister encore — silencieux
    }
  }

  static Future<void> _checkNewLikes(
      SupabaseClient sb, String uid, DateTime since) async {
    try {
      final data = await sb
          .from('likes')
          .select(
              'from_user_id, profiles!likes_from_user_id_fkey(name, photo_url)')
          .eq('to_user_id', uid)
          .gte('created_at', since.toIso8601String())
          .order('created_at', ascending: false);

      final count = (data as List).length;
      if (count >= 1) {
        final topLiker = count > 0 ? data[0]['profiles'] : null;
        await showNewLikesSummaryNotification(
          likeCount: count,
          topLikerName: topLiker?['name'] as String?,
          topLikerPhoto: topLiker?['photo_url'] as String?,
        );
      }
    } catch (_) {
      // Silencieux si structure BDD différente
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UTILITAIRES
  // ═══════════════════════════════════════════════════════════════

  static Future<void> clearBadge() async {
    await AwesomeNotifications().resetGlobalBadge();
  }

  static Future<void> clearConversationNotifications(
      String conversationId) async {
    await AwesomeNotifications()
        .cancel(conversationId.hashCode.abs() % 2147483647);
    await AwesomeNotifications().resetGlobalBadge();
  }

  // ═══════════════════════════════════════════════════════════════
  // ÉCOUTE DES CLICS
  // ═══════════════════════════════════════════════════════════════

  static void listenToNotifications() {
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction action) async {
    final type = action.payload?['type'];

    // ── Message → conversation ──
    if (type == 'message') {
      final conversationId = action.payload?['conversationId'];
      final senderName = action.payload?['senderName'] ?? '';
      final senderPhoto = action.payload?['senderPhoto'];
      if (conversationId == null) return;

      await Future.delayed(const Duration(milliseconds: 800));

      ConversationModel conv;
      try {
        if (Get.isRegistered<ChatListController>()) {
          final ctrl = Get.find<ChatListController>();
          final found = ctrl.conversations
              .firstWhereOrNull((c) => c.id == conversationId);
          conv = found ??
              _buildMinimalConv(conversationId, senderName, senderPhoto);
        } else {
          conv = _buildMinimalConv(conversationId, senderName, senderPhoto);
        }
      } catch (_) {
        conv = _buildMinimalConv(conversationId, senderName, senderPhoto);
      }

      await clearConversationNotifications(conversationId);
      if (Get.currentRoute == '/chat/conversation') {
        Get.back();
        await Future.delayed(const Duration(milliseconds: 200));
      }
      Get.toNamed('/chat/conversation', arguments: conv);
    }

    // ── Like / Match → profil ──
    else if (type == 'like' || type == 'match') {
      final fromUserId = action.payload?['fromUserId'];
      if (fromUserId == null || fromUserId.isEmpty) return;

      await Future.delayed(const Duration(milliseconds: 800));
      try {
        final data = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', fromUserId)
            .maybeSingle();
        if (data == null) return;
        Get.toNamed('/profile/view',
            arguments: UserModel(
              id: data['id'] as String,
              name: data['name'] as String? ?? 'Utilisateur',
              age: data['age'] as int? ?? 18,
              photoUrl: data['photo_url'] as String?,
              bio: data['bio'] as String?,
              isOnline: data['is_online'] as bool? ?? false,
              latitude: (data['latitude'] as num?)?.toDouble(),
              longitude: (data['longitude'] as num?)?.toDouble(),
            ));
      } catch (_) {}
    }

    // ✅ Résumé likes → page profil / qui m'a liké
    else if (type == 'likes_summary' || type == 'profile_views') {
      await Future.delayed(const Duration(milliseconds: 500));
      Get.offAllNamed(AppRoutes.main);
      if (Get.isRegistered<NavigationController>()) {
        Get.find<NavigationController>().goTo(4); // onglet Profil
      }
    }

    // ✅ Utilisateur en ligne → ouvrir son profil
    else if (type == 'user_online') {
      final userId = action.payload?['userId'];
      final userName = action.payload?['userName'] ?? '';
      if (userId == null) return;

      await Future.delayed(const Duration(milliseconds: 800));
      try {
        final data = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', userId)
            .maybeSingle();
        if (data == null) return;
        Get.toNamed('/profile/view',
            arguments: UserModel(
              id: data['id'] as String,
              name: data['name'] as String? ?? userName,
              age: data['age'] as int? ?? 18,
              photoUrl: data['photo_url'] as String?,
              isOnline: true,
              latitude: (data['latitude'] as num?)?.toDouble(),
              longitude: (data['longitude'] as num?)?.toDouble(),
            ));
      } catch (_) {}
    }

    // ✅ Réengagement → onglet Accueil
    else if (type == 'reengagement') {
      await Future.delayed(const Duration(milliseconds: 500));
      Get.offAllNamed(AppRoutes.main);
    }
  }

  static ConversationModel _buildMinimalConv(
      String id, String userName, String? photoUrl) {
    return ConversationModel(
      id: id,
      userId: '',
      userName: userName.isNotEmpty ? userName : 'Message',
      userPhotoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
      isOnline: false,
      unreadCount: 0,
      lastActivity: DateTime.now(),
      isPinned: false,
    );
  }
}
