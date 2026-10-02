import 'package:video_player/video_player.dart';

final Expando<Future<void>> _initialisations = Expando<Future<void>>();

/// Initialise un contrôleur vidéo UNE seule fois, même si plusieurs écrans le
/// demandent (préchargement de l'accueil puis viewer de story).
///
/// Un 2ᵉ `initialize()` sur le même contrôleur enregistre un 2ᵉ observateur
/// de cycle de vie dans video_player, jamais retiré au dispose : à la mise
/// en arrière-plan il appelait pause() sur un contrôleur libéré
/// (« A VideoPlayerController was used after being disposed »).
Future<void> initialiserUneFois(VideoPlayerController ctrl) =>
    _initialisations[ctrl] ??= ctrl.initialize();
