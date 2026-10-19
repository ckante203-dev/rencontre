import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/album/album_service.dart';
import 'package:rencontre/features/album/ecran_album_prive.dart';

// ══════════════════════════════════════════════════════════════════
//  ALBUM PRIVÉ DANS UNE CONVERSATION (comme Grindr) : tout se fait ici —
//  ouvrir / fermer mon album à cette personne, ajouter ou supprimer mes
//  photos, voir l'album qu'elle m'a ouvert.
// ══════════════════════════════════════════════════════════════════

/// [partagerDansDiscussion] : partage l'album et poste la carte dans la
/// discussion (true = partagé, false = album vide, null = échec).
Future<void> ouvrirAlbumConversation({
  required String autreId,
  required String autreNom,
  required Future<bool?> Function({Duration? duree, bool vueUnique})
      partagerDansDiscussion,
}) {
  return Get.bottomSheet(
    _FeuilleAlbum(
        autreId: autreId,
        autreNom: autreNom,
        partagerDansDiscussion: partagerDansDiscussion),
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
  );
}

class _FeuilleAlbum extends StatefulWidget {
  final String autreId, autreNom;
  final Future<bool?> Function({Duration? duree, bool vueUnique})
      partagerDansDiscussion;
  const _FeuilleAlbum(
      {required this.autreId,
      required this.autreNom,
      required this.partagerDansDiscussion});
  @override
  State<_FeuilleAlbum> createState() => _FeuilleAlbumState();
}

class _FeuilleAlbumState extends State<_FeuilleAlbum> {
  List<PhotoAlbum> _photos = [];
  AccesAlbum? _acces; // mon album, vu par cette personne (null = fermé)
  bool _sonAlbum = false; // elle m'a ouvert le sien ?
  bool _chargement = true;
  bool _bascule = false;
  int _ajoutsEnCours = 0;

