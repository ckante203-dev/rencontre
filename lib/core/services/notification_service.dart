import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

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
          importance: NotificationImportance.High,
          channelShowBadge: true,
          playSound: true,
          enableVibration: true,
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
      ],
      debug: false,
    );

    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  // ─── NOTIFICATION MESSAGE ─────────────────────────────────────

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
        autoDismissible: true,
        badge: 1,
        payload: {
          'type': 'message',
          'conversationId': conversationId,
          'senderName': senderName,
        },
      ),
    );
  }

  // ─── NOTIFICATION MATCH ───────────────────────────────────────

  static Future<void> showMatchNotification({
    required String userName,
    String? userPhoto,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'matches',
        title: '💘 Nouveau match !',
        body: '$userName veut te parler !',
        largeIcon: userPhoto,
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
        badge: 1,
        payload: {
          'type': 'match',
          'userName': userName,
        },
      ),
    );
  }

  // ─── NOTIFICATION ANNONCE ─────────────────────────────────────

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
        badge: 1,
      ),
    );
  }

  // ─── EFFACER BADGE ────────────────────────────────────────────

  static Future<void> clearBadge() async {
    await AwesomeNotifications().resetGlobalBadge();
  }

  // ─── EFFACER NOTIF D'UNE CONVERSATION ────────────────────────

  static Future<void> clearConversationNotifications(
      String conversationId) async {
    await AwesomeNotifications()
        .cancel(conversationId.hashCode.abs() % 2147483647);
  }

  // ─── ÉCOUTE DES CLICS ────────────────────────────────────────
  // Appelle cette méthode dans main() après initialize()

  static void listenToNotifications() {
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onActionReceived,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onActionReceived(ReceivedAction action) async {
    final type = action.payload?['type'];
    final conversationId = action.payload?['conversationId'];
    final senderName = action.payload?['senderName'] ?? '';

    if (type == 'message' && conversationId != null) {
      // Navigue vers la conversation
      // Utilise un léger délai pour s'assurer que l'app est prête
      await Future.delayed(const Duration(milliseconds: 300));
      Get.toNamed('/chat/conversation',
          arguments: _NotifConvProxy(
            id: conversationId,
            userName: senderName,
          ));
    }
  }
}

// Proxy minimal pour naviguer depuis une notification
// (quand on n'a pas le ConversationModel complet)
class _NotifConvProxy {
  final String id;
  final String userName;
  _NotifConvProxy({required this.id, required this.userName});
}
