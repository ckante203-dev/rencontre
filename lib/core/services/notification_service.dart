import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Initialise les notifications au démarrage
  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null, // null = icône par défaut de l'app
      [
        NotificationChannel(
          channelKey: 'messages',
          channelName: 'Messages',
          channelDescription: 'Notifications de nouveaux messages',
          defaultColor: const Color(0xFFFF3CAC),
          ledColor: const Color(0xFFFF3CAC),
          importance: NotificationImportance.High,
          channelShowBadge: true, // 🔴 Badge sur l'icône
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
      ],
      debug: false,
    );

    // Demande permission
    await AwesomeNotifications().requestPermissionToSendNotifications();
  }

  // Envoie une notification de message
  static Future<void> showMessageNotification({
    required String senderName,
    required String message,
    String? senderPhoto,
    required String conversationId,
  }) async {
    final bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) return;

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: conversationId.hashCode.abs(),
        channelKey: 'messages',
        title: senderName,
        body: message,
        largeIcon: senderPhoto,
        notificationLayout: NotificationLayout.Messaging,
        category: NotificationCategory.Message,
        wakeUpScreen: true,
        autoDismissible: true,
        badge: 1,
        payload: {'conversationId': conversationId},
      ),
    );
  }

  // Envoie une notification de match
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
      ),
    );
  }

  // Remet le badge à 0 quand l'app est ouverte
  static Future<void> clearBadge() async {
    await AwesomeNotifications().resetGlobalBadge();
  }

  // Écoute les clics sur les notifications
  static void listenToNotifications(Function(String?) onConversationOpen) {
    AwesomeNotifications().setListeners(
      onActionReceivedMethod: (action) async {
        final conversationId = action.payload?['conversationId'];
        onConversationOpen(conversationId);
      },
    );
  }
}