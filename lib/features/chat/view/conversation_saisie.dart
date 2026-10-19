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
            Obx(() => ctrl.showAttachMenu.value
                ? _AttachMenu(ctrl: ctrl)
                : const SizedBox.shrink()),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Obx(() => ctrl.isRecording.value || ctrl.vocalApercu.value != null
                  ? const SizedBox.shrink()
                  : GestureDetector(
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
                            color: ctrl.showAttachMenu.value
                                ? AppColors.surAccent
                                : AppColors.textPrimary)),
                  )),
              const SizedBox(width: 8),
              // 🎤 Comme WhatsApp : pendant un vocal, la ligne d'enregistrement
              // (ou la réécoute) remplace le champ de texte
              Expanded(
                  child: Obx(() => ctrl.isRecording.value
                      ? _RecordingIndicator(ctrl: ctrl)
                      : ctrl.vocalApercu.value != null
                          ? _ApercuVocal(ctrl: ctrl)
                          : Container(
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
                      hintText: 'Message...'.tr,
                      hintStyle:
                          TextStyle(color: AppColors.textMuted, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                ),
              ))),
              const SizedBox(width: 8),
              Obx(() {
                final hasText = ctrl.inputText.value.trim().isNotEmpty;
                final isRec = ctrl.isRecording.value;
                // Verrouillé ou en réécoute : les boutons sont dans la ligne
                if (ctrl.vocalVerrouille.value || ctrl.vocalApercu.value != null) {
                  return const SizedBox.shrink();
                }
                // Toujours la même structure (cadenas puis micro) : le
                // micro ne doit pas être recréé pendant l'appui
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  isRec ? const _IndiceVerrou() : const SizedBox.shrink(),
                  GestureDetector(
                  onTap: hasText ? ctrl.sendText : null,
                  // Texte écrit : appui long = programmer l'envoi
                  onLongPress:
                      hasText ? () => ctrl.programmerMessage(context) : null,
                  onLongPressStart:
                      hasText ? null : (_) => ctrl.startRecording(),
                  onLongPressMoveUpdate: hasText
                      ? null
                      : (d) => ctrl.glisserVocal(d.offsetFromOrigin),
                  onLongPressEnd: hasText ? null : (_) => ctrl.lacherVocal(),
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
                        color: AppColors.surAccent),
                  ),
                ),
                ]);
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
              Text('Modifier le message'.tr,
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
          Text(
              msg.senderId == ctrl.myId
                  ? 'Vous'.tr
                  : ctrl.conversation.userName,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(_apercuCitation(msg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ])),
        if (_miniatureCitation(msg, ctrl.myId) != null) ...[
          _MiniatureCitation(_miniatureCitation(msg, ctrl.myId)!),
          const SizedBox(width: 10),
        ],
        GestureDetector(
            onTap: ctrl.cancelReply,
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.textMuted)),
      ]),
    );
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
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(22)),
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
        // Pas verrouillé : consigne qui s'efface quand on glisse ;
        // verrouillé : 🔒 mains libres
        Expanded(
          child: Obx(() => widget.ctrl.vocalVerrouille.value
              ? Text('🔒 ' + 'Enregistrement...'.tr,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted))
              : Opacity(
                  opacity: (1 + widget.ctrl.vocalGlisse.value / 110)
                      .clamp(0.2, 1.0),
                  child: Text('◀ Glisse pour annuler · ▲ pour verrouiller'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                )),
        ),
        Obx(() {
          final s = widget.ctrl.recordingSeconds.value;
          return Text(
              '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600));
        }),
        // Verrouillé : 🗑 supprimer · ⏹ arrêter pour réécouter · ➤ envoyer
        Obx(() => widget.ctrl.vocalVerrouille.value
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 6),
                _BoutonVocal(
                    icone: Icons.delete_outline_rounded,
                    onTap: widget.ctrl.cancelRecording),
                _BoutonVocal(
                    icone: Icons.stop_circle_outlined,
                    onTap: widget.ctrl.arreterPourApercu),
                _BoutonVocal(
                    icone: Icons.send_rounded,
                    accent: true,
                    onTap: widget.ctrl.stopRecording),
              ])
            : const SizedBox.shrink()),
      ]),
    );
  }
}

