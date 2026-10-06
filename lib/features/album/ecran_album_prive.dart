import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/album/album_service.dart';
import 'package:rencontre/features/home/widget/story_report_sheet.dart';

void _snack(String texte) => Get.snackbar(texte, '',
    messageText: const SizedBox.shrink(),
    snackPosition: SnackPosition.TOP,
    backgroundColor: AppColors.surface,
    colorText: AppColors.textPrimary,
    duration: const Duration(seconds: 2));

// ══════════════════════════════════════════════════════════════════
//  MON ALBUM PRIVÉ : ajouter / supprimer, voir qui y a accès
// ══════════════════════════════════════════════════════════════════

class EcranMonAlbum extends StatefulWidget {
  const EcranMonAlbum({super.key});

  @override
  State<EcranMonAlbum> createState() => _EcranMonAlbumState();
}

class _EcranMonAlbumState extends State<EcranMonAlbum> {
  List<PhotoAlbum> _photos = [];
  List<PersonneAcces> _acces = [];
  bool _chargement = true;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await Future.wait(
          [AlbumService.mesPhotos(), AlbumService.personnesAvecAcces()]);
      if (!mounted) return;
      setState(() {
        _photos = r[0] as List<PhotoAlbum>;
        _acces = r[1] as List<PersonneAcces>;
      });
    } catch (e) {
      debugPrint('Album : chargement impossible : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  Future<void> _ajouter() async {
    if (_photos.length >= AlbumService.maxPhotos) {
      _snack('Ton album est plein (${AlbumService.maxPhotos} photos)');
      return;
    }
    final choix = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1440,
        maxHeight: 1440,
        imageQuality: 85);
    if (choix == null) return;
    setState(() => _envoi = true);
    try {
      await AlbumService.ajouter(File(choix.path));
      await _charger();
    } catch (e) {
      debugPrint('Album : ajout impossible : $e');
      _snack("Impossible d'ajouter la photo");
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _supprimer(PhotoAlbum photo) async {
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Supprimer cette photo ?',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler', style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Supprimer',
                style: TextStyle(color: Color(0xFFFF3B30)))),
      ],
    ));
    if (ok != true) return;
    try {
      await AlbumService.supprimer(photo);
      setState(() => _photos.removeWhere((p) => p.id == photo.id));
    } catch (_) {
      _snack('Impossible de supprimer la photo');
    }
  }

  Future<void> _retirer(PersonneAcces p) async {
    try {
      await AlbumService.retirer(p.id);
      setState(() => _acces.removeWhere((a) => a.id == p.id));
      _snack('${p.nom} ne voit plus ton album');
    } catch (_) {
      _snack("Impossible de retirer l'accès");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('🔒 Mon album privé',
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.textPrimary)),
      ),
      body: _chargement
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                Text(
                  'Personne ne voit ces photos. Tu choisis à qui tu les '
                  'montres, depuis une conversation (menu ⋮ → Partager mon '
                  'album privé). Les captures d\'écran sont bloquées.',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: [
                    for (final p in _photos)
                      GestureDetector(
                        onTap: () => _ouvrir(context, _photos, p),
                        onLongPress: () => _supprimer(p),
                        child: _Vignette(url: p.url),
                      ),
                    if (_photos.length < AlbumService.maxPhotos)
                      GestureDetector(
                        onTap: _envoi ? null : _ajouter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Center(
                            child: _envoi
                                ? SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.accent))
                                : Icon(Icons.add_rounded,
                                    color: AppColors.textPrimary, size: 30),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    '${_photos.length}/${AlbumService.maxPhotos} photos · '
                    'appui long pour supprimer',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 24),
                Text('Qui peut voir mon album',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                if (_acces.isEmpty)
                  Text('Personne pour le moment',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted))
                else
                  for (final p in _acces)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.surface2,
                        backgroundImage: (p.photoUrl ?? '').isNotEmpty
                            ? CachedNetworkImageProvider(p.photoUrl!)
                            : null,
                        child: (p.photoUrl ?? '').isEmpty
                            ? Icon(Icons.person_rounded,
                                color: AppColors.textPrimary)
                            : null,
                      ),
                      title: Text(p.nom,
                          style: TextStyle(color: AppColors.textPrimary)),
                      trailing: TextButton(
                        onPressed: () => _retirer(p),
                        child: const Text('Retirer',
                            style: TextStyle(color: Color(0xFFFF3B30))),
                      ),
                    ),
              ],
            ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
//  ALBUM D'UNE AUTRE PERSONNE (si elle me l'a partagé)
// ══════════════════════════════════════════════════════════════════

