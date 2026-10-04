import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// Réglage « Son des notifications » de l'utilisateur (mis à jour par
  /// ControleurProfil). Coupé → canaux *_silencieux.
  static bool sonActive = true;
  static String _canal(String base) =>
      sonActive ? base : '${base}_silencieux';

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
        // ✅ Nouveaux abonnés (le serveur utilisait ce canal, absent de l'app)
        NotificationChannel(
          channelKey: 'follows',
          channelName: 'Abonnés',
          channelDescription: 'Notifications de nouveaux abonnés',
          defaultColor: const Color(0xFFFF3CAC),
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
        ),
        // ✅ Variantes silencieuses : réglage « Son des notifications » coupé
        // (le serveur choisit le canal *_silencieux selon profiles.notif_son)
        for (final c in const [
          ['messages_silencieux', 'Messages (silencieux)'],
          ['likes_silencieux', 'Likes (silencieux)'],
          ['matches_silencieux', 'Matchs (silencieux)'],
          ['follows_silencieux', 'Abonnés (silencieux)'],
        ])
          NotificationChannel(
            channelKey: c[0],
            channelName: c[1],
            channelDescription: 'Notifications sans son',
            defaultColor: const Color(0xFFFF3CAC),
            importance: NotificationImportance.High,
            channelShowBadge: true,
            playSound: false,
            enableVibration: true,
          ),
        // ✅ Nouveau canal — stories
        NotificationChannel(
          channelKey: 'stories',
          channelName: 'Stories',
          channelDescription: 'Nouvelles stories et likes de stories',
          defaultColor: const Color(0xFF7B2FFF),
          ledColor: const Color(0xFF7B2FFF),
          importance: NotificationImportance.Default,
          channelShowBadge: true,
          playSound: false,
        ),
        // ✅ Notifications intelligentes
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
        // ✅ Alertes en ligne
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
  // NOTIFICATIONS
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
        channelKey: _canal('messages'),
        title: senderName,
        body: preview,
        largeIcon: senderPhoto,
        notificationLayout: NotificationLayout.Messaging,
        category: NotificationCategory.Message,
        wakeUpScreen: true,
        // ✅ Disparaît une fois touchée (avant : restait dans la barre)
        autoDismissible: true,
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
        channelKey: _canal('likes'),
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
        channelKey: _canal('matches'),
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

  // ✅ Remplace showAnnonceNotification — notifications de stories
  static Future<void> showStoryNotification({
    required String title,
    required String body,
    String? userPhoto,
    String? userId,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'stories',
        title: title,
        body: body,
        largeIcon: userPhoto,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: false,
        payload: {
          'type': 'new_story',
          'userId': userId ?? '',
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ NOTIFICATIONS INTELLIGENTES
  // ═══════════════════════════════════════════════════════════════

  /// Notif "X personnes ont vu ton profil"
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

  /// Notif de réengagement
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
        'Reviens voir ce qui se passe sur Zamu'
      ),
      (
        'Nouvelles stories disponibles 📸',
        'Découvre ce que partagent les gens près de toi'
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
  static Future<void> checkAndSendSmartNotifications() async {
    try {
      final sb = Supabase.instance.client;
      final uid = sb.auth.currentUser?.id;
      if (uid == null) return;

      final bool isAllowed =
          await AwesomeNotifications().isNotificationAllowed();
      if (!isAllowed) return;

      final yesterday = DateTime.now().subtract(const Duration(hours: 24));

      await _checkProfileViews(sb, uid, yesterday);
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
    await _handlePayload(action.payload ?? const {});
  }

  /// ✅ Clic sur une notification push FCM affichée par le système
  /// (app en arrière-plan ou fermée). Convertit les clés envoyées par
  /// les edge functions vers celles des notifications locales, puis
  /// réutilise la même navigation.
  static Future<void> handlePushTap(Map<String, dynamic> data) async {
    String? s(String key) {
      return data[key]?.toString();
    }

    final type = s('type') ??
        ((s('conversationId') ?? '').isNotEmpty ? 'message' : null);
    await _handlePayload({
      'type': type,
      'conversationId': s('conversationId'),
      'senderName': s('senderName'),
      'senderPhoto': s('senderPhoto'),
      'fromUserId': s('fromUserId') ?? s('from_user_id'),
      'userName': s('userName') ?? s('from_user_name'),
      'userPhoto': s('userPhoto') ?? s('from_user_photo'),
      'userId': s('userId'),
      'filtre': s('filtre'),
    });
  }

  /// ✅ Notification push reçue app ouverte : on l'affiche avec le bon
  /// canal selon son type (avant, un like s'affichait comme un message).
  static Future<void> showFromPush(
      Map<String, dynamic> data, String? title, String? body) async {
    String? s(String key) {
      return data[key]?.toString();
    }

    final type = s('type');
    // 💸 Like reçu par un compte gratuit : anonyme, ouvre l'onglet ❤️
    if (type == 'like_anonyme') {
      if (!await AwesomeNotifications().isNotificationAllowed()) return;
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
          channelKey: _canal('likes'),
          title: title ?? '❤️ Quelqu\'un t\'a liké !',
          body: body ?? 'Découvre qui t\'a liké 👀',
          notificationLayout: NotificationLayout.Default,
          payload: {'type': 'like_anonyme'},
        ),
      );
      return;
    }
    // ⭐ Favori en ligne / proche / dans ma ville (dynamic-processor)
    if (type != null && type.startsWith('favori')) {
      final fromUserId = s('fromUserId') ?? s('from_user_id') ?? '';
      if (fromUserId.isEmpty) return;
      if (!await AwesomeNotifications().isNotificationAllowed()) return;
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: ('$type$fromUserId').hashCode.abs() % 2147483647,
          channelKey: _canal('likes'),
          title: title ?? '⭐ Ton favori',
          body: body ?? '',
          largeIcon: s('from_user_photo'),
          notificationLayout: NotificationLayout.Default,
          payload: {'type': type, 'fromUserId': fromUserId},
        ),
      );
      return;
    }
    if (type == 'like' || type == 'match') {
      final fromUserId = s('fromUserId') ?? s('from_user_id') ?? '';
      final userName = s('userName') ?? s('from_user_name') ?? 'Quelqu\'un';
      final userPhoto = s('userPhoto') ?? s('from_user_photo');
      if (type == 'match') {
        await showMatchNotification(
            userName: userName, userPhoto: userPhoto, fromUserId: fromUserId);
      } else if (fromUserId.isNotEmpty) {
        await showLikeNotification(
            userName: userName, userPhoto: userPhoto, fromUserId: fromUserId);
      }
      return;
    }

    final convId = s('conversationId') ?? '';
    if (convId.isEmpty) return;
    // ✅ Conversation déjà ouverte à l'écran : le message s'affiche dans la
    // discussion, pas besoin de notification (avant : bannière + son à
    // chaque message de la personne avec qui on discute).
    if (Get.isRegistered<ConversationController>(tag: convId)) return;
    await showMessageNotification(
      senderName: s('senderName') ?? title ?? 'Quelqu\'un',
      message: s('message') ?? body ?? '',
      senderPhoto: s('senderPhoto'),
      conversationId: convId,
    );
  }

  static Future<void> _handlePayload(Map<String, String?> payload) async {
    final type = payload['type'];

    // ── Message → conversation ──
    if (type == 'message') {
      final conversationId = payload['conversationId'];
      final senderName = payload['senderName'] ?? '';
      final senderPhoto = payload['senderPhoto'];
      if (conversationId == null || conversationId.isEmpty) return;

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

    // ── Like / Match / Favori → profil ──
    else if (type == 'like' ||
        type == 'match' ||
        (type != null &&
            type.startsWith('favori') &&
            type != 'favori_story')) {
      final fromUserId = payload['fromUserId'];
      if (fromUserId == null || fromUserId.isEmpty) return;

      await Future.delayed(const Duration(milliseconds: 800));
      // Profil complet (âge, photos, bio…), pas une fiche partielle
      await ouvrirProfilParId(fromUserId);
    }

    // ✅ Nouvelle story (ou story d'un favori ⭐) → onglet Story
    else if (type == 'new_story' ||
        type == 'like_story' ||
        type == 'favori_story') {
      await Future.delayed(const Duration(milliseconds: 500));
      NavigationController.pendingIndex = NavigationController.storyIndex;
      Get.offAllNamed(AppRoutes.main);
    }

    // ✅ Résumé likes / vues profil, like anonyme → onglet ❤️
    else if (type == 'likes_summary' ||
        type == 'profile_views' ||
        type == 'like_anonyme') {
      await Future.delayed(const Duration(milliseconds: 500));
      NavigationController.pendingIndex = NavigationController.likesIndex;
      Get.offAllNamed(AppRoutes.main);
    }

    // ✅ Utilisateur en ligne → ouvrir son profil
    else if (type == 'user_online') {
      final userId = payload['userId'];
      if (userId == null || userId.isEmpty) return;

      await Future.delayed(const Duration(milliseconds: 800));
      await ouvrirProfilParId(userId);
    }

    // ✅ Réengagement (relance de 19 h) → Accueil, Messages ou filtre Dispo
    else if (type == 'reengagement') {
      await Future.delayed(const Duration(milliseconds: 500));
      final filtre = payload['filtre'];
      if (filtre == 'messages') {
        NavigationController.pendingIndex = NavigationController.messagesIndex;
      } else if (filtre == 'dispo' && Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().setFilter('dispo');
      }
      Get.offAllNamed(AppRoutes.main);
      if (filtre == 'dispo') {
        // HomeController est créé par l'écran principal s'il n'existait pas
        await Future.delayed(const Duration(milliseconds: 600));
        if (Get.isRegistered<HomeController>()) {
          Get.find<HomeController>().setFilter('dispo');
        }
      }
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
