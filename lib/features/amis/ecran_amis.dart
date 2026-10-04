import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/amis/amis_controller.dart';
import 'package:rencontre/features/profil/vue/qr_zamu.dart';

/// « Mes amis » : demandes reçues, amis, et ajouter des amis
/// (@pseudo ou QR code).
class EcranAmis extends StatefulWidget {
  final bool ouvrirDemandes;
  const EcranAmis({super.key, this.ouvrirDemandes = false});

  @override
  State<EcranAmis> createState() => _EcranAmisState();
}

class _EcranAmisState extends State<EcranAmis> {
  final _recherche = TextEditingController();
  List<Ami> _trouves = [];
  int _numero = 0;

  AmisController get _ctrl => AmisController.to;

  @override
  void initState() {
    super.initState();
    _ctrl.charger();
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  Future<void> _chercher(String q) async {
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
              Ami(
                id: r['id'] as String,
                nom: (r['name'] as String?) ?? 'Utilisateur',
                photoUrl: r['photo_url'] as String?,
                pseudo: r['username'] as String?,
                enLigne: r['en_ligne'] == true,
                statut: _ctrl.statutDe(r['id'] as String),
              ),
          ]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.ouvrirDemandes ? 1 : 0,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          title: const Text('👥 Amis',
              style: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Scanner un QR code',
              onPressed: () => Get.to(() => const EcranScanQr()),
              icon: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.accent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textMuted,
            tabs: [
              Obx(() => Tab(text: 'Mes amis (${_ctrl.amis.length})')),
              Obx(() => Tab(
                  text: _ctrl.nbDemandes > 0
                      ? 'Demandes (${_ctrl.nbDemandes})'
                      : 'Demandes')),
            ],
          ),
        ),
        body: TabBarView(children: [
          _ongletAmis(),
          _ongletDemandes(),
        ]),
      ),
    );
  }

  // ── Mes amis + ajouter ──
  Widget _ongletAmis() {
    return Obx(() {
      final amis = _ctrl.amis;
      return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _recherche,
            onChanged: _chercher,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ajouter un ami par son @pseudo…',
              hintStyle: TextStyle(color: AppColors.textMuted),
              prefixIcon:
                  Icon(Icons.person_add_rounded, color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        if (_trouves.isNotEmpty) ...[
          _titre('RÉSULTATS'),
          for (final a in _trouves) _ligne(a, recherche: true),
          const Divider(),
        ],
        if (amis.isEmpty && _trouves.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
                'Ajoute tes amis avec leur @pseudo ou en scannant leur QR '
                'code (📷 en haut à droite).',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, height: 1.5)),
          ),
        for (final a in amis) _ligne(a),
      ]);
    });
  }

  // ── Demandes reçues / envoyées ──
  Widget _ongletDemandes() {
    return Obx(() {
      final recues = _ctrl.demandesRecues;
      final envoyees = _ctrl.demandesEnvoyees;
      if (recues.isEmpty && envoyees.isEmpty) {
        return Center(
          child: Text('Aucune demande en attente',
              style: TextStyle(color: AppColors.textMuted)),
        );
      }
      return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        if (recues.isNotEmpty) ...[
          _titre('REÇUES'),
          for (final a in recues) _ligne(a),
        ],
        if (envoyees.isNotEmpty) ...[
          _titre('ENVOYÉES'),
          for (final a in envoyees) _ligne(a),
        ],
      ]);
    });
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppColors.textMuted)),
      );

  Widget _ligne(Ami a, {bool recherche = false}) {
    final statut = recherche ? _ctrl.statutDe(a.id) : a.statut;
    return ListTile(
      onTap: () => ouvrirProfilParId(a.id),
      leading: Stack(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.surface2,
          backgroundImage: (a.photoUrl ?? '').isNotEmpty
              ? CachedNetworkImageProvider(a.photoUrl!)
              : null,
          onBackgroundImageError:
              (a.photoUrl ?? '').isNotEmpty ? (_, __) {} : null,
          child: (a.photoUrl ?? '').isEmpty
              ? Text(a.nom.isEmpty ? '?' : a.nom[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700))
              : null,
        ),
        if (a.enLigne)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.online,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 2),
              ),
            ),
          ),
      ]),
      title: Text(a.nom,
          style: TextStyle(
              fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: (a.pseudo ?? '').isNotEmpty
          ? Text('@${a.pseudo}',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13))
          : null,
      trailing: BoutonAmi(userId: a.id, statutInitial: statut, compact: true),
    );
  }
}

