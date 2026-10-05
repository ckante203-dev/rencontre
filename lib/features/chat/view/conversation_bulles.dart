part of 'conversation_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  BULLES : liste des messages, texte, réponses, réactions, stories, album, photos sensibles
//  (découpé de conversation_screen.dart — même bibliothèque,
//  les classes privées restent partagées)
// ═══════════════════════════════════════════════════════════════════

class _MessageList extends StatelessWidget {
  final ConversationController ctrl;
  const _MessageList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoading.value) return _buildShimmer();
      final msgs = ctrl.messages.where(ctrl.estVisible).toList();
      if (msgs.isEmpty) return _buildEmpty();
      // « Lu HH:MM » seulement sous mon dernier message lu (✓✓ ailleurs)
      final dernierLuId = msgs.reversed
          .toList()
          .firstWhereOrNull(
              (m) => m.senderId == ctrl.myId && m.status == MessageStatus.read)
          ?.id;
      final items = <_ChatItem>[];
      for (int i = 0; i < msgs.length; i++) {
        final msg = msgs[i];
        final prev = i > 0 ? msgs[i - 1] : null;
        final bool showDate =
            prev == null || !_isSameDay(prev.createdAt, msg.createdAt);
        if (showDate) items.add(_ChatItem.dateSep(msg.createdAt));
        final bool groupBreak = prev == null ||
            showDate ||
            prev.senderId != msg.senderId ||
            msg.createdAt.difference(prev.createdAt).inMinutes > 3;
        final next = i < msgs.length - 1 ? msgs[i + 1] : null;
        final bool isLast = next == null ||
            next.senderId != msg.senderId ||
            next.createdAt.difference(msg.createdAt).inMinutes > 3;
        items.add(_ChatItem.message(msg, isFirst: groupBreak, isLast: isLast));
      }
      return ListView.builder(
        controller: ctrl.scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[items.length - 1 - i];
          if (item.isDateSep) return _DateLabel(date: item.date!);
          return _MessageBubble(
              msg: item.msg!,
              ctrl: ctrl,
              isFirst: item.isFirst,
              isLast: item.isLast,
              dernierLu: item.msg!.id == dernierLuId);
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
              width: 140 + (i * 20.0).clamp(0.0, 100.0),
              height: 38,
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16))),
        ),
      ),
    );
  }

  // Phrases pour briser la glace (comme Grindr / Bumble) : un tap les met
  // dans le champ, on peut les modifier avant d'envoyer.
  static const _brisGlace = [
    'Salut ! Comment tu vas ? 😊',
    'Coucou, on fait connaissance ? 👋',
    "Ton profil m'a fait sourire 😄",
    'Tu fais quoi de beau ce week-end ?',
    "J'adore ta photo 🔥",
  ];

  Widget _buildEmpty() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline_rounded,
              size: 44, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Dis bonjour à ${ctrl.conversation.userName} !',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Choisis une phrase pour commencer',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final phrase in _brisGlace)
                GestureDetector(
                  onTap: () {
                    ctrl.textController.text = phrase;
                    ctrl.inputText.value = phrase;
                    ctrl.textController.selection =
                        TextSelection.collapsed(offset: phrase.length);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(phrase,
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textPrimary)),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}

class _ChatItem {
  final MessageModel? msg;
  final DateTime? date;
  final bool isDateSep;
  final bool isFirst;
  final bool isLast;
  const _ChatItem._(
      {this.msg,
      this.date,
      this.isDateSep = false,
      this.isFirst = true,
      this.isLast = true});
  factory _ChatItem.message(MessageModel m,
          {bool isFirst = true, bool isLast = true}) =>
      _ChatItem._(msg: m, isFirst: isFirst, isLast: isLast);
  factory _ChatItem.dateSep(DateTime d) =>
      _ChatItem._(date: d, isDateSep: true);
}

