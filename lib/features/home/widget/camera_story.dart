import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

// ─── CAMÉRA ZAMU (ajout de story façon Snap / Instagram) ───────────
// Plein écran dans l'app : toucher = photo, maintenir = vidéo (30 s max,
// anneau de progression), pincer = zoom, double-toucher = retourner,
// flash. Vignette galerie à gauche, onglets TEXTE | STORY en bas.

class CameraStory extends StatefulWidget {
  /// Photo ou vidéo prise : chemin du fichier. [miroir] = selfie, à
  /// afficher et publier comme dans le miroir de l'aperçu.
  final void Function(String chemin, bool video, bool miroir) onMedia;
  final VoidCallback onGalerie;
  final VoidCallback onTexte;
  final VoidCallback onFermer;

  const CameraStory({
    super.key,
    required this.onMedia,
    required this.onGalerie,
    required this.onTexte,
    required this.onFermer,
  });

  @override
  State<CameraStory> createState() => _CameraStoryState();
}

class _CameraStoryState extends State<CameraStory>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _dureeMax = Duration(seconds: 30);
  // Dernière caméra utilisée (avant / arrière), gardée pendant la session
  static CameraLensDirection _sensMemorise = CameraLensDirection.back;

  List<CameraDescription> _cameras = [];
  CameraController? _ctrl;
  bool _pret = false;
  bool _refus = false; // permission refusée
  String? _erreur;
  bool _flash = false;
  bool _occupe = false; // prise de photo en cours
  bool _enregistre = false;
  bool _aideVue = false;
  Uint8List? _miniature; // dernière photo / vidéo du téléphone (galerie)
  bool _miniatureVideo = false;
  double _zoom = 1, _zoomMin = 1, _zoomMax = 1, _zoomDepart = 1;
  late final AnimationController _progression =
      AnimationController(vsync: this, duration: _dureeMax)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _arreterVideo();
        });

  CameraDescription? get _camera => _ctrl?.description;
  bool get _avant => _camera?.lensDirection == CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _demarrer();
    _chargerMiniature();
  }

  /// Miniature du dernier média de la galerie (comme Telegram), seulement
  /// si l'accès aux photos a déjà été donné : on ne redemande rien ici.
  Future<void> _chargerMiniature() async {
    try {
      final etat = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(
          androidPermission:
              AndroidPermission(type: RequestType.common, mediaLocation: false),
        ),
      );
      if (!etat.hasAccess) return;
      final albums = await PhotoManager.getAssetPathList(
          onlyAll: true, type: RequestType.common);
      if (albums.isEmpty) return;
      final derniers = await albums.first.getAssetListPaged(page: 0, size: 1);
      if (derniers.isEmpty) return;
      final m = await derniers.first
          .thumbnailDataWithSize(const ThumbnailSize.square(160));
      if (!mounted || m == null) return;
      setState(() {
        _miniature = m;
        _miniatureVideo = derniers.first.type == AssetType.video;
      });
    } catch (e) {
      debugPrint('Miniature galerie : $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progression.dispose();
    _ctrl?.dispose();
    super.dispose();
  }

  // Android libère la caméra quand l'app passe en arrière-plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (state == AppLifecycleState.inactive) {
      // Caméra encore en train de démarrer : on la laisse finir (la
      // libérer maintenant ferait planter son initialisation).
      if (c == null || !c.value.isInitialized) return;
      if (_enregistre) _arreterVideo();
      _ctrl = null;
      if (mounted) setState(() => _pret = false);
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (c == null && !_refus) _demarrer();
      _chargerMiniature(); // une photo a pu être prise entre-temps
    }
  }

  Future<void> _demarrer() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _erreur = 'Aucun appareil photo disponible');
        return;
      }
      final cam = _cameras.firstWhere((c) => c.lensDirection == _sensMemorise,
          orElse: () => _cameras.first);
      await _ouvrir(cam);
    } on CameraException catch (e) {
      _gererErreur(e);
    }
  }

  Future<void> _ouvrir(CameraDescription cam) async {
    final ancien = _ctrl;
    final ctrl = CameraController(cam, ResolutionPreset.veryHigh,
        enableAudio: true, imageFormatGroup: ImageFormatGroup.jpeg);
    _ctrl = ctrl;
    if (mounted) setState(() => _pret = false);
    await ancien?.dispose();
    try {
      await ctrl.initialize();
      if (!mounted || _ctrl != ctrl) return;
      _zoomMin = await ctrl.getMinZoomLevel();
      _zoomMax = (await ctrl.getMaxZoomLevel()).clamp(1, 8).toDouble();
      _zoom = _zoomMin;
      await ctrl.setFlashMode(FlashMode.off);
      _flash = false;
      _sensMemorise = cam.lensDirection;
      setState(() {
        _pret = true;
        _refus = false;
        _erreur = null;
      });
    } on CameraException catch (e) {
      if (_ctrl == ctrl) _gererErreur(e);
    } catch (e) {
      // Contrôleur remplacé / libéré pendant le démarrage : rien à faire
      debugPrint('CameraStory ouverture interrompue : $e');
    }
  }

  void _gererErreur(CameraException e) {
    debugPrint('CameraStory : ${e.code} ${e.description}');
    if (!mounted) return;
    final refus = e.code.contains('AccessDenied') ||
        e.code.contains('AccessRestricted');
    setState(() {
      _refus = refus;
      _erreur = refus ? null : 'Appareil photo indisponible';
    });
  }

  Future<void> _retourner() async {
    if (_enregistre || _cameras.length < 2 || _camera == null) return;
    HapticFeedback.selectionClick();
    final cible = _avant ? CameraLensDirection.back : CameraLensDirection.front;
    final cam = _cameras.firstWhere((c) => c.lensDirection == cible,
        orElse: () => _cameras.first);
    await _ouvrir(cam);
  }

  Future<void> _basculerFlash() async {
    final c = _ctrl;
    if (c == null || !_pret) return;
    _flash = !_flash;
    try {
      await c.setFlashMode(_flash ? FlashMode.always : FlashMode.off);
    } catch (_) {}
    setState(() {});
  }

  Future<void> _photo() async {
    final c = _ctrl;
    if (c == null || !_pret || _occupe || _enregistre) return;
    setState(() => _occupe = true);
    HapticFeedback.lightImpact();
    try {
      final f = await c.takePicture();
      // Selfie : affichée tout de suite en miroir, retournée à la
      // publication (comme Snap / Instagram)
      if (mounted) widget.onMedia(f.path, false, _avant);
    } catch (e) {
      debugPrint('takePicture : $e');
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  // Vidéo : l'appui long démarre après 0,2 s ; le démarrage de
  // l'enregistrement prend encore un instant. Si le doigt est relevé
  // pendant ce temps, on arrête dès que l'enregistrement a commencé.
  final Stopwatch _chronoVideo = Stopwatch();
  bool _demarrage = false;
  bool _relacheTot = false;
  static const _dureeMin = Duration(seconds: 1);

  Future<void> _demarrerVideo() async {
    final c = _ctrl;
    if (c == null || !_pret || _occupe || _enregistre || _demarrage) return;
    _demarrage = true;
    _relacheTot = false;
    try {
      if (_flash && !_avant) await c.setFlashMode(FlashMode.torch);
      await c.startVideoRecording();
      _chronoVideo
        ..reset()
        ..start();
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _enregistre = true;
        _aideVue = true;
      });
      _progression.forward(from: 0);
    } catch (e) {
      debugPrint('startVideoRecording : $e');
    } finally {
      _demarrage = false;
    }
    if (_relacheTot) _arreterVideo();
  }

  Future<void> _arreterVideo() async {
    if (_demarrage) {
      _relacheTot = true; // arrêt dès que l'enregistrement a commencé
      return;
    }
    final c = _ctrl;
    if (c == null || !_enregistre) return;
    // Une vidéo d'au moins 1 s (un appui court donne un petit clip)
    final reste = _dureeMin - _chronoVideo.elapsed;
    if (reste > Duration.zero) await Future.delayed(reste);
    if (!_enregistre) return;
    _progression.stop();
    _chronoVideo.stop();
    setState(() => _enregistre = false);
    try {
      final f = await c.stopVideoRecording();
      if (_flash) await c.setFlashMode(FlashMode.always);
      if (mounted) widget.onMedia(f.path, true, false);
    } catch (e) {
      debugPrint('stopVideoRecording : $e');
    }
  }

  Future<void> _zoomer(double z) async {
    final c = _ctrl;
    if (c == null || !_pret) return;
    final v = z.clamp(_zoomMin, _zoomMax);
    if ((v - _zoom).abs() < 0.01) return;
    _zoom = v;
    try {
      await c.setZoomLevel(v);
    } catch (_) {}
  }

  // ── Affichage ────────────────────────────────────────────────────

  Widget _apercu(Size ecran) {
    final c = _ctrl;
    if (_refus) {
      return _message('Autorise l\'appareil photo pour prendre une story',
          bouton: 'Ouvrir les réglages', action: openAppSettings);
    }
    if (_erreur != null) return _message(_erreur!);
    if (c == null || !_pret) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white54));
    }
    // Remplit l'écran (comme Snap) : on rogne ce qui dépasse
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: ecran.width,
            height: ecran.width * c.value.aspectRatio,
            child: CameraPreview(c),
          ),
        ),
      ),
    );
  }

  Widget _message(String texte, {String? bouton, VoidCallback? action}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography_rounded,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(texte,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            if (bouton != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: action,
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54)),
                child: Text(bouton),
              ),
            ],
          ]),
        ),
      );

  Widget _boutonRond(IconData icon, VoidCallback onTap, {double taille = 26}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
              color: Colors.black38, shape: BoxShape.circle),
          child: Icon(icon, color: Colors.white, size: taille),
        ),
      );

  String _chrono() {
    final s = (_progression.value * _dureeMax.inSeconds).floor();
    return '0:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ecran = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // ── Aperçu : pincer = zoom, double-toucher = retourner ──
        GestureDetector(
          onDoubleTap: _retourner,
          onScaleStart: (_) => _zoomDepart = _zoom,
          onScaleUpdate: (d) {
            if (d.pointerCount >= 2) _zoomer(_zoomDepart * d.scale);
          },
          child: _apercu(ecran),
        ),

        // ── Haut : fermer, chrono, flash, retourner ──
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_enregistre)
                  _boutonRond(Icons.close_rounded, widget.onFermer),
                const Spacer(),
                if (_enregistre)
                  AnimatedBuilder(
                    animation: _progression,
                    builder: (_, __) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(14)),
                      child: Text(_chrono(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                const Spacer(),
                if (!_enregistre)
                  Column(children: [
                    if (!_avant && _pret)
                      _boutonRond(
                          _flash
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          _basculerFlash),
                    const SizedBox(height: 12),
                    if (_cameras.length > 1)
                      _boutonRond(Icons.flip_camera_android_rounded, _retourner),
                  ]),
              ],
            ),
          ),
        ),

        // ── Bas : galerie, déclencheur, onglets ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedOpacity(
                  opacity: _aideVue || !_pret ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('Touche pour une photo · maintiens pour filmer',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            shadows: [Shadow(blurRadius: 6)])),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Galerie
                    SizedBox(
                      width: 56,
                      child: _enregistre
                          ? null
                          : GestureDetector(
                              onTap: widget.onGalerie,
                              child: Container(
                                width: 44,
                                height: 44,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  color: Colors.black38,
                                ),
                                child: _miniature == null
                                    ? const Icon(Icons.photo_library_rounded,
                                        color: Colors.white, size: 22)
                                    : Stack(fit: StackFit.expand, children: [
                                        Image.memory(_miniature!,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true),
                                        if (_miniatureVideo)
                                          const Center(
                                              child: Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: Colors.white,
                                                  size: 20)),
                                      ]),
                              ),
                            ),
                    ),
                    // Déclencheur
                    RawGestureDetector(
                      gestures: {
                        TapGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                    TapGestureRecognizer>(
                                TapGestureRecognizer.new,
                                (r) => r.onTap = _photo),
                        // 0,2 s d'appui suffisent pour filmer (au lieu de 0,5)
                        LongPressGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                                    LongPressGestureRecognizer>(
                                () => LongPressGestureRecognizer(
                                    duration:
                                        const Duration(milliseconds: 200)),
                                (r) => r
                                  ..onLongPressStart = ((_) => _demarrerVideo())
                                  ..onLongPressEnd = ((_) => _arreterVideo())
                                  ..onLongPressCancel = _arreterVideo),
                      },
                      child: AnimatedBuilder(
                        animation: _progression,
                        builder: (_, __) => SizedBox(
                          width: 86,
                          height: 86,
                          child: Stack(alignment: Alignment.center, children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: _enregistre ? 86 : 76,
                              height: _enregistre ? 86 : 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _enregistre
                                    ? Colors.red.withValues(alpha: 0.35)
                                    : Colors.transparent,
                                border:
                                    Border.all(color: Colors.white, width: 5),
                              ),
                            ),
                            if (_enregistre)
                              SizedBox(
                                width: 86,
                                height: 86,
                                child: CircularProgressIndicator(
                                  value: _progression.value,
                                  strokeWidth: 5,
                                  color: Colors.red,
                                ),
                              ),
                            if (_occupe)
                              const SizedBox(
                                width: 28,
                                height: 28,
                                child: CircularProgressIndicator(
                                    strokeWidth: 3, color: Colors.white),
                              ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 56),
                  ],
                ),
                const SizedBox(height: 14),
                if (!_enregistre)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: widget.onTexte,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          child: Text('TEXTE',
                              style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1)),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Text('STORY',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1)),
                      ),
                      const SizedBox(width: 60), // équilibre visuel
                    ],
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
