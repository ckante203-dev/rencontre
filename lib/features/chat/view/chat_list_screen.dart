import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ FIX Bug 1 : Ne PAS faire Get.put ici — le controller est déjà
    // enregistré permanent dans MainNavigation.initState()
    // Get.put ici causait un reload complet à chaque retour sur l'écran
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const _FilterBar(),
            const Expanded(child: _ConversationList()),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Text('Messages',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surface2,
                border: Border.all(color: AppColors.border),
              ),
              child:
                  const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── FILTER BAR ───────────────────────────────────────────────────

class _FilterBar extends GetView<ChatListController> {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Obx(() => ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'Tous',
                icon: Icons.chat_bubble_outline_rounded,
                active: controller.activeFilter.value == ChatFilter.all,
                onTap: () => controller.setFilter(ChatFilter.all),
              ),
              _FilterChip(
                label: 'Non lus',
                icon: Icons.mark_chat_unread_outlined,
                active: controller.activeFilter.value == ChatFilter.unread,
                onTap: () => controller.setFilter(ChatFilter.unread),
                badge:
                    controller.totalUnread > 0 ? controller.totalUnread : null,
              ),
              _FilterChip(
                label: 'En ligne',
                icon: Icons.circle,
                iconColor: AppColors.online,
                active: controller.activeFilter.value == ChatFilter.online,
                onTap: () => controller.setFilter(ChatFilter.online),
              ),
              _FilterChip(
                label: 'Proches',
                icon: Icons.location_on_outlined,
                active: controller.activeFilter.value == ChatFilter.nearby,
                onTap: () => controller.setFilter(ChatFilter.nearby),
              ),
              _FilterChip(
                label: 'Médias',
                icon: Icons.photo_library_outlined,
                active: controller.activeFilter.value == ChatFilter.media,
                onTap: () => controller.setFilter(ChatFilter.media),
              ),
            ],
          )),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? iconColor;
  final bool active;
  final VoidCallback onTap;
  final int? badge;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    this.iconColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: active ? AppColors.gradientPink : null,
          color: active ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: active ? Colors.transparent : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: label == 'En ligne' ? 8 : 13,
                color:
                    active ? Colors.white : (iconColor ?? AppColors.textMuted)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active ? Colors.white : AppColors.textMuted)),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: 0.3)
                        : AppColors.accent,
                    borderRadius: BorderRadius.circular(10)),
                child: Text('$badge',
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── CONVERSATION LIST ────────────────────────────────────────────

class _ConversationList extends GetView<ChatListController> {
  const _ConversationList();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) return _buildShimmer();

      final list = controller.filteredConversations;
      if (list.isEmpty) return _buildEmpty();

      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: list.length,
        itemBuilder: (_, i) => _ConversationTile(conv: list[i]),
      );
    });
  }

  Widget _buildShimmer() {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.border,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                      color: AppColors.surface2, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Container(
                        height: 12,
                        width: 100,
                        decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 6),
                    Container(
                        height: 10,
                        width: 160,
                        decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(6))),
                  ])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final filter = controller.activeFilter.value;
    final msgs = {
      ChatFilter.unread: 'Aucun message non lu',
      ChatFilter.online: 'Personne en ligne',
      ChatFilter.nearby: 'Aucun contact proche',
      ChatFilter.media: 'Aucun échange de médias',
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(msgs[filter] ?? 'Aucune conversation',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 15)),
        ],
      ),
    );
  }
}

// ─── CONVERSATION TILE ────────────────────────────────────────────

class _ConversationTile extends GetView<ChatListController> {
  final ConversationModel conv;
  const _ConversationTile({required this.conv});

