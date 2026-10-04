part of 'conversation_screen.dart';

// ═══════════════════════════════════════════════════════════════════
//  MÉDIAS : snaps, photos, vidéos, vocaux, position
//  (découpé de conversation_screen.dart — même bibliothèque,
//  les classes privées restent partagées)
// ═══════════════════════════════════════════════════════════════════

class _SnapBubble extends StatefulWidget {
  final MessageModel msg;
  final bool isMine;
  final ConversationController ctrl;
  final VoidCallback onTap;
  const _SnapBubble(
      {required this.msg,
      required this.isMine,
      required this.ctrl,
      required this.onTap});
  @override
  State<_SnapBubble> createState() => _SnapBubbleState();
}

class _SnapBubbleState extends State<_SnapBubble> {
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.msg.isOpened && widget.msg.expiresAt != null) _startCountdown();
  }

  // ✅ FIX — le message devient "ouvert" APRÈS la création du widget
  // (openSnap met à jour isOpened/expiresAt) : on démarre alors le
  // compte à rebours, sinon "Snap expiré" s'affichait immédiatement.
  @override
  void didUpdateWidget(covariant _SnapBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final msg = widget.msg;
    if (msg.isOpened &&
        msg.expiresAt != null &&
        (!oldWidget.msg.isOpened ||
            oldWidget.msg.expiresAt != msg.expiresAt)) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    if (widget.msg.expiresAt == null) return;
    _timer?.cancel(); // ✅ FIX — pas de double timer
    final rem = widget.msg.expiresAt!.difference(DateTime.now()).inSeconds;
    if (rem <= 0) return;
    // ✅ FIX — appelé depuis initState/didUpdateWidget, un build suit
    // toujours : affectation directe au lieu de setState.
    _countdown = rem;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = widget.msg.expiresAt!.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        t.cancel();
        if (mounted) setState(() => _countdown = 0);
        return;
      }
      if (mounted) setState(() => _countdown = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final hasPhoto = msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty;
    final isMine = widget.isMine;

    if (isMine) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            gradient: AppColors.gradientPink,
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Snap envoyé',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(msg.isOpened ? 'Ouvert ✓' : 'En attente',
                    style: TextStyle(
                        fontSize: 10, color: Colors.white.withOpacity(0.7))),
              ]),
        ]),
      );
    }

    if (msg.isOpened && hasPhoto && _countdown > 0) {
      final urgent = _countdown <= 3;
      return Stack(children: [
        GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      _PleinEcranMedia(url: msg.mediaUrl!, isVideo: false))),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                  imageUrl: msg.mediaUrl!,
                  width: 210,
                  height: 260,
                  fit: BoxFit.cover)),
        ),
        Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: urgent ? Colors.red.withOpacity(0.85) : Colors.black54,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${_countdown}s',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            )),
        Positioned(
            bottom: 8,
            left: 10,
            right: 10,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    value: _countdown / 10.0,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        urgent ? Colors.red : AppColors.accent3),
                    minHeight: 3))),
      ]);
    }

    if (!msg.isOpened && hasPhoto) {
      return GestureDetector(
        onTap: () {
          widget.onTap();
          Future.delayed(const Duration(milliseconds: 100), () {
            final ctx = Get.context;
            if (ctx == null) return;
            Navigator.push(
                ctx,
                MaterialPageRoute(
                    builder: (_) => _SnapPleinEcran(
                        url: msg.mediaUrl!,
                        snapDuration: msg.snapDurationSec ?? 10)));
          });
        },
        child: Container(
          width: 210,
          height: 85,
          decoration: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(16)),
          child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_camera_rounded, size: 26, color: Colors.white),
                SizedBox(height: 6),
                Text('Appuie pour voir',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text('Disparaît après ouverture',
                    style: TextStyle(fontSize: 10, color: Colors.white70)),
              ]),
        ),
      );
    }

    // Trace laissée après l'ouverture (comme Snapchat) : la photo n'existe
    // plus, mais on sait qu'un snap a été reçu et vu.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.photo_camera_outlined, size: 15, color: AppColors.accent),
        const SizedBox(width: 8),
        Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(msg.isOpened ? 'Snap ouvert' : 'Snap expiré',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(msg.isOpened ? 'Photo éphémère vue ✓' : 'Non ouvert à temps',
                  style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
            ]),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SNAP PLEIN ÉCRAN
