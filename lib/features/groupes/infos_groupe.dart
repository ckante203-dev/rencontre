import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/groupes/choix_membres.dart';
import 'package:rencontre/features/groupes/ecran_groupe.dart';
import 'package:rencontre/features/groupes/groupe_model.dart';
import 'package:rencontre/features/groupes/groupes_controller.dart';

/// Infos du groupe : membres, sourdine, nom (admin), ajouter / retirer
/// des membres, nommer un admin, quitter.
class InfosGroupe extends StatefulWidget {
  final GroupeResume groupe;
  final List<MembreGroupe> membres;
  const InfosGroupe({super.key, required this.groupe, required this.membres});

  @override
  State<InfosGroupe> createState() => _InfosGroupeState();
}

class _InfosGroupeState extends State<InfosGroupe> {
  late GroupeResume _g = widget.groupe;
  late List<MembreGroupe> _membres = [...widget.membres];
  late bool _sourdine = widget.groupe.sourdine;

  String get _moi => supabase.auth.currentUser?.id ?? '';
  bool get _suisAdmin =>
      _membres.any((m) => m.id == _moi && m.admin) || _g.suisAdmin;
  bool get _gere => _suisAdmin && !_g.estEvenement; // groupe d'amis

  void _snack(String t, String m) => Get.snackbar(t, m,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white);

  Future<void> _rechargerMembres() async {
    try {
      final rows = await supabase
          .from('groupe_membres')
          .select('user_id, role, profiles(name, photo_url)')
          .eq('groupe_id', _g.id);
      setState(() => _membres = [
            for (final r in rows as List)
              MembreGroupe(
                id: r['user_id'] as String,
                nom: (r['profiles']?['name'] as String?) ?? 'Utilisateur',
                photoUrl: r['profiles']?['photo_url'] as String?,
                admin: r['role'] == 'admin',
              ),
          ]);
    } catch (_) {}
  }

  Future<void> _basculerSourdine(bool v) async {
    setState(() => _sourdine = v);
    try {
      await supabase
          .from('groupe_membres')
          .update({'sourdine': v})
          .eq('groupe_id', _g.id)
          .eq('user_id', _moi);
      GroupesController.to.charger();
    } catch (_) {
      setState(() => _sourdine = !v);
      _snack('Oups', 'Réglage non enregistré');
    }
  }

