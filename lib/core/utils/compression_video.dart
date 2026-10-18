import 'dart:async';
import 'dart:io';

import 'package:video_compress/video_compress.dart';

// video_compress ne sait faire qu'une compression à la fois : une 2ᵉ
// lancée pendant la 1ʳᵉ annule celle-ci, puis le plugin lit les infos d'un
// fichier de sortie qui n'existe plus et fait planter l'appli côté Android
// (IllegalArgumentException « … does not exist », impossible à rattraper
// en Dart). Tous les appels passent donc ici, l'un après l'autre, et
// seulement sur un fichier qui existe.

Future<void> _file = Future.value();

Future<T> _uneALaFois<T>(Future<T> Function() tache) {
  final suite = _file.then((_) => tache());
  _file = suite.then((_) {}, onError: (_) {});
  return suite;
}

/// Infos de la vidéo (durée, taille), ou null si le fichier n'existe pas.
Future<MediaInfo?> infosVideo(String chemin) => _uneALaFois(() async {
      if (!await File(chemin).exists()) return null;
      return VideoCompress.getMediaInfo(chemin);
    });

/// Vidéo compressée, ou null (fichier absent, échec) : on garde alors
/// l'original.
Future<File?> compresserVideo(String chemin,
        {VideoQuality qualite = VideoQuality.Res1280x720Quality,
        bool supprimerOriginal = false}) =>
    _uneALaFois(() async {
      if (!await File(chemin).exists()) return null;
      final info = await VideoCompress.compressVideo(chemin,
          quality: qualite, deleteOrigin: supprimerOriginal, includeAudio: true);
      final sortie = info?.file;
      return sortie != null && await sortie.exists() ? sortie : null;
    });

/// Vignette de la vidéo, ou null si le fichier n'existe pas.
Future<File?> vignetteVideo(String chemin) => _uneALaFois(() async {
      if (!await File(chemin).exists()) return null;
      return VideoCompress.getFileThumbnail(chemin, quality: 60, position: -1);
    });

/// Vide le cache du plugin, après les compressions en cours.
Future<void> viderCacheVideo() =>
    _uneALaFois(() => VideoCompress.deleteAllCache().then((_) {}));
