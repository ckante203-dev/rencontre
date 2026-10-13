import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/widget/stickers_story.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

/// Story « à la une » : gardée sur le profil après les 24 h (table
/// stories_une, SQL 054). Le fichier est copié dans le bucket `stories`
/// (préfixe une_) pour ne pas être supprimé avec la story d'origine.
class StoryUne {
  final String id;
  final String userId;
  final String mediaUrl;
  final bool isVideo;
  final String? texte;
  final String? fond; // couleur hex des stories texte
  final String? legende;
  final List<StickerStory> stickers;

  const StoryUne({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.isVideo,
    this.texte,
    this.fond,
    this.legende,
    this.stickers = const [],
  });

  bool get estTexte => mediaUrl.isEmpty && (texte ?? '').isNotEmpty;

  factory StoryUne.depuis(Map<String, dynamic> r) => StoryUne(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        mediaUrl: (r['media_url'] as String?) ?? '',
        isVideo: r['is_video'] == true,
        texte: r['texte'] as String?,
        fond: r['fond'] as String?,
        legende: r['legende'] as String?,
        stickers: StickerStory.listeDepuis(r['stickers']),
      );
}

class StoriesUneService {
  StoriesUneService._();
  static SupabaseClient get _sb => Supabase.instance.client;
  static const max = 10;

  static Future<List<StoryUne>> de(String userId) async {
    try {
      final rows = await _sb
          .from('stories_une')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return [for (final r in rows as List) StoryUne.depuis(r)];
    } catch (_) {
      return const []; // table absente (SQL 054 pas encore passé)
    }
  }

  /// Ajoute ma story à la une. Retourne un message d'erreur, ou null.
  static Future<String?> ajouter(StoryModel s) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || s.userId != uid) return 'Action impossible, réessaie'.tr;
    try {
      var url = s.mediaUrl;
      const marque = '/storage/v1/object/public/stories/';
      final i = url.indexOf(marque);
      if (url.isNotEmpty && i >= 0) {
        final source = Uri.decodeFull(url.substring(i + marque.length));
        final ext = source.split('.').last;
        final dest =
            'stories/$uid/une_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _sb.storage.from('stories').copy(source, dest);
        url = _sb.storage.from('stories').getPublicUrl(dest);
      }
      await _sb.from('stories_une').insert({
        'user_id': uid,
        'media_url': url,
        'is_video': s.isVideo,
        'texte': s.isTextStory ? s.textContent : null,
        'fond': s.isTextStory ? s.bgColor : null,
        'legende': s.caption,
        'stickers': s.stickers.map((e) => e.toJson()).toList(),
      });
      return null;
    } on PostgrestException catch (e) {
      debugPrint('À la une : $e');
      return e.message.contains('stories_une_max')
          ? '10 stories à la une maximum'.tr
          : 'Action impossible, réessaie'.tr;
    } catch (e) {
      debugPrint('À la une : $e');
      return 'Action impossible, réessaie'.tr;
    }
  }

  static Future<void> retirer(StoryUne u) async {
    await _sb.from('stories_une').delete().eq('id', u.id);
    const marque = '/storage/v1/object/public/stories/';
    final i = u.mediaUrl.indexOf(marque);
    if (i >= 0) {
      try {
        await _sb.storage
            .from('stories')
            .remove([Uri.decodeFull(u.mediaUrl.substring(i + marque.length))]);
      } catch (_) {}
    }
  }
}

Color _couleur(String? hex) {
  final h = (hex ?? '').replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? const Color(0xFF7B2FFF) : Color(v);
}

/// Rangée de cercles « À la une » sur un profil
class RangeeStoriesUne extends StatefulWidget {
  final String userId;
  const RangeeStoriesUne({super.key, required this.userId});

  @override
  State<RangeeStoriesUne> createState() => _RangeeStoriesUneState();
}

class _RangeeStoriesUneState extends State<RangeeStoriesUne> {
  List<StoryUne> _liste = const [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final l = await StoriesUneService.de(widget.userId);
    if (mounted) setState(() => _liste = l);
  }

  @override
  Widget build(BuildContext context) {
    if (_liste.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('À LA UNE'.tr,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textMuted)),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _liste.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final u = _liste[i];
              return GestureDetector(
                onTap: () async {
                  final retiree = await Get.to<bool>(
                      () => _VueStoryUne(liste: _liste, depart: i),
                      fullscreenDialog: true);
                  if (retiree == true) _charger();
                },
                child: Container(
                  width: 68,
                  height: 68,
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.gradientPink,
                  ),
                  child: ClipOval(
                    child: u.estTexte
                        ? Container(
                            color: _couleur(u.fond),
                            alignment: Alignment.center,
                            child: const Text('Aa',
                                style: TextStyle(
                                    color: AppColors.surMedia,
                                    fontWeight: FontWeight.w800)),
                          )
                        : u.isVideo
                            ? Container(
                                color: Colors.black,
                                child: const Icon(Icons.play_arrow_rounded,
                                    color: AppColors.surMedia),
                              )
                            : CachedNetworkImage(
                                imageUrl: u.mediaUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 200,
                                errorWidget: (_, __, ___) =>
                                    Container(color: AppColors.surface2),
                              ),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Plein écran : on passe d'une story à la une à l'autre en touchant
class _VueStoryUne extends StatefulWidget {
  final List<StoryUne> liste;
  final int depart;
  const _VueStoryUne({required this.liste, required this.depart});

  @override
  State<_VueStoryUne> createState() => _VueStoryUneState();
}

class _VueStoryUneState extends State<_VueStoryUne> {
  late int _i = widget.depart;
  VideoPlayerController? _video;

  StoryUne get _u => widget.liste[_i];
  bool get _aMoi =>
      _u.userId == Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _preparer();
  }

  void _preparer() {
    _video?.dispose();
    _video = null;
    if (_u.isVideo && _u.mediaUrl.isNotEmpty) {
      final v = VideoPlayerController.networkUrl(Uri.parse(_u.mediaUrl));
      _video = v;
      v.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        v
          ..setLooping(true)
          ..play();
      }).catchError((_) {});
    }
  }

  void _suivant() {
    if (_i < widget.liste.length - 1) {
      setState(() => _i++);
      _preparer();
    } else {
      Get.back();
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = _u;
    final v = _video;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _suivant,
        child: Stack(fit: StackFit.expand, children: [
          if (u.estTexte)
            Container(
              color: _couleur(u.fond),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Text(u.texte!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.surMedia,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
            )
          else if (u.isVideo)
            Center(
              child: v != null && v.value.isInitialized
                  ? AspectRatio(
                      aspectRatio: v.value.aspectRatio, child: VideoPlayer(v))
                  : const CircularProgressIndicator(color: AppColors.surMedia),
            )
          else
            CachedNetworkImage(imageUrl: u.mediaUrl, fit: BoxFit.contain, memCacheWidth: 1080),
          CoucheStickers(u.stickers),
          if ((u.legende ?? '').isNotEmpty)
            Positioned(
              left: 24,
              right: 24,
              bottom: 80,
              child: Text(u.legende!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.surMedia,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 6)])),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            right: 8,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.surMedia),
                onPressed: () => Get.back(),
              ),
              const Spacer(),
              if (_aMoi)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.surMedia),
                  label: Text('Retirer de la une'.tr,
                      style: const TextStyle(color: AppColors.surMedia)),
                  onPressed: () async {
                    await StoriesUneService.retirer(u);
                    Get.back(result: true);
                  },
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