// ═══════════════════════════════════════════════════════════════════
//  DATE LABEL
// ═══════════════════════════════════════════════════════════════════

class _DateLabel extends StatelessWidget {
  final DateTime date;
  const _DateLabel({required this.date});
  String _label() {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
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
    return '${date.day} ${mois[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
          child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: Text(_label(),
            style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500)),
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final ConversationController ctrl;
  final bool isFirst;
  final bool isLast;
  final bool dernierLu;
  const _MessageBubble(
      {required this.msg,
      required this.ctrl,
      this.isFirst = true,
      this.isLast = true,
      this.dernierLu = false});

  @override
  Widget build(BuildContext context) {
    final isMine = msg.senderId == ctrl.myId;
    final h = msg.createdAt.hour.toString().padLeft(2, '0');
    final m = msg.createdAt.minute.toString().padLeft(2, '0');
    // Texte simple : heure + coches DANS la bulle (façon WhatsApp)
    final texteSimple = msg.type == MessageType.text &&
        msg.text != ConversationController.texteAlbum &&
        !_TextBubble.emojisSeuls(msg.text);
    return _GlisserPourRepondre(
      onRepondre: () => ctrl.setReplyTo(msg),
      child: GestureDetector(
        onLongPress: () => ctrl.showMessageOptions(context, msg),
        child: Padding(
          padding: EdgeInsets.only(
              top: isFirst ? 4 : 1,
              bottom: isLast ? 4 : 1,
              left: isMine ? 56 : 4,
              right: isMine ? 4 : 56),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment:
                    isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!isMine) ...[
                    SizedBox(
                        width: 30,
                        child: isLast
                            ? _Avatar(
                                name: ctrl.conversation.userName,
                                size: 28,
                                photoUrl: ctrl.conversation.userPhotoUrl)
                            : const SizedBox()),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                      child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (msg.storyReply != null)
                        _StoryReplyPreview(
                            storyReply: msg.storyReply!, isMine: isMine),
                      if (msg.replyTo != null && msg.storyReply == null)
                        _ReplyPreview(
                            replyTo: msg.replyTo!, isMine: isMine, ctrl: ctrl),
                      _buildContent(isMine, context),
                      if (texteSimple) ...[
                        // « Lu 14:32 » sous mon dernier message lu seulement
                        if (isMine && dernierLu && msg.readAt != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: _StatusIcon(
                                status: msg.status, readAt: msg.readAt),
                          ),
                      ] else ...[
                        const SizedBox(height: 2),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          if (msg.modifieLe != null)
                            Text('modifié · ',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.textMuted)),
                          Text('$h:$m',
                              style: TextStyle(
                                  fontSize: 10, color: AppColors.textMuted)),
                          if (isMine) ...[
                            const SizedBox(width: 3),
                            // ✅ Heure de lecture de CE message (read_at, posé par
                            // le serveur). Avant : la même heure — souvent celle
                            // d'envoi du dernier message lu — sur tous les messages.
                            _StatusIcon(
                                status: msg.status,
                                readAt: dernierLu ? msg.readAt : null),
                          ],
                        ]),
                      ],
                    ],
                  )),
                ],
              ),
              if (msg.hasReactions) _ReactionsRow(msg: msg, ctrl: ctrl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isMine, BuildContext context) {
    switch (msg.type) {
      case MessageType.snap:
        return _SnapBubble(
            msg: msg,
            isMine: isMine,
            ctrl: ctrl,
            onTap: () => ctrl.openSnap(msg));
      case MessageType.audio:
        return _AudioBubble(msg: msg, isMine: isMine, ctrl: ctrl);
      case MessageType.image:
        if (msg.text == ConversationController.texteSticker &&
            (msg.mediaUrl ?? '').isNotEmpty) {
          return CachedNetworkImage(
            imageUrl: msg.mediaUrl!,
            width: 140,
            height: 140,
            fit: BoxFit.contain,
            placeholder: (_, __) => const SizedBox(width: 140, height: 140),
            errorWidget: (_, __, ___) =>
                _MediaBubble(msg: msg, isMine: isMine, isVideo: false),
          );
        }
        final sensible = !isMine &&
            (msg.text ?? '')
                .startsWith(ConversationController.prefixeSensible) &&
            ConversationController.flouterSensibles;
        if (sensible) {
          return _FlouSensible(
              child: _MediaBubble(msg: msg, isMine: isMine, isVideo: false));
        }
        return _MediaBubble(msg: msg, isMine: isMine, isVideo: false);
      case MessageType.location:
        return _LocationBubble(msg: msg, isMine: isMine);
      case MessageType.annonceReply:
        return _AnnonceReplyBubble(msg: msg, isMine: isMine);
      default:
        if (msg.text == ConversationController.texteAlbum) {
          return _CarteAlbumPartage(msg: msg, isMine: isMine, ctrl: ctrl);
        }
        return _TextBubble(
            msg: msg, isMine: isMine, isFirst: isFirst, isLast: isLast);
      // (heure + coches ajoutées dans _TextBubble)
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RÉACTIONS
// ═══════════════════════════════════════════════════════════════════

class _ReactionsRow extends StatelessWidget {
  final MessageModel msg;
  final ConversationController ctrl;
  const _ReactionsRow({required this.msg, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final entries =
        msg.reactions.entries.where((e) => e.value.isNotEmpty).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 34),
      child: Wrap(
          spacing: 3,
          children: entries.map((entry) {
            final emoji = entry.key;
            final count = entry.value.length;
            final me = entry.value.contains(ctrl.myId);
            return GestureDetector(
              onTap: () => ctrl.toggleReaction(msg, emoji),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: me
                      ? AppColors.accent.withOpacity(0.1)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: me
                          ? AppColors.accent.withOpacity(0.5)
                          : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  if (count > 1) ...[
                    const SizedBox(width: 3),
                    Text('$count',
                        style: TextStyle(
                            fontSize: 10,
                            color: me
                                ? AppColors.textPrimary
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w600))
                  ],
                ]),
              ),
            );
          }).toList()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STORY / REPLY PREVIEW
// ═══════════════════════════════════════════════════════════════════

// ✅ MIS À JOUR — cadre agrandi + tap pour voir la story façon Snapchat
// (plein écran, nom de l'auteur, bouton retour) au lieu de rester
// statique dans la bulle de chat.
class _StoryReplyPreview extends StatelessWidget {
  final StoryReplyData storyReply;
  final bool isMine;
  const _StoryReplyPreview({required this.storyReply, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _StoryReplyFullScreen(storyReply: storyReply),
          ),
        );
      },
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withOpacity(0.1) : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border(
              left: BorderSide(
                  color: isMine ? Colors.white38 : AppColors.accent, width: 3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9), bottomLeft: Radius.circular(9)),
            child: SizedBox(
              // ✅ Cadre agrandi (56x72 au lieu de 40x50)
              width: 56,
              height: 72,
              child: Stack(fit: StackFit.expand, children: [
                // ✅ Story texte : pas d'image à montrer.
                if (storyReply.isTextStory)
                  Container(
                    decoration: BoxDecoration(
                      color: storyReply.storyBgColor != null
                          ? _storyBgColor(storyReply.storyBgColor)
                          : null,
                      gradient: storyReply.storyBgColor == null
                          ? AppColors.gradientPink
                          : null,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Center(
                        child: Text(storyReply.storyText ?? 'Aa',
                            textAlign: TextAlign.center,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: storyReply.storyText == null ? 18 : 8,
                                fontWeight: FontWeight.w800))),
                  )
                else
                  CachedNetworkImage(
                      imageUrl: storyReply.storyPreviewUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.photo_camera_rounded,
                              color: Colors.white38, size: 18))),
                if (storyReply.storyIsVideo)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 22)),
                  ),
              ]),
            ),
          ),
          Flexible(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      storyReply.storyIsVideo
                          ? '🎬 Vidéo'
                          : storyReply.isTextStory
                              ? '✍️ Texte'
                              : '📸 Photo',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              isMine ? Colors.white70 : AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(
                      storyReply.storyOwnerName.isNotEmpty
                          ? 'Story de ${storyReply.storyOwnerName}'
                          : 'Story',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.visibility_rounded,
                        size: 11, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text('Voir',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                  ]),
                ]),
          )),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ NOUVEAU — VISIONNAGE DE LA STORY DEPUIS LE CHAT, FAÇON SNAPCHAT
