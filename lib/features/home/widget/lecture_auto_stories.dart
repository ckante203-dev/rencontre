import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Lecture automatique des vidéos dans la grille « Découvrir » (comme
/// Snapchat) : UNE seule vidéo à la fois — la plus visible à l'écran —,
/// en boucle et SANS le son tant qu'on ne touche pas. Par défaut seulement
/// en Wi-Fi (forfaits mobiles limités) ; réglable dans les Paramètres.
class LectureAutoStories extends GetxController {
  static LectureAutoStories get to => Get.isRegistered<LectureAutoStories>()
      ? Get.find()
      : Get.put(LectureAutoStories(), permanent: true);

  static const _cleDonnees = 'lecture_auto_donnees_mobiles';

  /// Story dont la vidéo est en lecture (null = aucune)
  final RxnString active = RxnString();
  final _visibles = <String, double>{};
  bool _wifi = true;

  /// Lecture aussi en données mobiles (réglage, désactivé par défaut)
  final RxBool aussiEnDonnees =
      (GetStorage().read<bool>(_cleDonnees) ?? false).obs;

  void reglerDonnees(bool v) {
    aussiEnDonnees.value = v;
    GetStorage().write(_cleDonnees, v);
    _choisir();
  }

  @override
  void onInit() {
    super.onInit();
    Connectivity().checkConnectivity().then(_majReseau).catchError((_) {});
    Connectivity().onConnectivityChanged.listen(_majReseau);
  }

  void _majReseau(List<ConnectivityResult> r) {
    _wifi = r.contains(ConnectivityResult.wifi) ||
        r.contains(ConnectivityResult.ethernet);
    _choisir();
  }

  void signaler(String id, double fraction) {
    if (fraction <= 0) {
      _visibles.remove(id);
    } else {
      _visibles[id] = fraction;
    }
    _choisir();
  }

  void _choisir() {
    if (!_wifi && !aussiEnDonnees.value) {
      active.value = null;
      return;
    }
    String? meilleur;
    var max = 0.6; // au moins 60 % de la carte visible
    _visibles.forEach((id, f) {
      if (f > max) {
        max = f;
        meilleur = id;
      }
    });
    if (active.value != meilleur) active.value = meilleur;
  }
}

/// Aperçu vidéo d'une carte : image fixe [vignette], remplacée par la
/// vidéo muette quand cette carte est la plus visible.
class ApercuVideoAuto extends StatelessWidget {
  final String id;
  final String url;
  final int? debutMs;
  final Widget vignette;
  const ApercuVideoAuto({
    super.key,
    required this.id,
    required this.url,
    required this.vignette,
    this.debutMs,
  });

  @override
  Widget build(BuildContext context) {
    final lecture = LectureAutoStories.to;
    return VisibilityDetector(
      key: Key('lecture_auto_$id'),
      onVisibilityChanged: (i) => lecture.signaler(id, i.visibleFraction),
      child: Obx(() => lecture.active.value == id
          ? _VideoMuette(url: url, debutMs: debutMs, vignette: vignette)
          : vignette),
    );
  }
}

class _VideoMuette extends StatefulWidget {
  final String url;
  final int? debutMs;
  final Widget vignette;
  const _VideoMuette(
      {required this.url, required this.vignette, this.debutMs});

  @override
  State<_VideoMuette> createState() => _VideoMuetteState();
}

class _VideoMuetteState extends State<_VideoMuette> {
  late final VideoPlayerController _c =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _pret = false;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) async {
      if (!mounted) return;
      await _c.setVolume(0);
      await _c.setLooping(true);
      if ((widget.debutMs ?? 0) > 0) {
        await _c.seekTo(Duration(milliseconds: widget.debutMs!));
      }
      await _c.play();
      if (mounted) setState(() => _pret = true);
    }).catchError((_) {}); // vidéo indisponible : la vignette reste
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_pret) return widget.vignette;
    return Stack(fit: StackFit.expand, children: [
      FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: _c.value.size.width,
          height: _c.value.size.height,
          child: VideoPlayer(_c),
        ),
      ),
      // Son coupé (comme Snapchat)
      const Positioned(
        left: 8,
        top: 8,
        child: Icon(Icons.volume_off_rounded,
            color: Color(0xE6FFFFFF), size: 20),
      ),
    ]);
  }
}
