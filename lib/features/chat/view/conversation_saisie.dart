part of 'conversation_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  SAISIE : barre de saisie, menu ➕, aperçu avant envoi
//  (découpé de conversation_screen.dart — même bibliothèque,
//  les classes privées restent partagées)
// ═══════════════════════════════════════════════════════════════════

class _InputBar extends StatelessWidget {
  final ConversationController ctrl;
  const _InputBar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
      padding: EdgeInsets.fromLTRB(
          10, 8, 10, MediaQuery.of(context).viewInsets.bottom + 10),
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Obx(() => ctrl.replyToMessage.value != null
                ? _ReplyBar(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.enModification.value != null
                ? _BandeauModification(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.isRecording.value
                ? _RecordingIndicator(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.showAttachMenu.value
                ? _AttachMenu(ctrl: ctrl)
                : const SizedBox.shrink()),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Obx(() => GestureDetector(
                    onTap: ctrl.toggleAttachMenu,
                    child: Container(
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
                            border: Border.all(color: AppColors.border)),
                        child: Icon(
                            ctrl.showAttachMenu.value
                                ? Icons.close_rounded
                                : Icons.add_rounded,
                            size: 20,
                            color: Colors.white)),
                  )),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border)),
                child: TextField(
                  controller: ctrl.textController,
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textPrimary, height: 1.35),
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => ctrl.sendText(),
                  decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle:
                          TextStyle(color: AppColors.textMuted, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                ),
              )),
              const SizedBox(width: 8),
              Obx(() {
                final hasText = ctrl.inputText.value.trim().isNotEmpty;
                final isRec = ctrl.isRecording.value;
                return GestureDetector(
                  onTap: hasText ? ctrl.sendText : null,
                  onLongPressStart:
                      hasText ? null : (_) => ctrl.startRecording(),
                  onLongPressEnd: hasText ? null : (_) => ctrl.stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: isRec ? 46 : 38,
                    height: isRec ? 46 : 38,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.accent2]),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.accent
                                  .withOpacity(isRec ? 0.5 : 0.3),
                              blurRadius: isRec ? 14 : 7)
                        ]),
                    child: Icon(
                        hasText
                            ? Icons.send_rounded
                            : (isRec ? Icons.stop_rounded : Icons.mic_rounded),
                        size: 18,
                        color: Colors.white),
                  ),
                );
              }),
            ]),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  REPLY BAR
// ═══════════════════════════════════════════════════════════════════

class _BandeauModification extends StatelessWidget {
  final ConversationController ctrl;
  const _BandeauModification({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: AppColors.accent, width: 3)),
      ),
      child: Row(children: [
        Icon(Icons.edit_rounded, size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modifier le message',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(ctrl.enModification.value?.text ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
          onPressed: ctrl.annulerModification,
        ),
      ]),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  final ConversationController ctrl;
  const _ReplyBar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final msg = ctrl.replyToMessage.value!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: AppColors.accent, width: 3))),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.senderId == ctrl.myId ? 'Vous' : ctrl.conversation.userName,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(_preview(msg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ])),
        GestureDetector(
            onTap: ctrl.cancelReply,
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.textMuted)),
      ]),
    );
  }

  String _preview(MessageModel msg) {
    switch (msg.type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.audio:
        return '🎤 Vocal';
      case MessageType.snap:
        return '📸 Snap';
      case MessageType.location:
        return '📍 Position';
      default:
        return msg.text ?? '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RECORDING INDICATOR
// ═══════════════════════════════════════════════════════════════════

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
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                        AppColors.error, Colors.transparent, _anim.value)))),
        const SizedBox(width: 8),
        Obx(() {
          final n = (widget.ctrl.recordingDb.value / 80.0).clamp(0.0, 1.0);
          return Row(
              children: List.generate(
                  8,
                  (i) => Container(
                      width: 2.5,
                      height: 4 + (i % 2 == 0 ? n : n * 0.6) * 14,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2)))));
        }),
        const SizedBox(width: 8),
        Text('Enregistrement...',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const Spacer(),
        Obx(() {
          final s = widget.ctrl.recordingSeconds.value;
          return Text(
              '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600));
        }),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: widget.ctrl.cancelRecording,
            child: Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ATTACH MENU
// ═══════════════════════════════════════════════════════════════════

class _AttachMenu extends StatelessWidget {
  final ConversationController ctrl;
  const _AttachMenu({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _AttachItem(
            icon: Icons.camera_alt_rounded,
            label: 'Caméra',
            color: AppColors.accent,
            onTap: () => _selectionnerEtEnvoyer(context, camera: true)),
        _AttachItem(
            icon: Icons.photo_library_rounded,
            label: 'Galerie',
            color: AppColors.accent2,
            onTap: () => _selectionnerEtEnvoyer(context, camera: false)),
        _AttachItem(
            icon: Icons.videocam_rounded,
            label: 'Vidéo',
            color: const Color(0xFF00B4DB),
            onTap: () => _selectionnerVideo(context)),
        _AttachItem(
            icon: Icons.location_on_rounded,
            label: 'Position',
            color: const Color(0xFFFFD93D),
            onTap: ctrl.envoyerLocalisation),
        _AttachItem(
            icon: Icons.lock_rounded,
            label: 'Album',
            color: const Color(0xFFFF8FB1),
            onTap: () async {
              final ok = await ctrl.partagerAlbum();
              if (ok == false) {
                Get.snackbar('Ton album privé est vide',
                    'Ajoute des photos, puis partage-le',
                    snackPosition: SnackPosition.TOP,
                    backgroundColor: AppColors.surface,
                    colorText: Colors.white,
                    mainButton: TextButton(
                        onPressed: () => Get.to(() => const EcranMonAlbum()),
                        child: const Text('Ajouter',
                            style: TextStyle(color: Colors.white))));
              }
            }),
        _AttachItem(
            icon: Icons.emoji_emotions_rounded,
            label: 'Sticker',
            color: const Color(0xFF7CFFB2),
            onTap: () async {
              ctrl.showAttachMenu.value = false;
              final choix = await choisirSticker(context);
              if (choix != null) {
                ctrl.envoyerSticker(choix.url, gif: choix.estGif);
              }
            }),
      ]),
    );
  }

  void _selectionnerEtEnvoyer(BuildContext context,
      {required bool camera}) async {
    ctrl.showAttachMenu.value = false;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85);
    if (picked == null) return;
    final ctx = Get.context;
    if (ctx == null) return;
    showModalBottomSheet(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _PreviewSheet(ctrl: ctrl, filePath: picked.path));
  }

  void _selectionnerVideo(BuildContext context) async {
    ctrl.showAttachMenu.value = false;
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (picked == null) return;
    final ctx = Get.context;
    if (ctx == null) return;
    showModalBottomSheet(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) =>
            _PreviewSheet(ctrl: ctrl, filePath: picked.path, isVideo: true));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PREVIEW SHEET