class EcranAlbumDe extends StatelessWidget {
  final String nom;
  final List<PhotoAlbum> photos;
  const EcranAlbumDe({super.key, required this.nom, required this.photos});

  /// Signalement de l'album (contenu non modéré : important pour le Play Store).
  Future<void> _signaler() async {
    final ownerId = photos.isEmpty ? null : photos.first.chemin.split('/').first;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (ownerId == null || uid == null) return;
    final raison =
        await choisirMotifSignalement('Pourquoi signaler cet album ?');
    if (raison == null) return;
    try {
      await Supabase.instance.client.from('reports').insert({
        'reporter_id': uid,
        'reported_id': ownerId,
        'reason': 'Album privé : $raison',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _snack("Signalement envoyé. Merci, notre équipe va l'examiner.");
    } catch (_) {
      _snack("Impossible d'envoyer le signalement");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('🔓 Album de $nom',
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Signaler',
            icon: const Icon(Icons.flag_outlined, color: Color(0xFFFF9500)),
            onPressed: _signaler,
          ),
        ],
      ),
      body: GridView.count(
        padding: const EdgeInsets.all(12),
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (final p in photos)
            GestureDetector(
              onTap: () => _ouvrir(context, photos, p),
              child: _Vignette(url: p.url),
            ),
        ],
      ),
    );
  }
}

/// Bouton sur la fiche d'un profil : visible seulement si cette personne
/// m'a partagé son album (et qu'il contient des photos).
class BoutonAlbumPrive extends StatefulWidget {
  final String ownerId;
  final String nom;
  const BoutonAlbumPrive({super.key, required this.ownerId, required this.nom});

  @override
  State<BoutonAlbumPrive> createState() => _BoutonAlbumPriveState();
}

class _BoutonAlbumPriveState extends State<BoutonAlbumPrive> {
  // ✅ Chargé une seule fois : avant, chaque reconstruction de la fiche
  // (défilement des photos…) relançait la requête et les liens signés.
  Future<List<PhotoAlbum>>? _photos;

  bool get _maFiche =>
      widget.ownerId == Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    if (!_maFiche) {
      _photos = AlbumService.photosDe(widget.ownerId)
          .catchError((_) => <PhotoAlbum>[]);
    }
  }

  @override
  void didUpdateWidget(covariant BoutonAlbumPrive old) {
    super.didUpdateWidget(old);
    // Carrousel de profils : la fiche affiche maintenant quelqu'un d'autre
    if (old.ownerId != widget.ownerId && !_maFiche) {
      _photos = AlbumService.photosDe(widget.ownerId)
          .catchError((_) => <PhotoAlbum>[]);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ma propre fiche : rien à « ouvrir »
    if (_maFiche || _photos == null) return const SizedBox.shrink();
    final nom = widget.nom;
    return FutureBuilder<List<PhotoAlbum>>(
      future: _photos,
      builder: (_, snap) {
        final photos = snap.data ?? const <PhotoAlbum>[];
        if (photos.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GestureDetector(
            onTap: () =>
                Get.to(() => EcranAlbumDe(nom: nom, photos: photos)),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Icon(Icons.lock_open_rounded,
                    color: AppColors.surAccent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      '$nom t\'a ouvert son album privé · '
                      '${photos.length} photo${photos.length > 1 ? 's' : ''}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surAccent)),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.surAccent),
              ]),
            ),
          ),
        );
      },
    );
  }
}

class _Vignette extends StatelessWidget {
  final String url;
  const _Vignette({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        // Le lien change à chaque ouverture : on met en cache par fichier.
        cacheKey: Uri.parse(url).path,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppColors.surface2),
        errorWidget: (_, __, ___) => Container(
            color: AppColors.surface2,
            child: Icon(Icons.broken_image_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.38))),
      ),
    );
  }
}

void _ouvrir(BuildContext context, List<PhotoAlbum> photos, PhotoAlbum p) {
  Get.to(() => _PleinEcran(photos: photos, debut: photos.indexOf(p)));
}

class _PleinEcran extends StatelessWidget {
  final List<PhotoAlbum> photos;
  final int debut;
  const _PleinEcran({required this.photos, required this.debut});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: AppColors.surMedia)),
      body: PageView.builder(
        controller: PageController(initialPage: debut < 0 ? 0 : debut),
        itemCount: photos.length,
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: CachedNetworkImage(
              imageUrl: photos[i].url,
              cacheKey: Uri.parse(photos[i].url).path,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: AppColors.surMedia)),
            ),
          ),
        ),
      ),
    );
  }
}