class _IndiceVerrou extends StatelessWidget {
  const _IndiceVerrou();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textPrimary),
        Icon(Icons.keyboard_arrow_up_rounded,
            size: 18, color: AppColors.textMuted),
      ]),
    );
  }
}

class _BoutonVocal extends StatelessWidget {
  final IconData icone;
  final VoidCallback onTap;
  final bool accent;
  const _BoutonVocal(
      {required this.icone, required this.onTap, this.accent = false});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: accent ? AppColors.gradientPink : null,
          color: accent ? null : AppColors.surface,
        ),
        child: Icon(icone,
            size: 18,
            color: accent ? AppColors.surAccent : AppColors.textPrimary),
      ),
    );
  }
}

/// Vocal enregistré (mode verrouillé, ⏹) : réécouter, supprimer ou envoyer
class _ApercuVocal extends StatelessWidget {
  final ConversationController ctrl;
  const _ApercuVocal({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final s = ctrl.recordingSeconds.value;
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        _BoutonVocal(
            icone: Icons.delete_outline_rounded, onTap: ctrl.supprimerApercu),
        Obx(() => _BoutonVocal(
            icone: ctrl.apercuEnLecture.value
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            onTap: ctrl.ecouterApercu)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
              '🎤 ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ),
        _BoutonVocal(
            icone: Icons.send_rounded, accent: true, onTap: ctrl.envoyerApercu),
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
            label: 'Caméra'.tr,
            color: AppColors.accent,
            onTap: () => _selectionnerEtEnvoyer(context, camera: true)),
        _AttachItem(
            icon: Icons.photo_library_rounded,
            label: 'Galerie'.tr,
            color: AppColors.accent2,
            onTap: () => _selectionnerEtEnvoyer(context, camera: false)),
        _AttachItem(
            icon: Icons.videocam_rounded,
            label: 'Vidéo'.tr,
            color: const Color(0xFF00B4DB),
            onTap: () => _selectionnerVideo(context)),
        _AttachItem(
            icon: Icons.location_on_rounded,
            label: 'Position'.tr,
            color: const Color(0xFFFFD93D),
            onTap: () => _choisirPosition(context)),
        _AttachItem(
            icon: Icons.lock_rounded,
            label: 'Album'.tr,
            color: const Color(0xFFFF8FB1),
            onTap: () async {
              final ok = await ctrl.partagerAlbum();
              if (ok == false) {
                Get.snackbar('Ton album privé est vide'.tr,
                    'Ajoute des photos, puis partage-le'.tr,
                    snackPosition: SnackPosition.TOP,
                    backgroundColor: AppColors.surface,
                    colorText: AppColors.textPrimary,
                    mainButton: TextButton(
                        onPressed: () => Get.to(() => const EcranMonAlbum()),
                        child: Text('Ajouter'.tr,
                            style: TextStyle(color: AppColors.textPrimary))));
              }
            }),
        _AttachItem(
            icon: Icons.emoji_emotions_rounded,
            label: 'Sticker'.tr,
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
    // Galerie : plusieurs photos d'un coup (10 au maximum)
    if (!camera) {
      final photos = await picker.pickMultiImage(
          maxWidth: 1080, maxHeight: 1920, imageQuality: 85, limit: 10);
      if (photos.isEmpty) return;
      final ctx = Get.context;
      if (ctx == null) return;
      if (photos.length > 1) {
        _envoyerPlusieurs(ctx, photos.take(10).map((p) => p.path).toList());
        return;
      }
      showModalBottomSheet(
          context: ctx,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) =>
              _PreviewSheet(ctrl: ctrl, filePath: photos.first.path));
      return;
    }
    final picked = await picker.pickImage(
        source: ImageSource.camera,
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

  /// Aperçu de plusieurs photos (retirer, agrandir, en ajouter) puis envoi
  /// l'une après l'autre
  void _envoyerPlusieurs(BuildContext ctx, List<String> chemins) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ApercuPlusieurs(ctrl: ctrl, chemins: chemins),
    );
  }

  /// Position : actuelle, ou en direct pendant 1 h (rendez-vous)
  void _choisirPosition(BuildContext context) {
    ctrl.showAttachMenu.value = false;
    Get.bottomSheet(
      SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.place_rounded, color: AppColors.accent),
              title: Text('Position actuelle'.tr,
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Get.back();
                ctrl.envoyerLocalisation();
              },
            ),
            ListTile(
              leading: const Icon(Icons.radio_button_checked_rounded,
                  color: Colors.red),
              title: Text('En direct pendant 1 h'.tr,
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: Text(
                  'Pour un rendez-vous : ta position se met à jour chaque minute, app ouverte.'.tr,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onTap: () async {
                Get.back();
                if (!ctrl.peutEnvoyer()) return;
                final ok =
                    await PositionDirect.demarrer(ctrl.conversation.id);
                if (!ok) {
                  Get.snackbar('📍', 'Impossible de récupérer la position'.tr,
                      snackPosition: SnackPosition.TOP,
                      backgroundColor: AppColors.surface,
                      colorText: AppColors.textPrimary);
                }
              },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
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
//  APERÇU DE PLUSIEURS PHOTOS (galerie)
// ═══════════════════════════════════════════════════════════════════

class _ApercuPlusieurs extends StatefulWidget {
  final ConversationController ctrl;
  final List<String> chemins;
  const _ApercuPlusieurs({required this.ctrl, required this.chemins});
  @override
  State<_ApercuPlusieurs> createState() => _ApercuPlusieursState();
}

class _ApercuPlusieursState extends State<_ApercuPlusieurs> {
  static const _max = 10;
  late final List<String> _chemins = [...widget.chemins];

  void _retirer(String c) {
    HapticFeedback.selectionClick();
    setState(() => _chemins.remove(c));
    if (_chemins.isEmpty) Get.back();
  }

  Future<void> _ajouter() async {
    final reste = _max - _chemins.length;
    if (reste <= 0) return;
    final photos = await ImagePicker().pickMultiImage(
        maxWidth: 1080, maxHeight: 1920, imageQuality: 85, limit: reste);
    if (!mounted || photos.isEmpty) return;
    setState(() => _chemins.addAll(photos.take(reste).map((p) => p.path)));
  }

  /// Photo en grand ; glisser pour passer à la suivante, 🗑 pour la retirer
  Future<void> _agrandir(int depart) async {
    final page = PageController(initialPage: depart);
    var index = depart;
    // Double-toucher pour zoomer (le doigt déplace alors la photo) ; sinon
    // le doigt change de photo. Un zoom au pincement captait le glissement.
    final zoom = TransformationController();
    var zoomee = false;
    Offset toucher = Offset.zero;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setPlein) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: AppColors.surMedia,
            title: Text('${index + 1} / ${_chemins.length}'),
            actions: [
              TextButton.icon(
                onPressed: () {
                  final c = _chemins[index];
                  _retirer(c);
                  if (_chemins.isEmpty) {
                    Navigator.of(ctx).pop();
                    return;
                  }
                  setPlein(() =>
                      index = index.clamp(0, _chemins.length - 1).toInt());
                },
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Color(0xFFFF453A)),
                label: Text('Retirer'.tr,
                    style: const TextStyle(color: Color(0xFFFF453A))),
              ),
            ],
          ),
          body: PageView.builder(
            controller: page,
            physics: zoomee
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: _chemins.length,
            onPageChanged: (i) => setPlein(() {
              index = i;
              zoomee = false;
              zoom.value = Matrix4.identity();
            }),
            itemBuilder: (_, i) {
              final image = Center(
                  child: Image.file(File(_chemins[i]), fit: BoxFit.contain));
              return GestureDetector(
                onDoubleTapDown: (d) => toucher = d.localPosition,
                onDoubleTap: () => setPlein(() {
                  if (zoomee) {
                    zoom.value = Matrix4.identity();
                    zoomee = false;
                  } else {
                    const x = 2.5;
                    zoom.value = Matrix4.identity()
                      ..translate(-toucher.dx * (x - 1), -toucher.dy * (x - 1))
                      ..scale(x);
                    zoomee = true;
                  }
                }),
                child: zoomee && i == index
                    ? InteractiveViewer(
                        transformationController: zoom,
                        maxScale: 5,
                        child: image)
                    : image,
              );
            },
          ),
        ),
      ),
    ));
    page.dispose();
    zoom.dispose();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final n = _chemins.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Touche une photo pour la voir en grand'.tr,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
          ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
            child: GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var i = 0; i < n; i++)
                  GestureDetector(
                    onTap: () => _agrandir(i),
                    child: Stack(fit: StackFit.expand, children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(_chemins[i]),
                            fit: BoxFit.cover, cacheWidth: 300),
                      ),
                      // ✕ retirer cette photo
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _retirer(_chemins[i]),
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.voileMedia,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.surMedia, width: 1.5),
                            ),
                            child: Icon(Icons.close_rounded,
                                size: 16, color: AppColors.surMedia),
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (n < _max)
                  GestureDetector(
                    onTap: _ajouter,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Icon(Icons.add_photo_alternate_outlined,
                          color: AppColors.textMuted, size: 30),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.send_rounded, color: AppColors.surAccent),
              label: Text(
                  n == 1
                      ? 'Envoyer la photo'.tr
                      : 'Envoyer @n photos'.trParams({'n': '$n'}),
                  style: const TextStyle(
                      color: AppColors.surAccent, fontWeight: FontWeight.w700)),
              onPressed: () async {
                final aEnvoyer = [..._chemins];
                Get.back();
                for (final c in aEnvoyer) {
                  if (!widget.ctrl.peutEnvoyer()) break;
                  widget.ctrl.envoyerMediaEnFond(chemin: c, video: false);
                  // identifiants temporaires distincts (horodatage en ms)
                  await Future.delayed(const Duration(milliseconds: 30));
                }
              },
            ),
          ),
        ]),
      ),
    );
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
  final _legende = TextEditingController();

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
    _legende.dispose();
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
                  color: Color(0x3DFFFFFF),
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
                        child: CircularProgressIndicator(
                            color: AppColors.surMedia)))
                : Image.file(File(widget.filePath), fit: BoxFit.contain),
          )),
          // Légende (pas pour un snap éphémère)
          if (!_modeEphemere)
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _legende,
                maxLength: 1000,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ajouter une légende…'.tr,
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.surface2,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
          if (_modeEphemere && _showDureePicker)
            Container(
                color: AppColors.surface,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text('Durée d\'affichage après ouverture'.tr,
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
              // Éphémère : photo ou vidéo (snap)
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
                    Text(_modeEphemere ? _duree.label : 'Éphémère'.tr,
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
                  child: Text(_sensible ? '🔞 Sensible'.tr : '🔞',
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
                              strokeWidth: 2, color: AppColors.surAccent))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.send_rounded,
                              color: AppColors.surAccent, size: 18),
                          SizedBox(width: 6),
                          Text('Envoyer'.tr,
                              style: TextStyle(
                                  color: AppColors.surAccent,
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
      ephemere: _modeEphemere,
      snapSecondes: _modeEphemere ? _duree.seconds : null,
      sensible: _sensible,
      // Pas de légende sur un snap (il disparaît, le texte resterait)
      legende: _modeEphemere ? null : _legende.text,
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
