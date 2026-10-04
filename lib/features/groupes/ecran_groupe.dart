import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/view/sticker_sheet.dart';
import 'package:rencontre/features/groupes/groupe_model.dart';
import 'package:rencontre/features/groupes/groupes_controller.dart';
import 'package:rencontre/features/groupes/infos_groupe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Discussion de groupe : texte, photo, GIF / sticker. Messages en temps
/// réel, gardés 7 jours.
class EcranGroupe extends StatefulWidget {
  final GroupeResume groupe;
  const EcranGroupe({super.key, required this.groupe});

  @override
  State<EcranGroupe> createState() => _EcranGroupeState();
}

class _EcranGroupeState extends State<EcranGroupe> {
  final _saisie = TextEditingController();
  final _defilement = ScrollController();
  final List<MessageGroupe> _messages = []; // du plus récent au plus ancien
  final Map<String, MembreGroupe> _membres = {};
  final Map<String, String> _urlsPhotos = {}; // chemin → URL signée
  late GroupeResume _groupe = widget.groupe;
  RealtimeChannel? _canal;
  bool _chargement = true;
  bool _envoi = false;

  String get _moi => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    GroupesController.groupeOuvert = _groupe.id;
    _charger();
    _ecouter();
    _saisie.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (GroupesController.groupeOuvert == _groupe.id) {
      GroupesController.groupeOuvert = null;
    }
    final c = _canal;
    if (c != null) supabase.removeChannel(c).catchError((_) => '');
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    await Future.wait([_chargerMembres(), _chargerMessages()]);
    _marquerLu();
  }

  Future<void> _chargerMembres() async {
    try {
      final rows = await supabase
          .from('groupe_membres')
          .select('user_id, role, profiles(name, photo_url)')
          .eq('groupe_id', _groupe.id);
      _membres
        ..clear()
        ..addAll({
          for (final r in rows as List)
            r['user_id'] as String: MembreGroupe(
              id: r['user_id'] as String,
              nom: (r['profiles']?['name'] as String?) ?? 'Utilisateur',
              photoUrl: r['profiles']?['photo_url'] as String?,
              admin: r['role'] == 'admin',
            ),
        });
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('membres du groupe : $e');
    }
  }

  Future<void> _chargerMessages() async {
    try {
      final rows = await supabase
          .from('groupe_messages')
          .select()
          .eq('groupe_id', _groupe.id)
          .order('created_at', ascending: false)
          .limit(150);
      final liste = [
        for (final r in rows as List) MessageGroupe.fromJson(r),
      ];
      await _signerPhotos(liste);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(liste);
        _chargement = false;
      });
    } catch (e) {
      debugPrint('messages du groupe : $e');
      if (mounted) setState(() => _chargement = false);
    }
  }

  // Photos dans un bucket privé : URL signée (1 h) pour les afficher
  Future<void> _signerPhotos(List<MessageGroupe> liste) async {
    final chemins = liste
        .where((m) => m.mediaPath != null && !_urlsPhotos.containsKey(m.mediaPath))
        .map((m) => m.mediaPath!)
        .toList();
    if (chemins.isEmpty) return;
    try {
      final signees = await supabase.storage
          .from('groupes')
          .createSignedUrls(chemins, 3600);
      for (final s in signees) {
        _urlsPhotos[s.path] = s.signedUrl;
      }
    } catch (e) {
      debugPrint('photos du groupe : $e');
    }
  }

  void _ecouter() {
    _canal = supabase
        .channel('groupe:${_groupe.id}:${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'groupe_messages',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'groupe_id',
              value: _groupe.id),
          callback: (p) async {
            final m = MessageGroupe.fromJson(p.newRecord);
            if (_messages.any((x) => x.id == m.id)) return;
            await _signerPhotos([m]);
            if (m.senderId != null && !_membres.containsKey(m.senderId)) {
              await _chargerMembres(); // nouveau membre
            }
            if (!mounted) return;
            setState(() => _messages.insert(0, m));
            _marquerLu();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'groupe_messages',
          callback: (p) {
            final id = p.oldRecord['id'];
            if (id == null || !mounted) return;
            setState(() => _messages.removeWhere((m) => m.id == id));
          },
        )
        .subscribe();
  }

  Future<void> _marquerLu() async {
    if (Get.isRegistered<GroupesController>()) {
      GroupesController.to.marquerLu(_groupe.id);
    }
    try {
      await supabase
          .from('groupe_membres')
          .update({'dernier_lu': DateTime.now().toUtc().toIso8601String()})
          .eq('groupe_id', _groupe.id)
          .eq('user_id', _moi);
    } catch (_) {}
  }

  Future<void> _inserer(Map<String, dynamic> ligne) async {
    final row = await supabase
        .from('groupe_messages')
        .insert({'groupe_id': _groupe.id, 'sender_id': _moi, ...ligne})
        .select()
        .single();
    final m = MessageGroupe.fromJson(row);
    await _signerPhotos([m]);
    if (!mounted || _messages.any((x) => x.id == m.id)) return;
    setState(() => _messages.insert(0, m));
  }

  Future<void> _envoyerTexte() async {
    final texte = _saisie.text.trim();
    if (texte.isEmpty || _envoi) return;
    setState(() => _envoi = true);
    _saisie.clear();
    try {
      await _inserer({'type': 'texte', 'contenu': texte});
    } catch (e) {
      debugPrint('envoi groupe : $e');
      _saisie.text = texte;
      _erreur('Message non envoyé, vérifie ta connexion');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _envoyerPhoto() async {
    final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80);
    if (f == null) return;
    setState(() => _envoi = true);
    try {
      final nom = '${DateTime.now().millisecondsSinceEpoch}'
          '_${Random().nextInt(1 << 32).toRadixString(16)}.jpg';
      final chemin = '${_groupe.id}/$nom';
      await supabase.storage.from('groupes').upload(chemin, File(f.path),
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await _inserer({'type': 'image', 'media_path': chemin});
    } catch (e) {
      debugPrint('photo groupe : $e');
      _erreur('Photo non envoyée, vérifie ta connexion');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  Future<void> _envoyerGif() async {
    final c = await choisirSticker(context);
    if (c == null || c.url.isEmpty) return;
    try {
      await _inserer({'type': 'giphy', 'contenu': c.url});
    } catch (e) {
      debugPrint('gif groupe : $e');
      _erreur('GIF non envoyé, vérifie ta connexion');
    }
  }

  void _erreur(String msg) => Get.snackbar('Oups', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white);

  void _options(MessageGroupe m) {
    final moi = m.senderId == _moi;
    final admin = _membres[_moi]?.admin ?? false;
    Get.bottomSheet(
      SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (m.type == 'texte')
              ListTile(
                leading: Icon(Icons.copy_rounded, color: AppColors.textPrimary),
                title: Text('Copier',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: m.contenu ?? ''));
                  Get.back();
                },
              ),
            if (m.senderId != null && !moi)
              ListTile(
                leading: Icon(Icons.person_rounded, color: AppColors.textPrimary),
                title: Text('Voir le profil',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () {
                  Get.back();
                  ouvrirProfilParId(m.senderId!);
                },
              ),
            if (moi || admin)
              ListTile(
                leading: const Icon(Icons.delete_rounded, color: Colors.red),
                title: const Text('Supprimer pour tout le monde',
                    style: TextStyle(color: Colors.red)),
                onTap: () async {
                  Get.back();
                  try {
                    await supabase
                        .from('groupe_messages')
                        .delete()
                        .eq('id', m.id);
                    if (mounted) {
                      setState(() => _messages.removeWhere((x) => x.id == m.id));
                    }
                  } catch (_) {
                    _erreur('Suppression impossible');
                  }
                },
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _ouvrirInfos() async {
    final maj = await Get.to<GroupeResume?>(
        () => InfosGroupe(groupe: _groupe, membres: _membres.values.toList()));
    if (maj == null) {
      // Revenu sans changement : on rafraîchit les membres
      _chargerMembres();
      return;
    }
    setState(() => _groupe = maj);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _ouvrirInfos,
          child: Row(children: [
            AvatarGroupe(groupe: _groupe, rayon: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_groupe.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(
                        '${_membres.isEmpty ? _groupe.nbMembres : _membres.length} membres'
                        '${_groupe.estEvenement ? ' · événement' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textMuted)),
                  ]),
            ),
          ]),
        ),
        actions: [
          IconButton(
            onPressed: _ouvrirInfos,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _chargement
              ? Center(
                  child: CircularProgressIndicator(color: AppColors.accent))
              : _messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('Dis bonjour au groupe 👋',
                            style: TextStyle(color: AppColors.textMuted)),
                      ),
                    )
                  : ListView.builder(
                      controller: _defilement,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                      itemCount: _messages.length,
                      itemBuilder: (_, i) => _bulle(i),
                    ),
        ),
        _barreSaisie(),
      ]),
    );
  }

  Widget _bulle(int i) {
    final m = _messages[i];
    final suivant = i > 0 ? _messages[i - 1] : null; // plus récent
    final precedent = i + 1 < _messages.length ? _messages[i + 1] : null;
    final nouveauJour = precedent == null ||
        precedent.createdAt.day != m.createdAt.day ||
        precedent.createdAt.month != m.createdAt.month;

    final contenu = m.estSysteme
        ? Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(m.contenu ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          )
        : _bulleMessage(m,
            debutSerie: precedent == null ||
                precedent.senderId != m.senderId ||
                precedent.estSysteme ||
                nouveauJour,
            finSerie: suivant == null ||
                suivant.senderId != m.senderId ||
                suivant.estSysteme);

    if (!nouveauJour) return contenu;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(_jour(m.createdAt),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      ),
      contenu,
    ]);
  }

  static String _jour(DateTime d) {
    final n = DateTime.now();
    final aujourdhui = DateTime(n.year, n.month, n.day);
    final ecart = aujourdhui.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (ecart == 0) return 'Aujourd\'hui';
    if (ecart == 1) return 'Hier';
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    if (ecart < 7) return jours[d.weekday - 1];
    return '${d.day}/${d.month}/${d.year}';
  }

  Widget _bulleMessage(MessageGroupe m,
      {required bool debutSerie, required bool finSerie}) {
    final moi = m.senderId == _moi;
    final auteur = _membres[m.senderId];
    final heure =
        '${m.createdAt.hour.toString().padLeft(2, '0')}:${m.createdAt.minute.toString().padLeft(2, '0')}';

    Widget corps;
    switch (m.type) {
      case 'image':
        final url = _urlsPhotos[m.mediaPath];
        corps = ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: url == null
              ? Container(
                  width: 200, height: 200, color: AppColors.surface2)
              : GestureDetector(
                  onTap: () => _voirPhoto(url),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    width: 220,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                        width: 220, height: 220, color: AppColors.surface2),
                  ),
                ),
        );
      case 'giphy':
        corps = CachedNetworkImage(
          imageUrl: m.contenu ?? '',
          width: 150,
          fit: BoxFit.contain,
          errorWidget: (_, __, ___) => const SizedBox(),
        );
      default:
        corps = Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            gradient: moi ? AppColors.gradientPink : null,
            color: moi ? null : AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!moi && debutSerie)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(auteur?.nom ?? 'Ancien membre',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent)),
                  ),
                Text(m.contenu ?? '',
                    style: TextStyle(
                        fontSize: 15,
                        color: moi ? Colors.white : AppColors.textPrimary)),
              ]),
        );
    }

    return GestureDetector(
      onLongPress: () => _options(m),
      child: Padding(
        padding: EdgeInsets.only(top: debutSerie ? 8 : 2),
        child: Row(
          mainAxisAlignment:
              moi ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!moi)
              SizedBox(
                width: 34,
                child: finSerie
                    ? GestureDetector(
                        onTap: () => m.senderId == null
                            ? null
                            : ouvrirProfilParId(m.senderId!),
                        child: _avatar(auteur),
                      )
                    : null,
              ),
            if (!moi) const SizedBox(width: 6),
            Flexible(
              child: Column(
                crossAxisAlignment:
                    moi ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!moi && debutSerie && m.type != 'texte')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, left: 4),
                      child: Text(auteur?.nom ?? 'Ancien membre',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent)),
                    ),
                  corps,
                  if (finSerie)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                      child: Text(heure,
                          style: TextStyle(
                              fontSize: 10, color: AppColors.textMuted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(MembreGroupe? m) => CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.surface2,
        backgroundImage: (m?.photoUrl ?? '').isNotEmpty
            ? CachedNetworkImageProvider(m!.photoUrl!)
            : null,
        onBackgroundImageError:
            (m?.photoUrl ?? '').isNotEmpty ? (_, __) {} : null,
        child: (m?.photoUrl ?? '').isEmpty
            ? Text((m?.nom ?? '?').isEmpty ? '?' : m!.nom[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700))
            : null,
      );

  void _voirPhoto(String url) => Get.to(() => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ));

  Widget _barreSaisie() {
    final peutEnvoyer = _saisie.text.trim().isNotEmpty && !_envoi;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(children: [
          IconButton(
            onPressed: _envoi ? null : _envoyerPhoto,
            icon: Icon(Icons.photo_rounded, color: AppColors.textMuted),
          ),
          IconButton(
            onPressed: _envoyerGif,
            icon: Icon(Icons.gif_box_rounded, color: AppColors.textMuted),
          ),
          Expanded(
            child: TextField(
              controller: _saisie,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Message au groupe…',
                hintStyle: TextStyle(color: AppColors.textMuted),
                counterText: '',
                filled: true,
                fillColor: AppColors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: peutEnvoyer ? _envoyerTexte : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: peutEnvoyer ? 1 : 0.4,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    gradient: AppColors.gradientPink, shape: BoxShape.circle),
                child: _envoi
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Avatar d'un groupe : photo (affiche de l'événement) ou initiale.
class AvatarGroupe extends StatelessWidget {
  final GroupeResume groupe;
  final double rayon;
  const AvatarGroupe({super.key, required this.groupe, this.rayon = 26});

  @override
  Widget build(BuildContext context) {
    final photo = groupe.photoUrl ?? '';
    return CircleAvatar(
      radius: rayon,
      backgroundColor: AppColors.accent.withValues(alpha: 0.25),
      backgroundImage:
          photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
      onBackgroundImageError: photo.isNotEmpty ? (_, __) {} : null,
      child: photo.isEmpty
          ? Text(
              groupe.estEvenement
                  ? '📅'
                  : (groupe.nom.isEmpty ? '👥' : groupe.nom[0].toUpperCase()),
              style: TextStyle(
                  fontSize: rayon * 0.8,
                  fontWeight: FontWeight.w800,
                  color: Colors.white))
          : null,
    );
  }
}