// ═══════════════════════════════════════════════════════════════════

class _SnapPleinEcran extends StatefulWidget {
  final String url;
  final int snapDuration;
  const _SnapPleinEcran({required this.url, required this.snapDuration});
  @override
  State<_SnapPleinEcran> createState() => _SnapPleinEcranState();
}

class _SnapPleinEcranState extends State<_SnapPleinEcran> {
  late int _countdown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _countdown = widget.snapDuration;
    if (_countdown > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _countdown--);
        if (_countdown <= 0) {
          t.cancel();
          if (mounted) Navigator.pop(context);
        }
      });
    } else {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _countdown <= 3 && _countdown > 0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
            child: CachedNetworkImage(
                imageUrl: widget.url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white38, size: 48)))),
        if (widget.snapDuration > 0)
          Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color:
                        urgent ? Colors.red.withOpacity(0.85) : Colors.black54,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_rounded,
                      size: 14, color: urgent ? Colors.white : Colors.white70),
                  const SizedBox(width: 5),
                  Text('${_countdown}s',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: urgent ? Colors.white : Colors.white70)),
                ]),
              )),
        if (widget.snapDuration > 0)
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                  value: _countdown / widget.snapDuration,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      urgent ? Colors.red : AppColors.accent3),
                  minHeight: 4)),
        Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MEDIA BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _MediaBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine, isVideo;
  const _MediaBubble(
      {required this.msg, required this.isMine, required this.isVideo});

  bool get _isVideoUrl {
    final url = msg.mediaUrl ?? '';
    return url.contains('.mp4') ||
        url.contains('.mov') ||
        url.contains('.avi') ||
        url.contains('video') ||
        isVideo;
  }

  // Pendant l'envoi, la photo / vidéo est encore un fichier du téléphone
  static bool _local(String? u) => u != null && u.isNotEmpty && !u.startsWith('http');

  static String _duree(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  Widget _image(String src, {double w = 220, double h = 260}) => _local(src)
      ? Image.file(File(src),
          width: w,
          height: h,
          fit: BoxFit.cover,
          cacheWidth: 440,
          errorBuilder: (_, __, ___) => _fallback())
      : CachedNetworkImage(
          imageUrl: src,
          width: w,
          height: h,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 100),
          memCacheWidth: 440,
          placeholder: (_, __) => Container(
              width: w,
              height: h,
              color: AppColors.surface2,
              child: Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accent, strokeWidth: 2))),
          errorWidget: (_, __, ___) => _fallback());

  @override
  Widget build(BuildContext context) {
    if (msg.mediaUrl == null || msg.mediaUrl!.isEmpty) return _fallback();
    final video = _isVideoUrl;
    final vignette = msg.vignetteUrl ?? '';

    Widget contenu;
    if (video) {
      // Vidéo : son image + bouton lecture + durée (comme WhatsApp)
      contenu = SizedBox(
        width: 220,
        height: 260,
        child: Stack(fit: StackFit.expand, children: [
          if (vignette.isNotEmpty)
            _image(vignette)
          else
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.surface2, AppColors.bg],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          if (!msg.enEnvoi)
            const Center(
              child: CircleAvatar(
                radius: 26,
                backgroundColor: Colors.black45,
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 34),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 13),
                if (msg.audioDurationSec != null) ...[
                  const SizedBox(width: 4),
                  Text(_duree(msg.audioDurationSec!),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ),
        ]),
      );
    } else {
      contenu = _image(msg.mediaUrl!);
    }

    // Envoi en cours : voile + étape (Compression… / Envoi…)
    if (msg.enEnvoi) {
      contenu = Stack(children: [
        contenu,
        Positioned.fill(
          child: Container(
            color: Colors.black45,
            child: Center(
              child: Obx(() {
                final etat =
                    ConversationController.etatsEnvoi[msg.id] ?? 'Envoi…';
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(etat,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ]);
              }),
            ),
          ),
        ),
      ]);
    }

    return GestureDetector(
      onTap: msg.enEnvoi
          ? null
          : () {
              final ctx = Get.context ?? context;
              Navigator.push(
                  ctx,
                  MaterialPageRoute(
                      builder: (_) => _PleinEcranMedia(
                          url: msg.mediaUrl!, isVideo: video)));
            },
      child: ClipRRect(borderRadius: BorderRadius.circular(14), child: contenu),
    );
  }

  Widget _fallback() => Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14), color: AppColors.surface2),
      child: const Center(
          child: Icon(Icons.broken_image_rounded,
              size: 36, color: Colors.white38)));
}