//  Plein écran, nom de l'auteur en en-tête, bouton retour. On ne
//  rejoue pas la story originale (elle peut avoir expiré) : on
//  affiche l'aperçu conservé au moment de la réponse.
// ═══════════════════════════════════════════════════════════════════

class _StoryReplyFullScreen extends StatefulWidget {
  final StoryReplyData storyReply;
  const _StoryReplyFullScreen({required this.storyReply});

  @override
  State<_StoryReplyFullScreen> createState() => _StoryReplyFullScreenState();
}

class _StoryReplyFullScreenState extends State<_StoryReplyFullScreen> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.storyReply.storyIsVideo) {
      final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(widget.storyReply.storyPreviewUrl));
      _videoCtrl = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted) return;
        setState(() => _videoReady = true);
        ctrl.setLooping(true);
        ctrl.play();
      }).catchError((e) {
        // ✅ Story expirée / réseau : plus d'erreur non gérée
        debugPrint('Vidéo de la story non chargée : $e');
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.storyReply;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        Center(
          child: story.storyIsVideo
              ? (_videoReady && _videoCtrl != null
                  ? AspectRatio(
                      aspectRatio: _videoCtrl!.value.aspectRatio,
                      child: VideoPlayer(_videoCtrl!))
                  : const CircularProgressIndicator(color: Colors.white))
              : story.isTextStory
                  ? Container(
                      color: story.storyBgColor != null
                          ? _storyBgColor(story.storyBgColor)
                          : Colors.black,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(story.storyText ?? '✍️ Story texte',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: story.storyText != null
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: story.storyText != null ? 28 : 20,
                              fontWeight: FontWeight.w800,
                              height: 1.3)),
                    )
                  : CachedNetworkImage(
                      imageUrl: story.storyPreviewUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white)),
                      errorWidget: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_rounded,
                              color: Colors.white38, size: 48)),
                    ),
        ),
        // ── Dégradé + en-tête façon Snapchat ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
                12, MediaQuery.of(context).padding.top + 8, 12, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  story.storyOwnerName.isNotEmpty
                      ? 'Story de ${story.storyOwnerName}'
                      : 'Story',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

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
        return '🎤 Vocal';
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
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withOpacity(0.1) : AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(
                color: isMine ? Colors.white38 : AppColors.accent, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isReplyMine ? 'Vous' : ctrl.conversation.userName,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isMine ? Colors.white70 : AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(_preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TEXTE BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _TextBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine, isFirst, isLast;
  const _TextBubble(
      {required this.msg,
      required this.isMine,
      this.isFirst = true,
      this.isLast = true});

  // Compilées une seule fois (et non à chaque bulle affichée). L'analyseur
  // ne connaît pas \p{Extended_Pictographic}, pourtant valide à l'exécution.
  static final _reEmojis = RegExp(
      // ignore: valid_regexps
      r'^(?:\p{Extended_Pictographic}|\p{Emoji_Component}|\u200d|\ufe0f|\s)+$',
      unicode: true);
  static final _reChiffres = RegExp(r'[0-9#*]');

  /// 1 à 3 emojis sans texte → affichés en grand, sans bulle.
  static bool emojisSeuls(String? texte) {
    final t = (texte ?? '').trim();
    if (t.isEmpty || t.characters.length > 3) return false;
    return _reEmojis.hasMatch(t) && !_reChiffres.hasMatch(t);
  }

  @override
  Widget build(BuildContext context) {
    final h = msg.createdAt.hour.toString().padLeft(2, '0');
    final mn = msg.createdAt.minute.toString().padLeft(2, '0');
    final modifie = msg.modifieLe != null;
    final couleurMeta = isMine ? Colors.white70 : AppColors.textMuted;

    // Heure (+ « modifié ») et coches, en bas à droite de la bulle
    final meta = Row(mainAxisSize: MainAxisSize.min, children: [
      if (modifie)
        Text('modifié ',
            style: TextStyle(
                fontSize: 10.5,
                fontStyle: FontStyle.italic,
                color: couleurMeta)),
      Text('$h:$mn', style: TextStyle(fontSize: 10.5, color: couleurMeta)),
      if (isMine) ...[
        const SizedBox(width: 3),
        _CochesBulle(status: msg.status),
      ],
    ]);

    // 😂 Gros emojis, sans bulle
    // 😂 Gros emojis, sans bulle (heure affichée dessous par la bulle)
    if (emojisSeuls(msg.text)) {
      return Text(msg.text!.trim(),
          style: const TextStyle(fontSize: 42, height: 1.15));
    }

    const r = Radius.circular(18);
    const rs = Radius.circular(5);
    // Coins resserrés côté expéditeur à l'intérieur d'un groupe de messages
    final borderRadius = isMine
        ? BorderRadius.only(
            topLeft: r,
            topRight: isFirst ? r : rs,
            bottomLeft: r,
            bottomRight: isLast ? r : rs)
        : BorderRadius.only(
            topLeft: isFirst ? r : rs,
            topRight: r,
            bottomLeft: isLast ? r : rs,
            bottomRight: r);
    // Largeur réservée à la fin du texte pour que l'heure ne le chevauche pas
    final largeurMeta = 36.0 + (modifie ? 44 : 0) + (isMine ? 18 : 0);
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      padding: const EdgeInsets.fromLTRB(12, 7, 9, 6),
      decoration: BoxDecoration(
          gradient: isMine ? AppColors.gradientPink : null,
          color: isMine ? null : AppColors.surface2,
          borderRadius: borderRadius),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: msg.text ?? ''),
              WidgetSpan(child: SizedBox(width: largeurMeta, height: 12)),
            ]),
            style: TextStyle(
                fontSize: 15,
                color: isMine ? Colors.white : AppColors.textPrimary,
                height: 1.35),
          ),
        ),
        Positioned(right: 0, bottom: 0, child: meta),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SNAP BUBBLE
