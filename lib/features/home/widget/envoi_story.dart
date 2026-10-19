import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/utils/compression_video.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/likes/like_controller.dart';

// ─── ÉCRAN « ENVOYER À… » APRÈS LA PHOTO (comme Snapchat) ─────────
// Un seul écran pour publier sa story ET envoyer des snaps à plusieurs
// personnes d'un coup : « Publier sur… » (Tout le monde / Amis / Proches,
// 🔒 Mystère, durée), 💘 Mes matchs, 💬 Conversations, recherche.

class ChoixEnvoi {
  final String? audience; // 'public' | 'amis' | 'friends' | null = pas de story
  final bool mystere;
  final double dureeHeures;
  final List<ConversationModel> destinataires;
  const ChoixEnvoi(this.audience, this.mystere, this.dureeHeures, this.destinataires);
}

/// Maximum de destinataires d'un coup (une copie du fichier par personne :
/// un snap vu est effacé du serveur, il ne doit pas effacer celui des autres).
const maxDestinataires = 10;

Future<ChoixEnvoi?> ouvrirEnvoiStory({
  required String audience,
  required bool mystere,
  required double dureeHeures,
}) async =>
    await Get.to<ChoixEnvoi>(
      () => _EcranEnvoi(
          audience: audience, mystere: mystere, dureeHeures: dureeHeures),
      transition: Transition.downToUp,
      fullscreenDialog: true,
    );

class _EcranEnvoi extends StatefulWidget {
  final String audience;
  final bool mystere;
  final double dureeHeures;
  const _EcranEnvoi(
      {required this.audience, required this.mystere, required this.dureeHeures});

  @override
  State<_EcranEnvoi> createState() => _EcranEnvoiState();
}

class _EcranEnvoiState extends State<_EcranEnvoi> {
  late String? _audience = widget.audience;
  late bool _mystere = widget.mystere;
  late double _duree = widget.dureeHeures;
  final Set<String> _choisis = {};
  String _q = '';

  // 1 h → 7 jours (aucune limite côté serveur)
  static const _durees = [1.0, 6.0, 24.0, 48.0, 72.0, 168.0];

  List<ConversationModel> get _conversations =>
      Get.isRegistered<ChatListController>()
          ? [...Get.find<ChatListController>().conversations]
          : const [];

  bool _estMatch(ConversationModel c) =>
      Get.isRegistered<LikeController>() &&
      Get.find<LikeController>().hasMatch(c.userId);

