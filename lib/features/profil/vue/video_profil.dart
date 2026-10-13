import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

/// Vidéo de profil (15 s) : déposée par la personne, montrée aux autres
/// seulement après validation par l'équipe Zamu (SQL 055).
class VideoProfilService {
  VideoProfilService._();
  static SupabaseClient get _sb => Supabase.instance.client;

  /// {url, statut, motif} de la vidéo d'un profil (null si aucune)
  static Future<Map<String, dynamic>?> de(String userId) async {
    try {
      final r = await _sb
          .from('profiles')
          .select('video_url, video_statut, video_motif')
          .eq('id', userId)
          .maybeSingle();
      if (r == null || (r['video_url'] ?? '').toString().isEmpty) return null;
      return r;
    } catch (_) {
      return null; // colonnes absentes (SQL 055 pas encore passé)
    }
  }

  /// Choix, compression et envoi. Retourne un message d'erreur, ou null.
  static Future<String?> deposer(ImageSource source) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return 'Tu dois être connecté'.tr;
    final choisie = await ImagePicker().pickVideo(
        source: source, maxDuration: const Duration(seconds: 15));
    if (choisie == null) return '';
    try {
      final info = await VideoCompress.getMediaInfo(choisie.path);
      if ((info.duration ?? 0) > 16000) {
        return 'Ta vidéo doit durer 15 secondes au maximum'.tr;
      }
      var fichier = File(choisie.path);
      final c = await VideoCompress.compressVideo(choisie.path,
          quality: VideoQuality.Res1280x720Quality, includeAudio: true);
      if (c?.file != null) fichier = c!.file!;
      final chemin = '$uid/video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await _sb.storage.from('profile-photos').upload(chemin, fichier,
          fileOptions: const FileOptions(contentType: 'video/mp4'));
      final url = _sb.storage.from('profile-photos').getPublicUrl(chemin);
      final ancienne = await de(uid);
      await _sb.from('profiles').update({'video_url': url}).eq('id', uid);
      await _supprimerFichier(ancienne?['video_url'] as String?);
      return null;
    } catch (e) {
      debugPrint('Vidéo de profil : $e');
      return 'Envoi impossible, vérifie ta connexion'.tr;
    } finally {
      VideoCompress.deleteAllCache().catchError((_) => null);
    }
  }

  static Future<void> supprimer() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    final v = await de(uid);
    await _sb.from('profiles').update({'video_url': null}).eq('id', uid);
    await _supprimerFichier(v?['video_url'] as String?);
  }

  static Future<void> _supprimerFichier(String? url) async {
    const marque = '/storage/v1/object/public/profile-photos/';
    final i = (url ?? '').indexOf(marque);
    if (i < 0) return;
    try {
      await _sb.storage
          .from('profile-photos')
          .remove([Uri.decodeFull(url!.substring(i + marque.length))]);
    } catch (_) {}
  }
}

/// Bloc « Ma vidéo » de l'écran Modifier mes infos
class BlocVideoProfil extends StatefulWidget {
  const BlocVideoProfil({super.key});

  @override
  State<BlocVideoProfil> createState() => _BlocVideoProfilState();
}

class _BlocVideoProfilState extends State<BlocVideoProfil> {
  Map<String, dynamic>? _video;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final v = await VideoProfilService.de(uid);
    if (mounted) setState(() => _video = v);
  }

  Future<void> _deposer() async {
    final source = await Get.bottomSheet<ImageSource>(
      SafeArea(
        child: Container(
          color: AppColors.surface,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: Icon(Icons.videocam_rounded, color: AppColors.textPrimary),
              title: Text('Filmer'.tr, style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Get.back(result: ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.video_library_rounded, color: AppColors.textPrimary),
              title: Text('Choisir dans la galerie'.tr,
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Get.back(result: ImageSource.gallery),
            ),
          ]),
        ),
      ),
    );
    if (source == null) return;
    setState(() => _envoi = true);
    final erreur = await VideoProfilService.deposer(source);
    if (!mounted) return;
    setState(() => _envoi = false);
    if (erreur != null && erreur.isNotEmpty) {
      Get.snackbar('🎬', erreur,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    } else if (erreur == null) {
      Get.snackbar('🎬', 'Vidéo envoyée : elle sera visible après vérification'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final statut = _video?['video_statut'] as String?;
    final texteStatut = switch (statut) {
      'validee' => '✅ Visible sur ton profil'.tr,
      'refusee' => '❌ Refusée : @motif'.trParams(
          {'motif': (_video?['video_motif'] ?? 'règles non respectées'.tr).toString()}),
      'en_attente' => '⏳ En cours de vérification'.tr,
      _ => 'Une vidéo de 15 s maximum. Elle est vérifiée par l\'équipe avant d\'être visible.'.tr,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        const Text('🎬', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(texteStatut,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textMuted, height: 1.35)),
        ),
        const SizedBox(width: 8),
        if (_envoi)
          SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent))
        else ...[
          if (_video != null)
            IconButton(
              tooltip: 'Supprimer'.tr,
              icon: Icon(Icons.delete_outline_rounded, color: AppColors.error),
              onPressed: () async {
                await VideoProfilService.supprimer();
                _charger();
              },
            ),
          TextButton(
            onPressed: _deposer,
            child: Text(_video == null ? 'Ajouter'.tr : 'Changer'.tr,
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ]),
    );
  }
}

/// Sur un profil : bouton « ▶ Voir sa vidéo » si elle est validée
class BoutonVideoProfil extends StatefulWidget {
  final String userId;
  final String nom;
  const BoutonVideoProfil({super.key, required this.userId, required this.nom});

  @override
  State<BoutonVideoProfil> createState() => _BoutonVideoProfilState();
}

class _BoutonVideoProfilState extends State<BoutonVideoProfil> {
  String? _url;

  @override
  void initState() {
    super.initState();
    VideoProfilService.de(widget.userId).then((v) {
      if (mounted && v?['video_statut'] == 'validee') {
        setState(() => _url = v!['video_url'] as String);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: () => Get.to(() => _LecteurVideoProfil(url: _url!),
            fullscreenDialog: true),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: AppColors.gradientPink,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.play_circle_fill_rounded, color: AppColors.surAccent),
            const SizedBox(width: 8),
            Text('Voir la vidéo de @nom'.trParams({'nom': widget.nom}),
                style: const TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

class _LecteurVideoProfil extends StatefulWidget {
  final String url;
  const _LecteurVideoProfil({required this.url});

  @override
  State<_LecteurVideoProfil> createState() => _LecteurVideoProfilState();
}

class _LecteurVideoProfilState extends State<_LecteurVideoProfil> {
  late final VideoPlayerController _v =
      VideoPlayerController.networkUrl(Uri.parse(widget.url));

  @override
  void initState() {
    super.initState();
    _v.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _v
        ..setLooping(true)
        ..play();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Center(
            child: _v.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _v.value.aspectRatio, child: VideoPlayer(_v))
                : const CircularProgressIndicator(color: AppColors.surMedia),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.surMedia),
              onPressed: () => Get.back(),
            ),
          ),
        ]),
      );
}
