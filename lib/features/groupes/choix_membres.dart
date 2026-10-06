import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/groupes/ecran_groupe.dart';
import 'package:rencontre/features/groupes/groupes_controller.dart';

class _Contact {
  final String id;
  final String nom;
  final String? photo;
  final String? pseudo;
  const _Contact(this.id, this.nom, this.photo, [this.pseudo]);
}

/// Choisir des personnes (contacts de Messages + recherche @pseudo).
/// [nouveauGroupe] : demande aussi un nom et crée le groupe.
/// Sinon renvoie la liste des ids choisis (ajout de membres).
class ChoixMembres extends StatefulWidget {
  final bool nouveauGroupe;
  final Set<String> dejaMembres;
  final int maximum;
  const ChoixMembres({
    super.key,
    this.nouveauGroupe = true,
    this.dejaMembres = const {},
    this.maximum = 49,
  });

  @override
  State<ChoixMembres> createState() => _ChoixMembresState();
}

class _ChoixMembresState extends State<ChoixMembres> {
  final _nom = TextEditingController();
  final Map<String, _Contact> _choisis = {};
  final List<_Contact> _contacts = [];
  List<_Contact> _trouves = [];
  String _recherche = '';
  int _numero = 0;
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<ChatListController>()) {
      final vus = <String>{};
      for (final c in Get.find<ChatListController>().conversations) {
        if (c.userId.isEmpty ||
            widget.dejaMembres.contains(c.userId) ||
            !vus.add(c.userId)) {
          continue;
        }
        _contacts.add(_Contact(c.userId, c.userName, c.userPhotoUrl));
      }
    }
    _nom.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nom.dispose();
    super.dispose();
  }

  Future<void> _chercher(String q) async {
    setState(() => _recherche = q);
    final pseudo = q.trim().replaceFirst(RegExp(r'^@+'), '');
    final numero = ++_numero;
    if (pseudo.length < 3) {
      setState(() => _trouves = []);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 350));
    if (numero != _numero) return;
    try {
      final rows = await supabase
          .rpc('chercher_par_pseudo', params: {'p_q': pseudo}) as List;
      if (numero != _numero || !mounted) return;
      setState(() => _trouves = [
            for (final r in rows)
              if (!widget.dejaMembres.contains(r['id']))
                _Contact(r['id'] as String, r['name'] ?? 'Utilisateur',
                    r['photo_url'] as String?, r['username'] as String?),
          ]);
    } catch (_) {}
  }

  void _basculer(_Contact c) {
    setState(() {
      if (_choisis.remove(c.id) == null) {
        if (_choisis.length >= widget.maximum) {
          Get.snackbar('Groupe complet',
              '${widget.maximum + 1} membres maximum dans un groupe',
              snackPosition: SnackPosition.TOP,
              backgroundColor: AppColors.surface,
              colorText: AppColors.textPrimary);
          return;
        }
        _choisis[c.id] = c;
      }
    });
  }

  Future<void> _valider() async {
    if (_choisis.isEmpty || _envoi) return;
    if (!widget.nouveauGroupe) {
      Get.back(result: _choisis.keys.toList());
      return;
    }
    final nom = _nom.text.trim();
    if (nom.isEmpty) return;
    setState(() => _envoi = true);
    final ctrl = GroupesController.to;
    final id = await ctrl.creer(nom, _choisis.keys.toList());
    if (!mounted) return;
    setState(() => _envoi = false);
    if (id == null) return;
    final g = ctrl.groupes.firstWhereOrNull((x) => x.id == id);
    Get.back();
    if (g != null) Get.to(() => EcranGroupe(groupe: g));
  }

  @override
  Widget build(BuildContext context) {
    final q = _recherche.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');
    final contacts = _contacts
        .where((c) =>
            q.isEmpty ||
            c.nom.toLowerCase().contains(q) ||
            (c.pseudo ?? '').toLowerCase().contains(q))
        .toList();
    final ids = contacts.map((c) => c.id).toSet();
    final autres = _trouves.where((c) => !ids.contains(c.id)).toList();
    final pret = _choisis.isNotEmpty &&
        (!widget.nouveauGroupe || _nom.text.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
            widget.nouveauGroupe ? 'Nouveau groupe' : 'Ajouter des membres',
            style: const TextStyle(
                fontFamily: 'Syne', fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: pret
          ? FloatingActionButton.extended(
              onPressed: _valider,
              backgroundColor: AppColors.accent,
              icon: _envoi
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_rounded, color: Colors.white),
              label: Text(
                  widget.nouveauGroupe
                      ? 'Créer (${_choisis.length + 1})'
                      : 'Ajouter (${_choisis.length})',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            )
          : null,
      body: Column(children: [
        if (widget.nouveauGroupe)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              controller: _nom,
              maxLength: 60,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                hintText: 'Nom du groupe (ex : Les amis de Cocody)',
                hintStyle: TextStyle(color: AppColors.textMuted),
                counterText: '',
                prefixIcon: Icon(Icons.group_rounded, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        // Personnes choisies
        if (_choisis.isNotEmpty)
          SizedBox(
            height: 74,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final c in _choisis.values)
                  GestureDetector(
                    onTap: () => _basculer(c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(children: [
                        Stack(children: [
                          _avatar(c, 22),
                          const Positioned(
                            right: 0,
                            top: 0,
                            child: CircleAvatar(
                              radius: 8,
                              backgroundColor: Colors.black87,
                              child: Icon(Icons.close_rounded,
                                  size: 11, color: Colors.white),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 3),
                        SizedBox(
                          width: 52,
                          child: Text(c.nom,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textPrimary)),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            onChanged: _chercher,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Rechercher un nom ou un @pseudo…',
              hintStyle: TextStyle(color: AppColors.textMuted),
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: (contacts.isEmpty && autres.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        'Cherche tes amis par leur @pseudo pour les ajouter',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              : ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                  for (final c in contacts) _ligne(c),
                  if (autres.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                      child: Text('PROFILS ZAMU',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                              color: AppColors.textMuted)),
                    ),
                    for (final c in autres) _ligne(c),
                  ],
                ]),
        ),
      ]),
    );
  }

  Widget _avatar(_Contact c, double r) => CircleAvatar(
        radius: r,
        backgroundColor: AppColors.surface2,
        backgroundImage: (c.photo ?? '').isNotEmpty
            ? CachedNetworkImageProvider(c.photo!)
            : null,
        onBackgroundImageError: (c.photo ?? '').isNotEmpty ? (_, __) {} : null,
        child: (c.photo ?? '').isEmpty
            ? Text(c.nom.isEmpty ? '?' : c.nom[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))
            : null,
      );

  Widget _ligne(_Contact c) {
    final choisi = _choisis.containsKey(c.id);
    return ListTile(
      onTap: () => _basculer(c),
      leading: _avatar(c, 22),
      title: Text(c.nom,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: (c.pseudo ?? '').isNotEmpty
          ? Text('@${c.pseudo}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13))
          : null,
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: choisi ? AppColors.accent : Colors.transparent,
          border: Border.all(
              color: choisi ? AppColors.accent : AppColors.border, width: 2),
        ),
        child: choisi
            ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
