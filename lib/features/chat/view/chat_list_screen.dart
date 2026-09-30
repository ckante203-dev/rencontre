import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            const _SearchBar(),
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
          const _BoutonRecherche(),
        ],
      ),
    );
  }
}

// ─── BOUTON RECHERCHE ─────────────────────────────────────────────

class _BoutonRecherche extends GetView<ChatListController> {
  const _BoutonRecherche();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final actif = controller.isSearching.value;
      return GestureDetector(
        onTap: () {
          controller.isSearching.toggle();
          if (!controller.isSearching.value) {
            controller.searchQuery.value = '';
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: actif ? AppColors.gradientPink : null,
            color: actif ? null : AppColors.surface2,
            border: Border.all(
                color: actif ? Colors.transparent : AppColors.border),
          ),
          child: Icon(actif ? Icons.close_rounded : Icons.search_rounded,
              size: 19, color: Colors.white),
        ),
      );
    });
  }
}

// ─── SEARCH BAR ───────────────────────────────────────────────────

class _SearchBar extends GetView<ChatListController> {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isSearching = controller.isSearching.value;
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: isSearching ? 48 : 0,
        child: isSearching
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: TextField(
                    autofocus: true,
                    style:
                        TextStyle(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Rechercher une conversation...',
                      hintStyle:
                          TextStyle(color: AppColors.textMuted, fontSize: 14),
                      prefixIcon: Icon(Icons.search_rounded,
                          color: AppColors.textMuted, size: 18),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    ),
                    onChanged: (v) => controller.searchQuery.value = v,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      );
    });
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
    return GetBuilder<ChatListController>(
      builder: (ctrl) => Obx(() {
        if (ctrl.isLoading.value) return _buildShimmer();

        final list = ctrl.filteredConversations;

        if (list.isEmpty) {
          if (ctrl.searchQuery.value.isNotEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off_rounded,
                      size: 48, color: AppColors.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'Aucun résultat pour "${ctrl.searchQuery.value}"',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          return _buildEmpty();
        }

        return ListView.separated(
          physics: const BouncingScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            thickness: 0.5,
            indent: 80,
            endIndent: 16,
            color: AppColors.border.withValues(alpha: 0.6),
          ),
          itemBuilder: (_, i) => _ConversationTile(conv: list[i]),
        );
      }),
    );
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
                  decoration: BoxDecoration(
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
      ChatFilter.online: 'Personne en ligne pour le moment',
    };
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(msgs[filter] ?? 'Aucune conversation',
              style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
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
            _AvatarWithStoryRing(
              userId: conv.userId,
              name: conv.userName,
              photoUrl: conv.userPhotoUrl,
              size: 52,
              isOnline: conv.isOnline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(conv.userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                      Obx(() => controller.sourdineIds.contains(conv.id)
                          ? Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.notifications_off_rounded,
                                  size: 13, color: AppColors.textMuted),
                            )
                          : const SizedBox.shrink()),
                      if (conv.isPinned)
                        Padding(
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
    var msg = conv.lastMessage;
    // Historique effacé sur cet appareil : l'aperçu ne le montre plus.
    final effaceAvant = ConversationController.historiqueEffaceAvant(conv.id);
    if (msg != null &&
        effaceAvant != null &&
        !msg.createdAt.isAfter(effaceAvant)) {
      msg = null;
    }
    // ✅ Tous les messages ont expiré (règle éphémère) : la conversation
    // reste, avec un aperçu neutre.
    if (msg == null) {
      return Text('Aucun nouveau message',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted));
    }

    // ✅ FIX : isMine est maintenant une méthode qui prend l'ID de
    // l'utilisateur courant (controller.myId), au lieu d'un getter
    // cassé qui comparait à la chaîne "me" et ne fonctionnait jamais.
    final mine = msg.isMine(controller.myId);

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
              mine
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
      return Row(children: [
        Icon(Icons.mic_rounded, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Message vocal',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    if (msg.type == MessageType.image) {
      return Row(children: [
        Icon(Icons.photo_outlined, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Photo',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    if (msg.type == MessageType.location) {
      return Row(children: [
        Icon(Icons.location_on_outlined, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Localisation',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    return Text(
      mine ? 'Vous: ${msg.text ?? ''}' : (msg.text ?? ''),
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
          Divider(color: AppColors.border, height: 1),
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
            icon: controller.sourdineIds.contains(conv.id)
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            label: controller.sourdineIds.contains(conv.id)
                ? 'Réactiver les notifications'
                : 'Couper les notifications',
            onTap: () {
              Get.back();
              controller.basculerSourdine(conv);
            },
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
            style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        actions: [
          TextButton(
              onPressed: () => Get.back(),
              child: Text('Annuler',
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

// ─── AVATAR AVEC ANNEAU DE STORY (façon WhatsApp statut / Snap) ───

class _AvatarWithStoryRing extends StatelessWidget {
  final String userId;
  final String name;
  final String? photoUrl;
  final double size;
  final bool isOnline;

  const _AvatarWithStoryRing({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.size,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = _Avatar(name: name, size: size, photoUrl: photoUrl);

    if (!Get.isRegistered<HomeController>()) {
      return _withOnlineDot(avatar);
    }
    final homeCtrl = Get.find<HomeController>();

    return Obx(() {
      final hasStory = homeCtrl.userHasActiveStory(userId);
      final storySeen = homeCtrl.userStoryIsSeen(userId);

      if (!hasStory) return _withOnlineDot(avatar);

      return GestureDetector(
        onTap: () => _openStory(homeCtrl),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(2.2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: storySeen
                    ? null
                    : LinearGradient(
                        colors: [
                          AppColors.accent,
                          AppColors.accent2,
                          AppColors.accent3,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: storySeen ? AppColors.border : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.bg,
                ),
                child: avatar,
              ),
            ),
            if (isOnline)
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
      );
    });
  }

  Widget _withOnlineDot(Widget avatar) {
    if (!isOnline) return avatar;
    return Stack(
      children: [
        avatar,
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
    );
  }

  void _openStory(HomeController homeCtrl) {
    final userStories = homeCtrl.storiesForUser(userId);
    if (userStories.isEmpty) return;
    Get.to(
      () => StoryViewerScreen(stories: userStories, initialIndex: 0),
      transition: Transition.fadeIn,
    );
    homeCtrl.markStoryAsSeen(userStories.first.id);
  }
}