  Future<void> _renommer() async {
    final champ = TextEditingController(text: _g.nom);
    final nom = await Get.dialog<String>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Nom du groupe',
          style: TextStyle(color: AppColors.textPrimary)),
      content: TextField(
        controller: champ,
        maxLength: 60,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Annuler')),
        TextButton(
            onPressed: () => Get.back(result: champ.text.trim()),
            child: const Text('Enregistrer')),
      ],
    ));
    if (nom == null || nom.isEmpty || nom == _g.nom) return;
    try {
      await supabase.from('groupes').update({'nom': nom}).eq('id', _g.id);
      setState(() => _g = GroupeResume(
            id: _g.id,
            nom: nom,
            photoUrl: _g.photoUrl,
            evenementId: _g.evenementId,
            nbMembres: _g.nbMembres,
            suisAdmin: _g.suisAdmin,
            sourdine: _sourdine,
            derniereActivite: _g.derniereActivite,
          ));
      GroupesController.to.charger();
    } catch (_) {
      _snack('Oups', 'Nom non modifié');
    }
  }

  Future<void> _ajouter() async {
    final ids = await Get.to<List<String>>(() => ChoixMembres(
          nouveauGroupe: false,
          dejaMembres: _membres.map((m) => m.id).toSet(),
          maximum: 50 - _membres.length,
        ));
    if (ids == null || ids.isEmpty) return;
    try {
      final n = await supabase.rpc('ajouter_membres_groupe',
          params: {'p_groupe': _g.id, 'p_membres': ids}) as int;
      await _rechargerMembres();
      _snack('Membres ajoutés', '$n personne${n > 1 ? 's' : ''} ajoutée${n > 1 ? 's' : ''}');
    } catch (_) {
      _snack('Oups', 'Ajout impossible');
    }
  }

  void _optionsMembre(MembreGroupe m) {
    if (m.id == _moi) return;
    Get.bottomSheet(SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.person_rounded, color: AppColors.textPrimary),
            title: Text('Voir le profil de ${m.nom}',
                style: TextStyle(color: AppColors.textPrimary)),
            onTap: () {
              Get.back();
              ouvrirProfilParId(m.id);
            },
          ),
          if (_gere && !m.admin)
            ListTile(
              leading:
                  Icon(Icons.verified_user_rounded, color: AppColors.textPrimary),
              title: Text('Nommer admin',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () async {
                Get.back();
                try {
                  await supabase.rpc('promouvoir_membre_groupe',
                      params: {'p_groupe': _g.id, 'p_user': m.id});
                  _rechargerMembres();
                } catch (_) {
                  _snack('Oups', 'Impossible');
                }
              },
            ),
          if (_gere)
            ListTile(
              leading: const Icon(Icons.person_remove_rounded, color: Colors.red),
              title: Text('Retirer ${m.nom} du groupe',
                  style: const TextStyle(color: Colors.red)),
              onTap: () async {
                Get.back();
                try {
                  await supabase
                      .from('groupe_membres')
                      .delete()
                      .eq('groupe_id', _g.id)
                      .eq('user_id', m.id);
                  _rechargerMembres();
                } catch (_) {
                  _snack('Oups', 'Impossible de retirer ce membre');
                }
              },
            ),
        ]),
      ),
    ));
  }

  Future<void> _quitter() async {
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Quitter « ${_g.nom} » ?',
          style: TextStyle(color: AppColors.textPrimary)),
      content: Text(
          _g.estEvenement
              ? 'Tu ne recevras plus les messages de cet événement. Tu restes '
                  'inscrit à l\'événement.'
              : 'Tu ne recevras plus les messages de ce groupe.',
          style: TextStyle(color: AppColors.textMuted)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler')),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Quitter', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    try {
      await supabase
          .from('groupe_membres')
          .delete()
          .eq('groupe_id', _g.id)
          .eq('user_id', _moi);
      await GroupesController.to.charger();
      Get.back(); // infos
      Get.back(); // discussion
    } catch (_) {
      _snack('Oups', 'Impossible de quitter le groupe');
    }
  }

  @override
  Widget build(BuildContext context) {
    final membres = [..._membres]
      ..sort((a, b) {
        if (a.id == _moi) return -1;
        if (b.id == _moi) return 1;
        if (a.admin != b.admin) return a.admin ? -1 : 1;
        return a.nom.compareTo(b.nom);
      });
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: BackButton(onPressed: () => Get.back(result: _g)),
      ),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Center(child: AvatarGroupe(groupe: _g, rayon: 46)),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: _gere ? _renommer : null,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text(_g.nom,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              if (_gere) ...[
                const SizedBox(width: 6),
                Icon(Icons.edit_rounded, size: 16, color: AppColors.textMuted),
              ],
            ]),
          ),
        ),
        Center(
          child: Text(
              '${membres.length} membres${_g.estEvenement ? ' · groupe de l\'événement' : ''}',
              style: TextStyle(color: AppColors.textMuted)),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          value: _sourdine,
          onChanged: _basculerSourdine,
          activeColor: AppColors.accent,
          secondary: Icon(Icons.notifications_off_rounded,
              color: AppColors.textMuted),
          title: Text('Mettre en sourdine',
              style: TextStyle(color: AppColors.textPrimary)),
          subtitle: Text('Plus de notifications pour ce groupe',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ),
        const Divider(),
        if (_gere && membres.length < 50)
          ListTile(
            onTap: _ajouter,
            leading: CircleAvatar(
              backgroundColor: AppColors.accent,
              child: const Icon(Icons.person_add_rounded, color: Colors.white),
            ),
            title: Text('Ajouter des membres',
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w700)),
          ),
        for (final m in membres)
          ListTile(
            onTap: () => _optionsMembre(m),
            leading: CircleAvatar(
              backgroundColor: AppColors.surface2,
              backgroundImage: (m.photoUrl ?? '').isNotEmpty
                  ? CachedNetworkImageProvider(m.photoUrl!)
                  : null,
              onBackgroundImageError:
                  (m.photoUrl ?? '').isNotEmpty ? (_, __) {} : null,
              child: (m.photoUrl ?? '').isEmpty
                  ? Text(m.nom.isEmpty ? '?' : m.nom[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white))
                  : null,
            ),
            title: Text(m.id == _moi ? 'Toi' : m.nom,
                style: TextStyle(color: AppColors.textPrimary)),
            trailing: m.admin
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Admin',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent)),
                  )
                : null,
          ),
        const Divider(),
        ListTile(
          onTap: _quitter,
          leading: const Icon(Icons.logout_rounded, color: Colors.red),
          title: const Text('Quitter le groupe',
              style: TextStyle(color: Colors.red)),
        ),
      ]),
    );
  }
}
