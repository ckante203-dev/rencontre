import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(ChatListController());
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildSearchBar(),
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
              style: TextStyle(fontFamily: 'Syne', fontSize: 24,
                fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.surface2,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.edit_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            SizedBox(width: 12),
            Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
            SizedBox(width: 8),
            Text('Rechercher...', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

class _ConversationList extends GetView<ChatListController> {
  const _ConversationList();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoading.value) return _buildShimmer();
      if (controller.conversations.isEmpty) return _buildEmpty();

      return ListView.builder(
        physics: const BouncingScrollPhysics(),
        itemCount: controller.conversations.length,
        itemBuilder: (_, i) => _ConversationTile(conv: controller.conversations[i]),
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
              Container(width: 52, height: 52, decoration: const BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 12, width: 100, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 6),
                Container(height: 10, width: 160, decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(6))),
              ])),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Text('Aucune conversation', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
    );
  }
}

class _ConversationTile extends GetView<ChatListController> {
  final ConversationModel conv;
  const _ConversationTile({required this.conv});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.openConversation(conv),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: conv.unreadCount > 0 ? AppColors.surface2.withOpacity(0.5) : Colors.transparent,
        ),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                _Avatar(name: conv.userName, photoUrl: conv.userPhotoUrl, size: 52),
                if (conv.isOnline)
                  Positioned(
                    bottom: 1, right: 1,
                    child: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.online, shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(conv.userName,
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: conv.unreadCount > 0 ? AppColors.textPrimary : AppColors.textPrimary,
                        )),
                      const Spacer(),
                      if (conv.lastActivity != null)
                        Text(
                          timeago.format(conv.lastActivity!, locale: 'fr'),
                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(child: _buildLastMessage()),
                      if (conv.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: AppColors.gradientPink,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('${conv.unreadCount}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
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

  Widget _buildLastMessage() {
    final msg = conv.lastMessage;
    if (msg == null) return const SizedBox.shrink();

    if (msg.type == MessageType.snap) {
      final isMine = msg.isMine;
      final isOpened = msg.isOpened;
      return Row(
        children: [
          Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: isOpened ? AppColors.textMuted : AppColors.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            isMine ? (isOpened ? 'Snap ouvert' : 'Snap envoyé') : (isOpened ? 'Snap ouvert' : 'Snap reçu'),
            style: TextStyle(
              fontSize: 13,
              color: isOpened ? AppColors.textMuted : AppColors.accent,
              fontWeight: isOpened ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (msg.type == MessageType.audio) {
      return const Row(children: [
        Icon(Icons.mic_rounded, size: 14, color: AppColors.textMuted),
        SizedBox(width: 4),
        Text('Message vocal', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]);
    }

    return Text(
      msg.isMine ? 'Vous: ${msg.text ?? ''}' : (msg.text ?? ''),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        color: conv.unreadCount > 0 ? AppColors.textPrimary : AppColors.textMuted,
        fontWeight: conv.unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
      ),
    );
  }
}

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

    // Fallback initiale
    Widget fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors[idx],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Center(
        child: Text(letter,
          style: TextStyle(fontSize: size * 0.38,
            fontWeight: FontWeight.w800, color: Colors.white)),
      ),
    );

    // Si photo disponible → vraie photo
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: size, height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            fit: BoxFit.cover,
            width: size, height: size,
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          ),
        ),
      );
    }

    return fallback;
  }
}