// ═══════════════════════════════════════════════════════════════════

class _PreviewSheet extends StatefulWidget {
  final ConversationController ctrl;
  final String filePath;
  final bool isVideo;
  const _PreviewSheet(
      {required this.ctrl, required this.filePath, this.isVideo = false});
  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  bool _modeEphemere = false;
  bool _sensible = false; // 🔞 floutée chez le destinataire
  SnapDuration _duree = SnapDuration.s10;
  bool _showDureePicker = false;
  bool _uploading = false;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoCtrl = VideoPlayerController.file(File(widget.filePath));
      _videoCtrl!.initialize().then((_) {
        if (mounted) {
          setState(() => _videoReady = true);
          _videoCtrl!.setLooping(true);
          _videoCtrl!.play();
        }
      }).catchError((e) {
        debugPrint('Aperçu vidéo non chargé : $e');
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
    final size = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        height: size.height * 0.85,
        decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          Expanded(
              child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.isVideo
                ? (_videoReady && _videoCtrl != null
                    ? AspectRatio(
                        aspectRatio: _videoCtrl!.value.aspectRatio,
                        child: VideoPlayer(_videoCtrl!))
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)))
                : Image.file(File(widget.filePath), fit: BoxFit.contain),
          )),
          if (_modeEphemere && _showDureePicker)
            Container(
                color: AppColors.surface,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text('Durée d\'affichage après ouverture',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                          textAlign: TextAlign.center)),
                  ...SnapDuration.values.map((d) => InkWell(
                        onTap: () => setState(() {
                          _duree = d;
                          _showDureePicker = false;
                        }),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Row(children: [
                              Expanded(
                                  child: Text(d.label,
                                      style: TextStyle(
                                          fontSize: 15,
                                          color: _duree == d
                                              ? AppColors.textPrimary
                                              : AppColors.textMuted,
                                          fontWeight: _duree == d
                                              ? FontWeight.w600
                                              : FontWeight.w400))),
                              if (_duree == d)
                                Icon(Icons.check_rounded,
                                    color: AppColors.accent, size: 18),
                            ])),
                      )),
                ])),
          Container(
            color: AppColors.surface,
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Row(children: [
              if (!widget.isVideo)
                GestureDetector(
                  onTap: () => setState(() {
                    _modeEphemere = !_modeEphemere;
                    if (_modeEphemere) _showDureePicker = true;
                  }),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _modeEphemere
                          ? AppColors.accent.withOpacity(0.15)
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _modeEphemere
                              ? AppColors.accent.withOpacity(0.5)
                              : AppColors.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer_rounded,
                          size: 16,
                          color: _modeEphemere
                              ? AppColors.accent
                              : AppColors.textMuted),
                      const SizedBox(width: 5),
                      Text(_modeEphemere ? _duree.label : 'Éphémère',
                          style: TextStyle(
                              fontSize: 12,
                              color: _modeEphemere
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w500)),
                      if (_modeEphemere) ...[
                        const SizedBox(width: 4),
                        GestureDetector(
                            onTap: () => setState(
                                () => _showDureePicker = !_showDureePicker),
                            child: Icon(
                                _showDureePicker
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 16,
                                color: AppColors.accent)),
                      ],
                    ]),
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _sensible = !_sensible),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _sensible
                        ? AppColors.error.withOpacity(0.18)
                        : AppColors.surface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _sensible
                            ? AppColors.error.withOpacity(0.6)
                            : AppColors.border),
                  ),
                  child: Text(_sensible ? '🔞 Sensible' : '🔞',
                      style: TextStyle(
                          fontSize: 12,
                          color: _sensible
                              ? AppColors.textPrimary
                              : AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _uploading ? null : _envoyer,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.accent.withOpacity(0.4),
                            blurRadius: 12)
                      ]),
                  child: _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.send_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Envoyer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  /// La feuille se ferme tout de suite : l'envoi (compression vidéo,
  /// téléversement) continue en arrière-plan dans la discussion.
  void _envoyer() {
    if (!widget.ctrl.peutEnvoyer()) return;
    widget.ctrl.envoyerMediaEnFond(
      chemin: widget.filePath,
      video: widget.isVideo,
      ephemere: _modeEphemere && !widget.isVideo,
      snapSecondes: _modeEphemere ? _duree.seconds : null,
      sensible: _sensible,
    );
    Get.back();
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ATTACH ITEM
// ═══════════════════════════════════════════════════════════════════

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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3))),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.w500)),
        ]));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ANNONCE REPLY BUBBLE — style WhatsApp statut
// ═══════════════════════════════════════════════════════════════════
