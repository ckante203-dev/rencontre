import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';

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
              _Avatar(
                  name: conv.userName, size: 36, photoUrl: conv.userPhotoUrl),
              if (conv.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
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
                      fontFamily: 'Syne')),
              Text(
                conv.isOnline ? 'En ligne' : 'Hors ligne',
                style: TextStyle(
                    fontSize: 11,
                    color:
                        conv.isOnline ? AppColors.online : AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
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

      final msgs = ctrl.messages.toList();
      final items = <_ChatItem>[];

      for (int i = 0; i < msgs.length; i++) {
        final msg = msgs[i];
        final prev = i > 0 ? msgs[i - 1] : null;

        final bool showDate =
            prev == null || !_isSameDay(prev.createdAt, msg.createdAt);
        if (showDate) items.add(_ChatItem.dateSep(msg.createdAt));

        final bool showTime = prev != null &&
            !showDate &&
            msg.createdAt.difference(prev.createdAt).inMinutes > 10;
        if (showTime) items.add(_ChatItem.timeSep(msg.createdAt));

        items.add(_ChatItem.message(msg));
      }

      return ListView.builder(
        reverse: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[items.length - 1 - i];
          if (item.isDateSep) return _DateLabel(date: item.date!);
          if (item.isTimeSep) return _TimeLabel(date: item.date!);
          return _MessageBubble(msg: item.msg!, ctrl: ctrl);
        },
      );
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildShimmer() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, i) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.border,
        child: Align(
          alignment: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 160 + (i * 10.0),
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.surface2,
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
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('Commence la conversation',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ─── CHAT ITEM ────────────────────────────────────────────────────

class _ChatItem {
  final MessageModel? msg;
  final DateTime? date;
  final bool isDateSep;
  final bool isTimeSep;

  const _ChatItem._(
      {this.msg, this.date, this.isDateSep = false, this.isTimeSep = false});

  factory _ChatItem.message(MessageModel m) => _ChatItem._(msg: m);
  factory _ChatItem.dateSep(DateTime d) =>
      _ChatItem._(date: d, isDateSep: true);
  factory _ChatItem.timeSep(DateTime d) =>
      _ChatItem._(date: d, isTimeSep: true);
}

// ─── DATE LABEL ───────────────────────────────────────────────────

class _DateLabel extends StatelessWidget {
  final DateTime date;
  const _DateLabel({required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    const jours = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche'
    ];
    const mois = [
      'jan',
      'fév',
      'mars',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sep',
      'oct',
      'nov',
      'déc'
    ];
    if (diff < 7) return jours[date.weekday - 1];
    return '${jours[date.weekday - 1]} ${date.day} ${mois[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(_label(),
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border, thickness: 0.5)),
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
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text('$h:$m',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ),
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
    final h = msg.createdAt.hour.toString().padLeft(2, '0');
    final m = msg.createdAt.minute.toString().padLeft(2, '0');

    return GestureDetector(
      onLongPress: () => ctrl.showMessageOptions(context, msg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment:
              isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              _Avatar(
                  name: ctrl.conversation.userName,
                  size: 28,
                  photoUrl: ctrl.conversation.userPhotoUrl),
              const SizedBox(width: 6),
            ],
            Column(
              crossAxisAlignment:
                  isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // ── Réponse à une story (preview style WhatsApp) ──
                if (msg.storyReply != null)
                  _StoryReplyPreview(
                      storyReply: msg.storyReply!, isMine: isMine),
                // ── Réponse à un message normal ──────────────────
                if (msg.replyTo != null && msg.storyReply == null)
                  _ReplyPreview(
                      replyTo: msg.replyTo!, isMine: isMine, ctrl: ctrl),
                _buildContent(isMine, context),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$h:$m',
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textMuted)),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _StatusIcon(status: msg.status),
                    ],
                  ],
                ),
              ],
            ),
            if (isMine) const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isMine, BuildContext context) {
    switch (msg.type) {
      case MessageType.snap:
        return _SnapBubble(
            msg: msg, isMine: isMine, onTap: () => ctrl.openSnap(msg));
      case MessageType.audio:
        return _AudioBubble(msg: msg, isMine: isMine, ctrl: ctrl);
      case MessageType.image:
        return _ImageBubble(msg: msg, isMine: isMine);
      case MessageType.location:
        return _LocationBubble(msg: msg, isMine: isMine);
      default:
        return _TextBubble(msg: msg, isMine: isMine);
    }
  }
}

// ─── PREVIEW RÉPONSE À UNE STORY (style WhatsApp) ────────────────
//
// Affiché au-dessus de la bulle de texte quand le message est
// une réponse à une story (msg.storyReply != null).