// ═══════════════════════════════════════════════════════════════════

/// 🔞 Photo sensible : floutée jusqu'à ce que la personne choisisse de la voir.
class _FlouSensible extends StatefulWidget {
  final Widget child;
  const _FlouSensible({required this.child});

  @override
  State<_FlouSensible> createState() => _FlouSensibleState();
}

class _FlouSensibleState extends State<_FlouSensible> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    if (_visible) return widget.child;
    return GestureDetector(
      onTap: () => setState(() => _visible = true),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(alignment: Alignment.center, children: [
          IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: widget.child,
            ),
          ),
          const Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🔞', style: TextStyle(fontSize: 30)),
            SizedBox(height: 6),
            Text('Photo sensible',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
            SizedBox(height: 2),
            Text('Touche pour voir',
                style: TextStyle(fontSize: 12, color: Colors.white)),
          ]),
        ]),
      ),
    );
  }
}

/// Message « album privé partagé » : une carte qui ouvre l'album.
class _CarteAlbumPartage extends StatefulWidget {
  final MessageModel msg;
  final bool isMine;
  final ConversationController ctrl;
  const _CarteAlbumPartage(
      {required this.msg, required this.isMine, required this.ctrl});

  @override
  State<_CarteAlbumPartage> createState() => _CarteAlbumPartageState();
}