  String _sansAccent(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[éèêë]'), 'e')
      .replaceAll(RegExp('[àâä]'), 'a')
      .replaceAll(RegExp('[îï]'), 'i')
      .replaceAll(RegExp('[ôö]'), 'o')
      .replaceAll(RegExp('[ùûü]'), 'u');

  void _basculer(ConversationModel c) {
    setState(() {
      if (_choisis.remove(c.id)) return;
      if (_choisis.length >= maxDestinataires) {
        Get.snackbar('✈️', '@n personnes maximum par envoi'.trParams({'n': '$maxDestinataires'}),
            snackPosition: SnackPosition.TOP,
            backgroundColor: const Color(0xFF1C1C1E),
            colorText: Colors.white);
        return;
      }
      _choisis.add(c.id);
    });
    HapticFeedback.selectionClick();
  }

  String _dureeTexte(double h) => h < 24
      ? '${h.round()} h'
      : h == 24
          ? '24 h'
          : '@n j'.trParams({'n': '${(h / 24).round()}'});

  String get _resume {
    final n = _choisis.length;
    final story = _audience != null;
    if (story && n > 0) {
      return 'Ma story + @n snap@s'.trParams({'n': '$n', 's': n > 1 ? 's' : ''});
    }
    if (story) return 'Publier ma story'.tr;
    if (n > 0) return '@n snap@s'.trParams({'n': '$n', 's': n > 1 ? 's' : ''});
    return 'Choisis où envoyer'.tr;
  }

  // ─── Lignes ───
  Widget _titre(String t, {Widget? action}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
        child: Row(children: [
          Expanded(
            child: Text(t,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ),
          if (action != null) action,
        ]),
      );

  Widget _rond(bool actif) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: actif
              ? const LinearGradient(
                  colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)])
              : null,
          border: actif ? null : Border.all(color: Colors.white38, width: 2),
        ),
        child: actif
            ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
            : null,
      );

  Widget _ligne({
    required Widget gauche,
    required String titre,
    String? sous,
    required bool actif,
    required VoidCallback onTap,
    Widget? droite,
  }) =>
      InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            gauche,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(titre,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    if (sous != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(sous,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 13)),
                      ),
                  ]),
            ),
            droite ?? _rond(actif),
          ]),
        ),
      );

  Widget _icone(String emoji, Color fond) => Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fond, shape: BoxShape.circle),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      );

  Widget _avatar(ConversationModel c) => CircleAvatar(
        radius: 23,
        backgroundColor: Colors.white12,
        backgroundImage: (c.userPhotoUrl ?? '').isNotEmpty
            ? CachedNetworkImageProvider(c.userPhotoUrl!, maxWidth: 200)
            : null,
        child: (c.userPhotoUrl ?? '').isEmpty
            ? Text(c.userName.isEmpty ? '?' : c.userName[0].toUpperCase(),
                style: const TextStyle(color: Colors.white))
            : null,
      );

  Widget _ligneAudience(String id, String emoji, Color fond, String titre, String sous) =>
      _ligne(
        gauche: _icone(emoji, fond),
        titre: titre,
        sous: sous,
        actif: _audience == id,
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _audience = _audience == id ? null : id);
        },
      );

  @override
  Widget build(BuildContext context) {
    final q = _sansAccent(_q.trim());
    final toutes = _conversations
        .where((c) => q.isEmpty || _sansAccent(c.userName).contains(q))
        .toList();
    final matchs = toutes.where(_estMatch).toList();
    final autres = toutes.where((c) => !_estMatch(c)).toList();
    final peutEnvoyer = _audience != null || _choisis.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E12),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white, size: 30),
          onPressed: () => Get.back(),
        ),
        title: Text('Envoyer à…'.tr,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: Column(children: [
        // Recherche
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: 'Rechercher une personne'.tr,
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1C1C22),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView(children: [
            if (q.isEmpty) ...[
              _titre('Publier sur…'.tr),
              _ligneAudience('public', '🌍', const Color(0xFF2E63FF),
                  'Ma story · Tout le monde'.tr, 'Visible sur Découvrir'.tr),
              _ligneAudience('amis', '👥', const Color(0xFF30A46C),
                  'Ma story · Amis'.tr, 'Seulement tes amis'.tr),
              _ligneAudience('friends', '⭐', const Color(0xFFFF9F0A),
                  'Ma story · Proches'.tr, 'Ta liste Amis proches'.tr),
              if (_audience != null) ...[
                _ligne(
                  gauche: _icone('🔒', const Color(0xFF7B2FFF)),
                  titre: 'Story mystère'.tr,
                  sous: 'Floutée tant qu\'on ne t\'a pas liké'.tr,
                  actif: _mystere,
                  onTap: () => setState(() => _mystere = !_mystere),
                  droite: Switch(
                    value: _mystere,
                    activeThumbColor: Colors.white,
                    activeTrackColor: const Color(0xFFFF3CAC),
                    onChanged: (v) => setState(() => _mystere = v),
                  ),
                ),
                // ⏱ Durée de la story : choix direct (avant : une ligne à
                // toucher plusieurs fois, limitée à 24 h)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: Text('⏱ ${'Visible pendant'.tr}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ),
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final d in _durees)
                        GestureDetector(
                          onTap: () => setState(() => _duree = d),
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: _duree == d
                                  ? const LinearGradient(colors: [
                                      Color(0xFFFF3CAC),
                                      Color(0xFF7B2FFF)
                                    ])
                                  : null,
                              color: _duree == d ? null : Colors.white10,
                              borderRadius: BorderRadius.circular(19),
                            ),
                            child: Text(_dureeTexte(d),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: _duree == d
                                        ? FontWeight.w900
                                        : FontWeight.w600)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            if (matchs.isNotEmpty) ...[
              _titre('💘 ${'Mes matchs'.tr}',
                  action: TextButton(
                    onPressed: () => setState(() {
                      final tous = matchs.every((c) => _choisis.contains(c.id));
                      if (tous) {
                        _choisis.removeAll(matchs.map((c) => c.id));
                      } else {
                        for (final c in matchs) {
                          if (_choisis.length >= maxDestinataires) break;
                          _choisis.add(c.id);
                        }
                      }
                    }),
                    child: Text('Tout sélectionner'.tr,
                        style: const TextStyle(color: Color(0xFFFF3CAC))),
                  )),
              for (final c in matchs)
                _ligne(
                    gauche: _avatar(c),
                    titre: c.userName,
                    actif: _choisis.contains(c.id),
                    onTap: () => _basculer(c)),
            ],
            if (autres.isNotEmpty) ...[
              _titre('💬 ${'Conversations'.tr}'),
              for (final c in autres)
                _ligne(
                    gauche: _avatar(c),
                    titre: c.userName,
                    actif: _choisis.contains(c.id),
                    onTap: () => _basculer(c)),
            ],
            if (toutes.isEmpty && q.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Personne trouvé'.tr,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54)),
              ),
            const SizedBox(height: 100),
          ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: GestureDetector(
            onTap: !peutEnvoyer
                ? null
                : () {
                    final convs = _conversations
                        .where((c) => _choisis.contains(c.id))
                        .toList();
                    Get.back(
                        result: ChoixEnvoi(_audience, _mystere, _duree, convs));
                  },
            child: AnimatedOpacity(
              opacity: peutEnvoyer ? 1 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: Container(
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
                  borderRadius: BorderRadius.circular(29),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_resume,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(width: 10),
                  const Icon(Icons.send_rounded, color: Colors.white),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Envoie la photo / vidéo en snap éphémère à chaque destinataire (une copie
/// du fichier par personne). Renvoie le nombre de snaps envoyés.
Future<int> envoyerSnaps({
  required String chemin,
  required bool video,
  required List<ConversationModel> destinataires,
}) async {
  final sb = Supabase.instance.client;
  final uid = sb.auth.currentUser?.id;
  if (uid == null || destinataires.isEmpty) return 0;
  var fichier = File(chemin);
  if (video) {
    try {
      final info = await infosVideo(chemin);
      if ((info?.filesize ?? 0) > 6 * 1024 * 1024) {
        final c = await compresserVideo(chemin);
        if (c != null) fichier = c;
      }
    } catch (_) {}
  }
  final store = sb.storage.from('snaps');
  final contenu = video ? '🎬 Vidéo éphémère' : '📸 Photo éphémère';
  var envoyes = 0;
  for (final c in destinataires) {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final cheminMedia =
          'snaps/$uid/${video ? 'video' : 'photo'}_${ts}_$envoyes.${video ? 'mp4' : 'jpg'}';
      await store.upload(cheminMedia, fichier,
          fileOptions: FileOptions(
              upsert: true, contentType: video ? 'video/mp4' : 'image/jpeg'));
      final now = DateTime.now().toUtc().toIso8601String();
      await sb.from('messages').insert({
        'conversation_id': c.id,
        'sender_id': uid,
        'type': 'snap',
        'content': contenu,
        'media_url': store.getPublicUrl(cheminMedia),
        'status': 'sent',
        'created_at': now,
      });
      await sb.from('conversations').update({'updated_at': now}).eq('id', c.id);
      envoyes++;
    } catch (e) {
      debugPrint('Snap non envoyé à ${c.userName} : $e');
    }
  }
  if (video) {
    try {
      await viderCacheVideo();
    } catch (_) {}
  }
  return envoyes;
}
