import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/notifications/controller/notification_controller.dart';
import 'package:rencontre/features/notifications/model/notification_model.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<NotificationController>()) {
      Get.put(NotificationController(), permanent: true);
    }
    final ctrl = Get.find<NotificationController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text('Notifications',
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        actions: [
          Obx(() => ctrl.unreadCount.value > 0
              ? TextButton(
                  onPressed: ctrl.markAllAsRead,
                  child: Text('Tout marquer lu',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13)))
              : const SizedBox.shrink()),
        ],
      ),
      body: Obx(() {
        if (ctrl.isLoading.value && ctrl.notifications.isEmpty) {
          return Center(
              child: CircularProgressIndicator(color: AppColors.accent));
        }
        if (ctrl.notifications.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none_rounded,
                    size: 56, color: AppColors.textMuted),
                const SizedBox(height: 12),
                Text('Aucune notification pour le moment',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 4),
                Text('Stories des comptes que tu suis',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: ctrl.loadNotifications,
          color: AppColors.accent,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: ctrl.notifications.length,
            itemBuilder: (_, i) =>
                _NotifTile(notif: ctrl.notifications[i], ctrl: ctrl),
          ),
        );
      }),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final NotificationModel notif;
  final NotificationController ctrl;
  const _NotifTile({required this.notif, required this.ctrl});

  IconData get _icon {
    switch (notif.type) {
      case 'new_story':
        return Icons.auto_awesome_mosaic_rounded;
      case 'like_story':
        return Icons.favorite_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Future<void> _onTap() async {
    await ctrl.markAsRead(notif.id);
    switch (notif.type) {
      case 'new_story':
      case 'like_story':
        _openStory();
        break;
      default:
        break;
    }
  }

  void _openStory() {
    if (notif.actorId == null || !Get.isRegistered<HomeController>()) return;
    final homeCtrl = Get.find<HomeController>();
    final stories = homeCtrl.storiesForUser(notif.actorId!);
    if (stories.isEmpty) return;
    Get.to(
      () => StoryViewerScreen(stories: stories, initialIndex: 0),
      transition: Transition.fadeIn,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: Container(
        color: notif.isRead
            ? Colors.transparent
            : AppColors.accent.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: ClipOval(
                    child: notif.actorPhotoUrl != null &&
                            notif.actorPhotoUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: notif.actorPhotoUrl!, fit: BoxFit.cover)
                        : Container(
                            color: AppColors.surface2,
                            child: Center(
                              child: Text(
                                notif.actorName.isNotEmpty
                                    ? notif.actorName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                    color: Colors.white54,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                  ),
                ),
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 2),
                    ),
                    child: Icon(_icon, size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                  children: [
                    TextSpan(
                        text: '${notif.actorName} ',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: notif.message),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              timeago.format(notif.createdAt, locale: 'fr'),
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            if (!notif.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: AppColors.accent, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