class _StoryReplyPreview extends StatelessWidget {
  final StoryReplyData storyReply;
  final bool isMine;
  const _StoryReplyPreview({required this.storyReply, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white.withOpacity(0.5) : AppColors.accent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Miniature de la story
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              bottomLeft: Radius.circular(10),
            ),
            child: SizedBox(
              width: 44,
              height: 56,
              child: CachedNetworkImage(
                imageUrl: storyReply.storyPreviewUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surface,
                  child: Icon(
                    storyReply.storyIsVideo
                        ? Icons.videocam_rounded
                        : Icons.photo_camera_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
          // Texte à droite
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        storyReply.storyIsVideo
                            ? Icons.videocam_rounded
                            : Icons.photo_camera_rounded,
                        size: 11,
                        color: isMine ? Colors.white70 : AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        storyReply.storyIsVideo ? 'Vidéo' : 'Photo',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isMine ? Colors.white70 : AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    storyReply.storyOwnerName.isNotEmpty
                        ? 'Story de ${storyReply.storyOwnerName}'
                        : 'Story',
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── REPLY PREVIEW (réponse à un message normal) ──────────────────

class _ReplyPreview extends StatelessWidget {
  final MessageModel replyTo;
  final bool isMine;
  final ConversationController ctrl;
  const _ReplyPreview(
      {required this.replyTo, required this.isMine, required this.ctrl});

  String get _preview {
    switch (replyTo.type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.audio:
        return '🎤 Message vocal';
      case MessageType.snap:
        return '📸 Snap';
      case MessageType.location:
        return '📍 Localisation';
      default:
        return replyTo.text ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplyMine = replyTo.senderId == ctrl.myId;
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isMine ? Colors.white.withOpacity(0.6) : AppColors.accent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isReplyMine ? 'Vous' : ctrl.conversation.userName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isMine ? Colors.white.withOpacity(0.8) : AppColors.accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(_preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
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
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
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
          style:
              const TextStyle(fontSize: 15, color: Colors.white, height: 1.3)),
    );
  }
}

class _SnapBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  final VoidCallback onTap;
  const _SnapBubble(
      {required this.msg, required this.isMine, required this.onTap});

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
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Text(
              isMine
                  ? (msg.isOpened ? 'Snap ouvert' : 'Snap envoyé')
                  : (msg.isOpened ? 'Snap ouvert' : 'Ouvrir le snap'),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── AUDIO BUBBLE ────────────────────────────────────────────────

class _AudioBubble extends StatefulWidget {
  final MessageModel msg;
  final bool isMine;
  final ConversationController ctrl;
  const _AudioBubble(
      {required this.msg, required this.isMine, required this.ctrl});

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  bool _playing = false;

  Future<void> _toggle() async {
    if (_playing) {
      await widget.ctrl.stopAudio();
      setState(() => _playing = false);
    } else {
      if (widget.msg.mediaUrl != null && widget.msg.mediaUrl!.isNotEmpty) {
        setState(() => _playing = true);
        await widget.ctrl.playAudio(widget.msg.mediaUrl!);
        if (mounted) setState(() => _playing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.msg.audioDurationSec ?? 0;
    final min = (dur ~/ 60).toString().padLeft(2, '0');
    final sec = (dur % 60).toString().padLeft(2, '0');

    return GestureDetector(
      onTap: _toggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: widget.isMine ? AppColors.gradientPink : null,
          color: widget.isMine ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(_playing),
                size: 24,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              children: List.generate(16, (i) {
                final heights = [
                  8.0,
                  14.0,
                  10.0,
                  18.0,
                  12.0,
                  16.0,
                  8.0,
                  20.0,
                  10.0,
                  14.0,
                  18.0,
                  8.0,
                  12.0,
                  16.0,
                  10.0,
                  8.0
                ];
                return Container(
                  width: 3,
                  height: _playing ? heights[i] : heights[i] * 0.6,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(_playing ? 1.0 : 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
            const SizedBox(width: 8),
            Text('$min:$sec',
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500)),
          ],
        ),
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
          width: 220,
          height: 220,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: AppColors.surface2),
            child: const Center(
                child: CircularProgressIndicator(
                    color: AppColors.accent, strokeWidth: 2)),
          ),
          errorWidget: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
      width: 220,
      height: 220,
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
        return const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textMuted));
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded,
            size: 13, color: AppColors.textMuted);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded,
            size: 13, color: AppColors.textMuted);
      case MessageStatus.read:
        return ShaderMask(
          shaderCallback: (b) => AppColors.gradientPink.createShader(b),
          child:
              const Icon(Icons.done_all_rounded, size: 13, color: Colors.white),
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
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Barre de réponse (message normal OU story)
            Obx(() => ctrl.replyToMessage.value != null
                ? _ReplyBar(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.isRecording.value
                ? _RecordingIndicator(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.showAttachMenu.value
                ? _AttachMenu(ctrl: ctrl)
                : const SizedBox.shrink()),
            Row(
              children: [
                GestureDetector(
                  onTap: ctrl.toggleAttachMenu,
                  child: Obx(() => Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: ctrl.showAttachMenu.value
                              ? AppColors.gradientPink
                              : null,
                          color: ctrl.showAttachMenu.value
                              ? null
                              : AppColors.surface2,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Icon(
                          ctrl.showAttachMenu.value
                              ? Icons.close_rounded
                              : Icons.add_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
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
                      style: const TextStyle(
                          fontSize: 15, color: AppColors.textPrimary),
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => ctrl.sendText(),
                      decoration: const InputDecoration(
                        hintText: 'Message...',
                        hintStyle:
                            TextStyle(color: AppColors.textMuted, fontSize: 15),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    onLongPressStart:
                        hasText ? null : (_) => ctrl.startRecording(),
                    onLongPressEnd:
                        hasText ? null : (_) => ctrl.stopRecording(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: isRec ? 54 : 42,
                      height: isRec ? 54 : 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isRec ? const Color(0xFFFF3CAC) : null,
                        gradient: isRec
                            ? null
                            : const LinearGradient(
                                colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
                        boxShadow: isRec
                            ? [
                                BoxShadow(
                                    color: const Color(0xFFFF3CAC)
                                        .withOpacity(0.5),
                                    blurRadius: 16,
                                    spreadRadius: 2)
                              ]
                            : null,
                      ),
                      child: Icon(
                        hasText
                            ? Icons.send_rounded
                            : (isRec ? Icons.stop_rounded : Icons.mic_rounded),
                        size: 20,
                        color: Colors.white,
                      ),
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

// ─── REPLY BAR (au-dessus de l'input) ────────────────────────────
// Affiche soit la preview d'un message normal, soit la preview d'une story

class _ReplyBar extends StatelessWidget {
  final ConversationController ctrl;
  const _ReplyBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final msg = ctrl.replyToMessage.value!;
    final storyReply = msg.storyReply;

    // ── Réponse à une story : afficher la miniature
    if (storyReply != null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border:
              const Border(left: BorderSide(color: AppColors.accent, width: 3)),
        ),
        child: Row(
          children: [
            // Miniature
            ClipRRect(
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10)),
              child: SizedBox(
                width: 44,
                height: 56,
                child: CachedNetworkImage(
                  imageUrl: storyReply.storyPreviewUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.surface,
                    child: Icon(
                      storyReply.storyIsVideo
                          ? Icons.videocam_rounded
                          : Icons.photo_camera_rounded,
                      color: Colors.white38,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Icon(
                        storyReply.storyIsVideo
                            ? Icons.videocam_rounded
                            : Icons.photo_camera_rounded,
                        size: 11,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 4),
                      Text(storyReply.storyIsVideo ? 'Vidéo' : 'Photo',
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent)),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      storyReply.storyOwnerName.isNotEmpty
                          ? 'Story de ${storyReply.storyOwnerName}'
                          : 'Story',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.white60),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: ctrl.cancelReply,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    // ── Réponse à un message normal
    final isReplyMine = msg.senderId == ctrl.myId;
    final preview = _getPreview(msg);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border:
            const Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReplyMine ? 'Vous' : ctrl.conversation.userName,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent),
                ),
                const SizedBox(height: 2),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          GestureDetector(
            onTap: ctrl.cancelReply,
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  String _getPreview(MessageModel msg) {
    switch (msg.type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.audio:
        return '🎤 Message vocal';
      case MessageType.snap:
        return '📸 Snap';
      case MessageType.location:
        return '📍 Localisation';
      default:
        return msg.text ?? '';
    }
  }
}

// ─── RECORDING INDICATOR ─────────────────────────────────────────

class _RecordingIndicator extends StatefulWidget {
  final ConversationController ctrl;
  const _RecordingIndicator({required this.ctrl});

  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(Colors.red, Colors.transparent, _anim.value),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text('Enregistrement en cours...',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const Spacer(),
          Obx(() {
            final s = widget.ctrl.recordingSeconds.value;
            final min = (s ~/ 60).toString().padLeft(2, '0');
            final sec = (s % 60).toString().padLeft(2, '0');
            return Text('$min:$sec',
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600));
          }),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.ctrl.cancelRecording,
            child: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppColors.textMuted),
          ),
        ],
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
          _AttachItem(
              icon: Icons.camera_alt_rounded,
              label: 'Caméra',
              color: AppColors.accent,
              onTap: () => ctrl.envoyerPhoto(camera: true)),
          _AttachItem(
              icon: Icons.photo_library_rounded,
              label: 'Galerie',
              color: AppColors.accent2,
              onTap: () => ctrl.envoyerPhoto(camera: false)),
          _AttachItem(
              icon: Icons.auto_awesome_rounded,
              label: 'Snap',
              color: AppColors.accent3,
              onTap: ctrl.sendSnap),
          _AttachItem(
              icon: Icons.location_on_rounded,
              label: 'Lieu',
              color: const Color(0xFFFFD93D),
              onTap: ctrl.envoyerLocalisation),
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
  const _AttachItem(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── LOCATION BUBBLE ─────────────────────────────────────────────

class _LocationBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _LocationBubble({required this.msg, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        if (msg.text != null) {
          final uri = Uri.tryParse(msg.text!);
          if (uri != null && await canLaunchUrl(uri)) launchUrl(uri);
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded,
                      size: 20, color: Colors.white),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Ma localisation',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 90,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05)
                ]),
              ),
              child: const Center(
                  child:
                      Icon(Icons.map_rounded, size: 36, color: Colors.white54)),
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

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
            colors: colors[idx],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
      ),
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