class _CarteAlbumPartageState extends State<_CarteAlbumPartage> {
  bool _ouverture = false;

  Future<void> _ouvrir() async {
    if (widget.isMine) {
      Get.to(() => const EcranMonAlbum());
      return;
    }
    setState(() => _ouverture = true);
    try {
      final photos = await AlbumService.photosDe(widget.msg.senderId);
      if (photos.isEmpty) {
        Get.snackbar('Album privé', "L'accès à cet album a été retiré",
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
      } else {
        Get.to(() => EcranAlbumDe(
            nom: widget.ctrl.conversation.userName, photos: photos));
      }
    } catch (_) {
      Get.snackbar('Album privé', "Impossible d'ouvrir l'album",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _ouverture = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nom = widget.ctrl.conversation.userName;
    return GestureDetector(
      onTap: _ouvrir,
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: AppColors.gradientPink,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: _ouverture
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.lock_open_rounded,
                    color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Album privé',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text(
                    widget.isMine
                        ? 'Tu as partagé ton album avec $nom'
                        : 'Touche pour voir les photos',
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _AnnonceReplyBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _AnnonceReplyBubble({required this.msg, required this.isMine});

  String get _catEmoji {
    final cat = msg.annonceReply?.annonceCategorie ?? '';
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return m[cat] ?? '📢';
  }

  @override
  Widget build(BuildContext context) {
    final reply = msg.annonceReply;
    final hasText = msg.text != null &&
        msg.text!.isNotEmpty &&
        msg.text != '📢 A répondu à une annonce';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ── Preview annonce (comme WhatsApp statut) ──
          Container(
            decoration: BoxDecoration(
              color:
                  isMine ? Colors.white.withOpacity(0.12) : AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(
                  color: isMine ? Colors.white38 : AppColors.accent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Auteur annonce
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_catEmoji ',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              reply?.annonceAuteur ?? 'Annonce',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isMine
                                    ? Colors.white70
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Titre
                        Text(
                          reply?.annonceTitre ?? 'Annonce',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isMine ? Colors.white : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Description
                        if (reply?.annonceDescription.isNotEmpty == true)
                          Text(
                            reply!.annonceDescription,
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isMine ? Colors.white54 : AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                // Miniature photo
                if (reply?.annonceMediaUrl != null &&
                    reply?.annonceIsVideo == false)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: reply!.annonceMediaUrl!,
                      width: 56,
                      height: 64,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  )
                else if (reply?.annonceIsVideo == true)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    child: Container(
                      width: 56,
                      height: 64,
                      color: Colors.white.withOpacity(0.08),
                      child: Center(
                        child: Icon(Icons.videocam_rounded,
                            color: AppColors.accent, size: 20),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Message texte en dessous (si présent) ──
          if (hasText)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: isMine ? AppColors.gradientPink : null,
                color: isMine ? null : AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                msg.text!,
                style: TextStyle(
                  fontSize: 14,
                  color: isMine ? Colors.white : AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AVATAR
// ═══════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? photoUrl;
  const _Avatar({required this.name, required this.size, this.photoUrl});
  @override
  Widget build(BuildContext context) {
    final palettes = [
      [const Color(0xFFFF6B6B), const Color(0xFFFECA57)],
      [const Color(0xFF48DBFB), const Color(0xFFFF9FF3)],
      [const Color(0xFFFF9F43), const Color(0xFFEE5A24)],
      [const Color(0xFFA29BFE), const Color(0xFF6C5CE7)],
      [const Color(0xFFFD79A8), const Color(0xFFE84393)],
      [const Color(0xFF55EFC4), const Color(0xFF00B894)],
    ];
    final idx = name.hashCode.abs() % palettes.length;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                colors: palettes[idx],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Center(
            child: Text(letter,
                style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                    color: Colors.white))));
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
          child: CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback));
    }
    return fallback;
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ AVATAR AVEC ANNEAU DE STORY (en-tête de conversation)
// ═══════════════════════════════════════════════════════════════════

class _AvatarWithStoryRing extends StatelessWidget {
  final String userId;
  final String name;
  final String? photoUrl;
  final double size;

  const _AvatarWithStoryRing({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeController>()) {
      return _Avatar(name: name, size: size, photoUrl: photoUrl);
    }
    final homeCtrl = Get.find<HomeController>();

    return Obx(() {
      final hasStory = homeCtrl.userHasActiveStory(userId);
      final storySeen = homeCtrl.userStoryIsSeen(userId);

      final avatar = _Avatar(name: name, size: size, photoUrl: photoUrl);

      if (!hasStory) return avatar;

      return GestureDetector(
        onTap: () => _openStory(homeCtrl),
        child: Container(
          padding: const EdgeInsets.all(2.5),
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
              color: AppColors.surface,
            ),
            child: avatar,
          ),
        ),
      );
    });
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

// Couleur de fond d'une story texte, stockée en hex ("#7B2FFF").
Color _storyBgColor(String? hex) {
  var h = (hex ?? '').replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF7B2FFF);
}

/// Coches dans une bulle (couleurs lisibles sur le dégradé rose)
class _CochesBulle extends StatelessWidget {
  final MessageStatus status;
  const _CochesBulle({required this.status});
  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.schedule_rounded,
            size: 12, color: Colors.white70);
      case MessageStatus.sent:
        return const Icon(Icons.check_rounded, size: 14, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all_rounded,
            size: 14, color: Colors.white70);
      case MessageStatus.read:
        // Lu : coches bleu clair, bien visibles sur le rose
        return const Icon(Icons.done_all_rounded,
            size: 14, color: Color(0xFF8BE9FF));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  GLISSER POUR RÉPONDRE (vers la droite, façon WhatsApp)
// ═══════════════════════════════════════════════════════════════════

class _GlisserPourRepondre extends StatefulWidget {
  final Widget child;
  final VoidCallback onRepondre;
  const _GlisserPourRepondre({required this.child, required this.onRepondre});
  @override
  State<_GlisserPourRepondre> createState() => _GlisserPourRepondreState();
}

class _GlisserPourRepondreState extends State<_GlisserPourRepondre>
    with SingleTickerProviderStateMixin {
  static const _seuil = 60.0;
  static const _max = 80.0;
  double _dx = 0;
  bool _vibre = false;
  late final AnimationController _retour;
  double _depart = 0;

  @override
  void initState() {
    super.initState();
    _retour = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180))
      ..addListener(() {
        setState(() => _dx = _depart * (1 - _retour.value));
      });
  }

  @override
  void dispose() {
    _retour.dispose();
    super.dispose();
  }

  void _fin() {
    if (_dx >= _seuil) widget.onRepondre();
    _depart = _dx;
    _vibre = false;
    _retour.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final p = (_dx / _seuil).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) {
        if (_retour.isAnimating) _retour.stop();
        final v = (_dx + d.delta.dx).clamp(0.0, _max);
        if (v >= _seuil && !_vibre) {
          _vibre = true;
          HapticFeedback.lightImpact();
        }
        setState(() => _dx = v);
      },
      onHorizontalDragEnd: (_) => _fin(),
      onHorizontalDragCancel: _fin,
      child: Stack(alignment: Alignment.centerLeft, children: [
        if (_dx > 0)
          Positioned(
            left: 10,
            child: Opacity(
              opacity: p,
              child: Transform.scale(
                scale: 0.6 + 0.4 * p,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surface2,
                  ),
                  child: Icon(Icons.reply_rounded,
                      size: 18, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
        Transform.translate(offset: Offset(_dx, 0), child: widget.child),
      ]),
    );
  }
}