/// Bouton « Ajouter en ami » / « Demande envoyée » / « Accepter » /
/// « ✓ Amis » — sur le profil, dans les listes…
class BoutonAmi extends StatefulWidget {
  final String userId;
  final String? statutInitial;
  final bool compact;
  const BoutonAmi(
      {super.key,
      required this.userId,
      this.statutInitial,
      this.compact = false});

  @override
  State<BoutonAmi> createState() => _BoutonAmiState();
}

class _BoutonAmiState extends State<BoutonAmi> {
  late String _statut = widget.statutInitial ??
      (Get.isRegistered<AmisController>()
          ? AmisController.to.statutDe(widget.userId)
          : 'aucun');
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    if (widget.statutInitial == null && Get.isRegistered<AmisController>()) {
      AmisController.to.statutServeur(widget.userId).then((s) {
        if (mounted) setState(() => _statut = s);
      });
    }
  }

  Future<void> _action(Future<String> Function() f) async {
    setState(() => _envoi = true);
    final s = await f();
    if (mounted) {
      setState(() {
        _statut = s;
        _envoi = false;
      });
    }
  }

  void _menuAmi() {
    Get.bottomSheet(SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: const Icon(Icons.person_remove_rounded, color: Colors.red),
          title: const Text('Retirer de mes amis',
              style: TextStyle(color: Colors.red)),
          onTap: () async {
            Get.back();
            await AmisController.to.retirer(widget.userId);
            if (mounted) setState(() => _statut = 'aucun');
          },
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<AmisController>() ||
        widget.userId == supabase.auth.currentUser?.id) {
      return const SizedBox.shrink();
    }
    final ctrl = AmisController.to;
    final (String label, IconData icon, bool plein, VoidCallback? onTap) =
        switch (_statut) {
      'amis' => ('Amis', Icons.check_rounded, false, _menuAmi),
      'prive' => (
          widget.compact ? 'Privé' : 'Compte privé',
          Icons.lock_rounded,
          false,
          () => Get.snackbar('🔒 Compte privé',
              "Cette personne n'accepte pas les demandes d'ami",
              snackPosition: SnackPosition.TOP,
              backgroundColor: AppColors.surface,
              colorText: Colors.white)
        ),
      'envoyee' => (
          widget.compact ? 'Envoyée' : 'Demande envoyée',
          Icons.schedule_rounded,
          false,
          () => _action(() async {
                await ctrl.retirer(widget.userId);
                return 'aucun';
              })
        ),
      'recue' => (
          'Accepter',
          Icons.person_add_alt_1_rounded,
          true,
          () => _action(() => ctrl.accepter(widget.userId))
        ),
      _ => (
          widget.compact ? 'Ajouter' : 'Ajouter en ami',
          Icons.person_add_rounded,
          true,
          () => _action(() => ctrl.demander(widget.userId))
        ),
    };
    final contenu = _envoi
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: plein ? Colors.white : AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: plein ? Colors.white : AppColors.textPrimary)),
          ]);
    final bouton = GestureDetector(
      onTap: _envoi ? null : onTap,
      child: Container(
        height: widget.compact ? 34 : 44,
        padding: EdgeInsets.symmetric(horizontal: widget.compact ? 12 : 18),
        decoration: BoxDecoration(
          gradient: plein ? AppColors.gradientPink : null,
          color: plein ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: plein ? null : Border.all(color: AppColors.border),
        ),
        child: Center(child: contenu),
      ),
    );
    // Demande reçue : « Accepter » + refuser (✕)
    if (_statut == 'recue') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        bouton,
        IconButton(
          tooltip: 'Refuser',
          onPressed: () async {
            await ctrl.retirer(widget.userId);
            if (mounted) setState(() => _statut = 'aucun');
          },
          icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
        ),
      ]);
    }
    return bouton;
  }
}