// ═══════════════════════════════════════════════════════════════════
//  PLEIN ÉCRAN MEDIA
// ═══════════════════════════════════════════════════════════════════

class _PleinEcranMedia extends StatefulWidget {
  final String url;
  final bool isVideo;
  const _PleinEcranMedia({required this.url, required this.isVideo});
  @override
  State<_PleinEcranMedia> createState() => _PleinEcranMediaState();
}

class _PleinEcranMediaState extends State<_PleinEcranMedia> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _videoCtrl!.initialize().then((_) {
        if (mounted) {
          setState(() => _videoReady = true);
          _videoCtrl!.play();
        }
      }).catchError((e) {
        // ✅ Vidéo supprimée (message éphémère) / réseau
        debugPrint('Vidéo du message non chargée : $e');
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (widget.isVideo && _videoReady)
            IconButton(
              icon: Icon(
                  _videoCtrl!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white),
              onPressed: () {
                setState(() {
                  _videoCtrl!.value.isPlaying
                      ? _videoCtrl!.pause()
                      : _videoCtrl!.play();
                });
              },
            ),
        ],
      ),
      body: Center(
          child: widget.isVideo
              ? (_videoReady && _videoCtrl != null
                  ? AspectRatio(
                      aspectRatio: _videoCtrl!.value.aspectRatio,
                      child: VideoPlayer(_videoCtrl!))
                  : const CircularProgressIndicator(color: Colors.white))
              : InteractiveViewer(
                  child: CachedNetworkImage(
                      imageUrl: widget.url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) =>
                          const CircularProgressIndicator(color: Colors.white),
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                          size: 48)))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AUDIO BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _AudioBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  final ConversationController ctrl;
  const _AudioBubble(
      {required this.msg, required this.isMine, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final dur = msg.audioDurationSec ?? 0;
    final min = (dur ~/ 60).toString().padLeft(2, '0');
    final sec = (dur % 60).toString().padLeft(2, '0');
    return Obx(() {
      final isPlaying = ctrl.currentlyPlayingId.value == msg.id;
      return GestureDetector(
        onTap: () {
          if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty)
            ctrl.playAudio(msg.mediaUrl!, msg.id);
        },
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              gradient: isMine ? AppColors.gradientPink : null,
              color: isMine ? null : AppColors.surface2,
              borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15)),
                child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white)),
            const SizedBox(width: 8),
            Flexible(child: _AudioWaveform(isPlaying: isPlaying)),
            const SizedBox(width: 8),
            Text('$min:$sec',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500)),
            if (isPlaying) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: ctrl.changerVitesseAudio,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(ctrl.vitesseAudioLabel,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
        ),
      );
    });
  }
}

