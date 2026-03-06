import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late ConversationController ctrl;

  @override
  void initState() {
    super.initState();
    // ✅ Put avec tag unique pour éviter les conflits
    final conv = Get.arguments as ConversationModel;
    ctrl = Get.put(ConversationController(), tag: conv.id);
    ctrl.init(conv);
  }

  @override
  void dispose() {
    Get.delete<ConversationController>(tag: ctrl.conversation.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _MessageList(ctrl: ctrl)),
          _InputBar(ctrl: ctrl),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final conv = ctrl.conversation;
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      titleSpacing: 0,
      leading: GestureDetector(
        onTap: () => Get.back(),
        child: const Icon(Icons.arrow_back_ios_rounded,
          size: 20, color: Colors.white),
      ),
      title: Row(
        children: [
          Stack(
            children: [
              _Avatar(name: conv.userName, size: 36, photoUrl: conv.userPhotoUrl),
              if (conv.isOnline)
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.online, shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(conv.userName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                  fontFamily: 'Syne',
                )),
              Text(
                conv.isOnline ? 'En ligne' : 'Hors ligne',
                style: TextStyle(fontSize: 11,
                  color: conv.isOnline
                    ? AppColors.online : AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.videocam_outlined, color: Colors.white),
          onPressed: () {}),
        IconButton(
          icon: const Icon(Icons.phone_outlined, color: Colors.white),
          onPressed: () {}),
        const SizedBox(width: 4),
      ],
    );
  }
}

// ─── MESSAGE LIST ─────────────────────────────────────────────────

class _MessageList extends StatelessWidget {
  final ConversationController ctrl;
  const _MessageList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoading.value) return _buildShimmer();
      if (ctrl.messages.isEmpty) return _buildEmpty();

      return ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        physics: const BouncingScrollPhysics(),
        itemCount: ctrl.messages.length,
        itemBuilder: (_, i) {
          final msgs = ctrl.messages.reversed.toList();
          final msg = msgs[i];
          final prev = i + 1 < msgs.length ? msgs[i + 1] : null;
          final showTime = prev == null ||
            msg.createdAt.difference(prev.createdAt).inMinutes.abs() > 10;
          return Column(
            children: [
              if (showTime) _TimeLabel(date: msg.createdAt),
              _MessageBubble(msg: msg, ctrl: ctrl),
            ],
          );
        },
      );
    });
  }

  Widget _buildShimmer() {
    return ListView.builder(
      reverse: true, padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, i) => Shimmer.fromColors(
        baseColor: AppColors.surface2, highlightColor: AppColors.border,
        child: Align(
          alignment: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 160 + (i * 10.0), height: 40,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: AppColors.surface2,
              borderRadius: BorderRadius.circular(18)),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Icon(Icons.chat_bubble_outline_rounded,
              size: 52, color: Colors.white),
          ),
          const SizedBox(height: 14),
          const Text('Dis bonjour ! 👋',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
              color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Commence la conversation',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ─── TIME LABEL ───────────────────────────────────────────────────

class _TimeLabel extends StatelessWidget {
  final DateTime date;
  const _TimeLabel({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(timeago.format(date, locale: 'fr'),
        style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
    );
  }
}

// ─── MESSAGE BUBBLE ───────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final ConversationController ctrl;
  const _MessageBubble({required this.msg, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isMine = msg.senderId == ctrl.myId;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            _Avatar(name: ctrl.conversation.userName, size: 28, photoUrl: ctrl.conversation.userPhotoUrl),
            const SizedBox(width: 6),
          ],
          _buildContent(isMine, context),
          if (isMine) ...[
            const SizedBox(width: 4),
            _StatusIcon(status: msg.status),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(bool isMine, BuildContext context) {
    switch (msg.type) {
      case MessageType.snap:
        return _SnapBubble(msg: msg, isMine: isMine,
          onTap: () => ctrl.openSnap(msg));
      case MessageType.audio:
        return _AudioBubble(msg: msg, isMine: isMine);
      case MessageType.image:
        return _ImageBubble(msg: msg, isMine: isMine);
      case MessageType.location:
        return _LocationBubble(msg: msg, isMine: isMine);
      default:
        return _TextBubble(msg: msg, isMine: isMine);
    }
  }
}

// ─── BULLES ───────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _TextBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.68),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: isMine ? AppColors.gradientPink : null,
        color: isMine ? null : AppColors.surface2,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMine ? 18 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 18),
        ),
      ),
      child: Text(msg.text ?? '',
        style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.3)),
    );
  }
}

class _SnapBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  final VoidCallback onTap;
  const _SnapBubble({required this.msg, required this.isMine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = msg.isOpened ? AppColors.textMuted : AppColors.accent;
    return GestureDetector(
      onTap: isMine ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12,
              decoration: BoxDecoration(color: color,
                borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Text(
              isMine
                ? (msg.isOpened ? 'Snap ouvert' : 'Snap envoyé')
                : (msg.isOpened ? 'Snap ouvert' : 'Ouvrir le snap'),
              style: TextStyle(fontSize: 13,
                fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

class _AudioBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _AudioBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: isMine ? AppColors.gradientPink : null,
        color: isMine ? null : AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Row(
            children: List.generate(12, (i) => Container(
              width: 3, height: 8 + (i % 4) * 4.0,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(2)),
            )),
          ),
          const SizedBox(width: 8),
          Text('0:${(msg.audioDurationSec ?? 5).toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 12, color: Colors.white)),
        ],
      ),
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _ImageBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: msg.mediaUrl!,
          width: 220, height: 220, fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 220, height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: AppColors.surface2),
            child: const Center(child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2))),
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
    width: 220, height: 220,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: AppColors.gradientPink),
    child: const Center(
      child: Icon(Icons.image_rounded, size: 48, color: Colors.white)));
}

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5,
            color: AppColors.textMuted));
      case MessageStatus.sent:
        // 1 trait gris = envoyé
        return const Icon(Icons.check_rounded, size: 15,
          color: AppColors.textMuted);
      case MessageStatus.delivered:
        // 2 traits gris = délivré
        return const Icon(Icons.done_all_rounded, size: 15,
          color: AppColors.textMuted);
      case MessageStatus.read:
        // 2 traits roses = lu
        return ShaderMask(
          shaderCallback: (b) => AppColors.gradientPink.createShader(b),
          child: const Icon(Icons.done_all_rounded, size: 15,
            color: Colors.white),
        );
    }
  }
}