  String get _prenom => widget.autreNom.split(' ').first;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await Future.wait([
        AlbumService.mesPhotos(),
        AlbumService.monAccesPour(widget.autreId),
        AlbumService.aPartageAvecMoi(widget.autreId),
      ]);
      if (!mounted) return;
      setState(() {
        _photos = r[0] as List<PhotoAlbum>;
        _acces = r[1] as AccesAlbum?;
        _sonAlbum = r[2] as bool;
      });
    } catch (e) {
      debugPrint('Album (conversation) : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _info(String t) => Get.snackbar(t, '',
      messageText: const SizedBox.shrink(),
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 2));

  Future<void> _basculerPartage(bool ouvrir) async {
    if (_bascule) return;
    if (ouvrir && _photos.isEmpty) {
      _info("Ajoute d'abord des photos à ton album 👇".tr);
      return;
    }
    HapticFeedback.selectionClick();
    _ChoixLimite? choix;
    if (ouvrir) {
      choix = await _choisirLimite();
      if (choix == null || !mounted) return;
    }
    setState(() => _bascule = true);
    try {
      if (ouvrir) {
        final ok = await widget.partagerDansDiscussion(
            duree: choix!.duree, vueUnique: choix.vueUnique);
        if (ok == true) {
          final a = await AlbumService.monAccesPour(widget.autreId);
          if (mounted) setState(() => _acces = a);
        }
      } else {
        await AlbumService.retirer(widget.autreId);
        if (mounted) setState(() => _acces = null);
        _info('@nom ne voit plus ton album'.trParams({'nom': _prenom}));
      }
    } catch (_) {
      _info('Action impossible, réessaie'.tr);
    } finally {
      if (mounted) setState(() => _bascule = false);
    }
  }

  /// Pour combien de temps j'ouvre mon album ?
  Future<_ChoixLimite?> _choisirLimite() {
    Widget option(String emoji, String titre, String sous, _ChoixLimite c) =>
        ListTile(
          leading: Text(emoji, style: const TextStyle(fontSize: 24)),
          title: Text(titre,
              style: TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          subtitle: Text(sous,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          onTap: () => Get.back(result: c),
        );
    return Get.bottomSheet<_ChoixLimite>(
      SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Ouvrir mon album à @nom…'.trParams({'nom': _prenom}),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            option('👁', 'Vue unique'.tr,
                "Une seule ouverture, 2 minutes, puis l'album se referme".tr,
                const _ChoixLimite(vueUnique: true)),
            option('⏱', 'Pendant 1 heure'.tr, '', const _ChoixLimite(duree: Duration(hours: 1))),
            option('🌙', 'Pendant 24 heures'.tr, '',
                const _ChoixLimite(duree: Duration(hours: 24))),
            option('📅', 'Pendant 7 jours'.tr, '',
                const _ChoixLimite(duree: Duration(days: 7))),
            option('♾️', 'Sans limite'.tr, "Jusqu'à ce que tu le refermes".tr,
                const _ChoixLimite()),
          ]),
        ),
      ),
      isScrollControlled: true,
    );
  }

  /// État de mon album pour cette personne
  String _etat() {
    final a = _acces;
    if (a == null) {
      return 'Fermé · @nom ne voit pas tes photos'.trParams({'nom': _prenom});
    }
    if (a.expire) {
      return a.vueUnique ? 'Vue unique déjà regardée'.tr : 'Accès expiré'.tr;
    }
    final fin = a.expireLe;
    if (a.vueUnique) {
      return fin == null
          ? '👁 ${'Vue unique · pas encore ouverte'.tr}'
          : '👁 ${'Vue unique · en cours'.tr}';
    }
    final vues = a.vues == 0
        ? 'pas encore regardé'.tr
        : 'regardé @n fois'.trParams({'n': '${a.vues}'});
    if (fin == null) return '${'Ouvert'.tr} · $vues';
    final d = '${fin.day.toString().padLeft(2, '0')}/${fin.month.toString().padLeft(2, '0')} '
        '${fin.hour.toString().padLeft(2, '0')}:${fin.minute.toString().padLeft(2, '0')}';
    return '⏱ ${'Ouvert jusqu\'au @d'.trParams({'d': d})} · $vues';
  }

  Future<void> _ajouter() async {
    final reste = AlbumService.maxPhotos - _photos.length;
    if (reste <= 0) {
      _info('Ton album est plein (@maxPhotos photos)'
          .trParams({'maxPhotos': '${AlbumService.maxPhotos}'}));
      return;
    }
    final choix = await ImagePicker().pickMultiImage(
        maxWidth: 1440, maxHeight: 1440, imageQuality: 85, limit: reste);
    if (choix.isEmpty || !mounted) return;
    final aAjouter = choix.take(reste).toList();
    setState(() => _ajoutsEnCours = aAjouter.length);
    var echecs = 0;
    for (final f in aAjouter) {
      try {
        await AlbumService.ajouter(File(f.path));
      } catch (e) {
        echecs++;
        debugPrint('Album : ajout impossible : $e');
      }
      if (mounted) setState(() => _ajoutsEnCours--);
    }
    if (echecs > 0) _info("Impossible d'ajouter @n photo(s)".trParams({'n': '$echecs'}));
    final photos = await AlbumService.mesPhotos().catchError((_) => _photos);
    if (mounted) setState(() => _photos = photos);
  }

  Future<void> _supprimer(PhotoAlbum p) async {
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Supprimer cette photo ?'.tr,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Supprimer'.tr,
                style: const TextStyle(color: Color(0xFFFF3B30)))),
      ],
    ));
    if (ok != true) return;
    try {
      await AlbumService.supprimer(p);
      if (mounted) setState(() => _photos.removeWhere((x) => x.id == p.id));
    } catch (_) {
      _info('Impossible de supprimer la photo'.tr);
    }
  }

  Future<void> _voirSonAlbum() =>
      afficherAlbumDe(widget.autreId, widget.autreNom);

  @override
  Widget build(BuildContext context) {
    final ouvert = _acces != null && !_acces!.expire;
    return Container(
      constraints: BoxConstraints(maxHeight: Get.height * 0.88),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: _chargement
            ? SizedBox(
                height: 220,
                child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent)))
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('🔒 ${'Album privé'.tr}',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                      'Tes photos privées, visibles seulement par les personnes à qui tu ouvres ton album.'
                          .tr,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                          height: 1.4)),
                  const SizedBox(height: 16),

                  // ── Ouvrir / fermer mon album à cette personne ──
                  _carte(
                    actif: ouvert,
                    child: Row(children: [
                      Icon(
                          ouvert
                              ? Icons.lock_open_rounded
                              : Icons.lock_rounded,
                          color: ouvert ? AppColors.accent : AppColors.textMuted,
                          size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Ouvrir mon album à @nom'
                                      .trParams({'nom': _prenom}),
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text(_etat(),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textMuted)),
                            ]),
                      ),
                      _bascule
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.accent))
                          : Switch.adaptive(
                              value: ouvert,
                              activeTrackColor: AppColors.accent,
                              onChanged: _basculerPartage),
                    ]),
                  ),

                  // ── Son album, s'il me l'a ouvert ──
                  if (_sonAlbum) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _voirSonAlbum,
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientPink,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          const Icon(Icons.photo_library_rounded,
                              color: AppColors.surAccent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                                "@nom t'a ouvert son album".trParams({'nom': _prenom}),
                                style: const TextStyle(
                                    color: AppColors.surAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14.5)),
                          ),
                          const Icon(Icons.chevron_right_rounded,
                              color: AppColors.surAccent),
                        ]),
                      ),
                    ),
                  ],

                  // ── Mes photos : ajouter / supprimer ici ──
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: Text('Mes photos'.tr,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                    Text('${_photos.length}/${AlbumService.maxPhotos}',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textMuted)),
                  ]),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      if (_photos.length + _ajoutsEnCours <
                          AlbumService.maxPhotos)
                        _caseAjout(),
                      for (var i = 0; i < _ajoutsEnCours; i++)
                        Container(
                          decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(10)),
                          child: Center(
                              child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accent))),
                        ),
                      for (final p in _photos) _vignette(p),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                      "📵 Captures d'écran bloquées · tu peux fermer ton album à tout moment"
                          .tr,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
      ),
    );
  }

  Widget _carte({required bool actif, required Widget child}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: actif ? AppColors.accent : AppColors.border,
              width: actif ? 1.5 : 1),
        ),
        child: child,
      );

  Widget _caseAjout() => GestureDetector(
        onTap: _ajoutsEnCours > 0 ? null : _ajouter,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.6)),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.add_a_photo_rounded, color: AppColors.accent, size: 24),
            const SizedBox(height: 4),
            Text('Ajouter'.tr,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent)),
          ]),
        ),
      );

  Widget _vignette(PhotoAlbum p) => GestureDetector(
        onTap: () => ouvrirPhotosAlbum(_photos, p),
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: p.url,
              cacheKey: Uri.parse(p.url).path,
              fit: BoxFit.cover,
              memCacheWidth: 300,
              placeholder: (_, __) => Container(color: AppColors.surface2),
              errorWidget: (_, __, ___) =>
                  Container(color: AppColors.surface2),
            ),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: GestureDetector(
              onTap: () => _supprimer(p),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.voileMedia,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surMedia, width: 1.2),
                ),
                child: const Icon(Icons.close_rounded,
                    size: 14, color: AppColors.surMedia),
              ),
            ),
          ),
        ]),
      );
}

/// Limite choisie en ouvrant mon album
class _ChoixLimite {
  final Duration? duree;
  final bool vueUnique;
  const _ChoixLimite({this.duree, this.vueUnique = false});
}