class _AudioWaveform extends StatefulWidget {
  final bool isPlaying;
  const _AudioWaveform({required this.isPlaying});
  @override
  State<_AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<_AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _h = [6.0, 12, 8, 16, 10, 18, 7, 20, 9, 15, 17, 8, 11, 14, 9, 7];
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => SizedBox(
              height: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(_h.length, (i) {
                  final phase = (i / _h.length + _ctrl.value) % 1.0;
                  final h = widget.isPlaying
                      ? _h[i] * (0.4 + 0.6 * math.sin(phase * 2 * math.pi))
                      : _h[i] * 0.4;
                  return Container(
                      width: 2.5,
                      height: h.clamp(3.0, 18.0),
                      margin: const EdgeInsets.symmetric(horizontal: 0.8),
                      decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(widget.isPlaying ? 0.9 : 0.4),
                          borderRadius: BorderRadius.circular(1.5)));
                }),
              ),
            ));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ STATUS ICON — avec "Lu HH:MM"
// ═══════════════════════════════════════════════════════════════════

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final DateTime? readAt; // ✅ heure de lecture
  const _StatusIcon({required this.status, this.readAt});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textMuted));
      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: 12, color: AppColors.textMuted);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded,
            size: 12, color: AppColors.textMuted);
      case MessageStatus.read:
        // ✅ Affiche "Lu HH:MM" si on a l'heure, sinon double coche rose
        if (readAt != null) {
          final h = readAt!.hour.toString().padLeft(2, '0');
          final m = readAt!.minute.toString().padLeft(2, '0');
          return Text('Lu $h:$m',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600));
        }
        return ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Icon(Icons.done_all_rounded,
                size: 12, color: Colors.white));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  LOCATION BUBBLE
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  LOCATION BUBBLE — design moderne façon Telegram/WhatsApp
// ═══════════════════════════════════════════════════════════════════

class _LocationBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _LocationBubble({required this.msg, required this.isMine});

  LatLng? _parseLatLng() {
    final c = msg.text ?? '';
    if (c.contains(',') && !c.startsWith('http')) {
      final p = c.split(',');
      if (p.length == 2) {
        final lat = double.tryParse(p[0].trim());
        final lng = double.tryParse(p[1].trim());
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }
    return null;
  }

  Future<void> _open(LatLng pt) async {
    final geoUri = Uri.parse(
        'geo:${pt.latitude},${pt.longitude}?q=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    final gUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(gUri)) {
      await launchUrl(gUri, mode: LaunchMode.externalApplication);
    }
  }

  String _coordsLabel(LatLng pt) {
    return '${pt.latitude.toStringAsFixed(4)}, ${pt.longitude.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final pt = _parseLatLng();
    return Container(
      width: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color:
                isMine ? AppColors.accent.withOpacity(0.35) : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Carte avec pin flottant ──
        GestureDetector(
          onTap: pt != null ? () => _open(pt) : null,
          child: SizedBox(
            height: 150,
            child: pt != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      FlutterMap(
                        options: MapOptions(
                            initialCenter: pt,
                            initialZoom: 15.5,
                            interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none)),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.vybestyle.zamu',
                          ),
                        ],
                      ),
                      // Léger voile pour unifier la carte avec le thème sombre
                      Container(color: Colors.black.withOpacity(0.12)),
                      // Pin central avec ombre douce, style goutte moderne
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.gradientPink,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withOpacity(0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.location_on_rounded,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badge "en direct" discret en haut à gauche
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location_rounded,
                                  size: 10, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('Position',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: AppColors.surface,
                    child: Center(
                        child: Icon(Icons.map_outlined,
                            size: 32, color: AppColors.textMuted)),
                  ),
          ),
        ),

        // ── Footer avec infos + bouton ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withOpacity(0.12),
              ),
              child:
                  Icon(Icons.place_rounded, size: 16, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Position partagée',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  if (pt != null) ...[
                    const SizedBox(height: 1),
                    Text(_coordsLabel(pt),
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
            if (pt != null)
              GestureDetector(
                onTap: () => _open(pt),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.directions_rounded,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    const Text('Itinéraire',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  INPUT BAR
// ═══════════════════════════════════════════════════════════════════