// ─── INPUT BAR ────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final ConversationController ctrl;
  const _InputBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(12, 8, 12,
        MediaQuery.of(context).viewInsets.bottom + 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Obx(() => ctrl.showAttachMenu.value
              ? _AttachMenu(ctrl: ctrl) : const SizedBox.shrink()),
            Row(
              children: [
                GestureDetector(
                  onTap: ctrl.toggleAttachMenu,
                  child: Obx(() => Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ctrl.showAttachMenu.value
                        ? AppColors.gradientPink : null,
                      color: ctrl.showAttachMenu.value
                        ? null : AppColors.surface2,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      ctrl.showAttachMenu.value
                        ? Icons.close_rounded : Icons.add_rounded,
                      size: 20, color: Colors.white),
                  )),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TextField(
                      controller: ctrl.textController,
                      style: const TextStyle(fontSize: 15,
                        color: AppColors.textPrimary),
                      maxLines: 4, minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => ctrl.sendText(),
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        hintStyle: TextStyle(color: AppColors.textMuted,
                          fontSize: 15),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Obx(() {
                  final hasText = ctrl.inputText.value.trim().isNotEmpty;
                  final isRec = ctrl.isRecording.value;
                  return GestureDetector(
                    onTap: hasText ? ctrl.sendText : null,
                    onLongPressStart: hasText ? null : (_) => ctrl.startRecording(),
                    onLongPressEnd: hasText ? null : (_) => ctrl.stopRecording(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isRec ? 54 : 42,
                      height: isRec ? 54 : 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isRec ? const Color(0xFFFF3CAC) : null,
                        gradient: isRec ? null : const LinearGradient(
                          colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
                        boxShadow: isRec ? [BoxShadow(
                          color: const Color(0xFFFF3CAC).withValues(alpha: 0.5),
                          blurRadius: 16, spreadRadius: 2)] : null,
                      ),
                      child: Icon(
                        hasText ? Icons.send_rounded
                          : (isRec ? Icons.stop_rounded : Icons.mic_rounded),
                        size: 20, color: Colors.white),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachMenu extends StatelessWidget {
  final ConversationController ctrl;
  const _AttachMenu({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _AttachItem(icon: Icons.camera_alt_rounded, label: 'Caméra',
            color: AppColors.accent,
            onTap: () => ctrl.envoyerPhoto(camera: true)),
          _AttachItem(icon: Icons.photo_library_rounded, label: 'Galerie',
            color: AppColors.accent2,
            onTap: () => ctrl.envoyerPhoto(camera: false)),
          _AttachItem(icon: Icons.auto_awesome_rounded, label: 'Snap',
            color: AppColors.accent3, onTap: ctrl.sendSnap),
          _AttachItem(icon: Icons.location_on_rounded, label: 'Lieu',
            color: const Color(0xFFFFD93D), onTap: ctrl.envoyerLocalisation),
        ],
      ),
    );
  }
}

class _AttachItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachItem({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15), shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11,
            color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── LOCALISATION BUBBLE ──────────────────────────────────────────

class _LocationBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _LocationBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Ouvre Google Maps
        if (msg.text != null) {
          Get.snackbar('📍 Localisation', 'Ouvre dans Maps...',
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF13131A),
            colorText: Colors.white);
        }
      },
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: isMine ? AppColors.gradientPink : null,
          color: isMine ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded,
                    size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Ma localisation',
                    style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Mini carte simulée
            Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.1),
                    Colors.white.withValues(alpha: 0.05)
                  ],
                ),
              ),
              child: const Center(
                child: Icon(Icons.map_rounded, size: 36,
                  color: Colors.white54),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Appuie pour ouvrir Maps',
              style: TextStyle(fontSize: 10, color: Colors.white60)),
          ],
        ),
      ),
    );
  }
}

// ─── AVATAR ───────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? photoUrl;
  const _Avatar({required this.name, required this.size, this.photoUrl});

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

    // Si photo disponible → affiche la vraie photo
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return Container(
        width: size, height: size,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: photoUrl!,
            fit: BoxFit.cover,
            width: size, height: size,
            placeholder: (_, __) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: colors[idx],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Center(child: Text(letter,
                style: TextStyle(fontSize: size * 0.38,
                  fontWeight: FontWeight.w800, color: Colors.white)))),
            errorWidget: (_, __, ___) => Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: colors[idx],
                  begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Center(child: Text(letter,
                style: TextStyle(fontSize: size * 0.38,
                  fontWeight: FontWeight.w800, color: Colors.white)))),
          ),
        ),
      );
    }

    // Sinon → initiale avec gradient
    return Container(
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
  }
}