  void _showOptions(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ConversationOptions(conv: conv),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.openConversation(conv),
      onLongPress: () => _showOptions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: conv.unreadCount > 0
              ? AppColors.surface2.withValues(alpha: 0.5)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Stack(
              children: [
                _Avatar(
                    name: conv.userName, photoUrl: conv.userPhotoUrl, size: 52),
                if (conv.isOnline)
                  Positioned(
                    bottom: 1,
                    right: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: AppColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 2)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(conv.userName,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      if (conv.isPinned)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin,
                              size: 13, color: AppColors.accent),
                        ),
                      if (conv.lastActivity != null)
                        Text(_formatTime(conv.lastActivity!),
                            style: TextStyle(
                              fontSize: 11,
                              color: conv.unreadCount > 0
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              fontWeight: conv.unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            )),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(child: _buildLastMessage()),
                      if (conv.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              gradient: AppColors.gradientPink,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('${conv.unreadCount}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    if (diff == 1) return 'Hier';
    if (diff < 7) {
      const j = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return j[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}';
  }

  Widget _buildLastMessage() {
    final msg = conv.lastMessage;
    if (msg == null) return const SizedBox.shrink();

    if (msg.type == MessageType.snap) {
      final isOpened = msg.isOpened;
      return Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
                color: isOpened ? AppColors.textMuted : AppColors.accent,
                borderRadius: BorderRadius.circular(2)),
          ),
          Text(
              msg.isMine
                  ? (isOpened ? 'Snap ouvert' : 'Snap envoyé')
                  : (isOpened ? 'Snap ouvert' : 'Snap reçu'),
              style: TextStyle(
                  fontSize: 13,
                  color: isOpened ? AppColors.textMuted : AppColors.accent,
                  fontWeight: isOpened ? FontWeight.w400 : FontWeight.w600)),
        ],
      );
    }

    if (msg.type == MessageType.audio) {
      return const Row(children: [
        Icon(Icons.mic_rounded, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Message vocal',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    if (msg.type == MessageType.image) {
      return const Row(children: [
        Icon(Icons.photo_outlined, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Photo',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    if (msg.type == MessageType.location) {
      return const Row(children: [
        Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Localisation',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    return Text(
      msg.isMine ? 'Vous: ${msg.text ?? ''}' : (msg.text ?? ''),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 13,
          color: conv.unreadCount > 0
              ? AppColors.textPrimary
              : AppColors.textMuted,
          fontWeight: conv.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400),
    );
  }
}

// ─── CONVERSATION OPTIONS ─────────────────────────────────────────

class _ConversationOptions extends GetView<ChatListController> {
  final ConversationModel conv;
  const _ConversationOptions({required this.conv});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          Row(
            children: [
              _Avatar(
                  name: conv.userName, photoUrl: conv.userPhotoUrl, size: 44),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conv.userName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  Text(conv.isOnline ? 'En ligne' : 'Hors ligne',
                      style: TextStyle(
                          fontSize: 12,
                          color: conv.isOnline
                              ? AppColors.online
                              : AppColors.textMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 8),
          _Option(
            icon: Icons.mark_chat_read_outlined,
            label: conv.unreadCount > 0
                ? 'Marquer comme lu'
                : 'Marquer comme non lu',
            onTap: () {
              Get.back();
              controller.toggleReadStatus(conv);
            },
          ),
          _Option(
            icon: conv.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            label: conv.isPinned ? 'Désépingler' : 'Épingler en haut',
            onTap: () {
              Get.back();
              controller.togglePin(conv);
            },
          ),
          _Option(
            icon: Icons.notifications_off_outlined,
            label: 'Désactiver les notifications',
            onTap: () => Get.back(),
          ),
          _Option(
            icon: Icons.archive_outlined,
            label: 'Archiver la conversation',
            onTap: () => Get.back(),
          ),
          _Option(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer la conversation',
            color: const Color(0xFFFF3B30),
            onTap: () {
              Get.back();
              _confirmDelete(context);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer la conversation',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        content: Text(
            'La conversation avec ${conv.userName} sera supprimée définitivement.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: const Text('Annuler',
                  style: TextStyle(color: AppColors.textMuted))),
          TextButton(
              onPressed: () {
                Get.back();
                controller.deleteConversation(conv.id);
              },
              child: const Text('Supprimer',
                  style: TextStyle(
                      color: Color(0xFFFF3B30), fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _Option(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: c, size: 22),
      title: Text(label,
          style:
              TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w500)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

// ─── AVATAR ───────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const _Avatar({required this.name, this.photoUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = [
      [const Color(0xFFFF6B6B), const Color(0xFFFECA57)],
      [const Color(0xFF48DBFB), const Color(0xFFFF9FF3)],
      [const Color(0xFFFF9F43), const Color(0xFFEE5A24)],
      [const Color(0xFFA29BFE), const Color(0xFF6C5CE7)],
      [const Color(0xFFFD79A8), const Color(0xFFE84393)],
      [const Color(0xFF55EFC4), const Color(0xFF00B894)],
    ];
    final idx = name.hashCode.abs() % colors.length;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              colors: colors[idx],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: Center(
          child: Text(letter,
              style: TextStyle(
                  fontSize: size * 0.38,
                  fontWeight: FontWeight.w800,
                  color: Colors.white))),
    );

    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          placeholder: (_, __) => fallback,
          errorWidget: (_, __, ___) => fallback,
        ),
      );
    }
    return fallback;
  }
}
