import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

// ─── STATUT « DISPO MAINTENANT » (façon Right Now de Grindr) ───────
// Un statut qui dure quelques heures (« ☕ Dispo pour un café »…),
// affiché sur la carte de l'accueil (filtre « Dispo ») et sur le profil.

const statutsDispo = [
  '☕ Dispo pour un café',
  '💬 Envie de discuter',
  '🍻 Partant pour sortir',
  '🍽️ On mange ensemble ?',
  '🎬 Film ou série ce soir',
  '🚶 Je me balade',
  '💃 Envie de danser',
  '🎮 Partant pour jouer',
];

const _durees = [
  Duration(hours: 1),
  Duration(hours: 3),
  Duration(hours: 6),
  Duration(hours: 12),
];

/// « encore 2 h 15 », « encore 40 min »
String dureeRestanteDispo(DateTime fin) {
  final r = fin.difference(DateTime.now());
  if (r.inMinutes < 1) return 'bientôt fini';
  if (r.inHours == 0) return 'encore ${r.inMinutes} min';
  final m = r.inMinutes % 60;
  return m == 0
      ? 'encore ${r.inHours} h'
      : 'encore ${r.inHours} h ${m.toString().padLeft(2, '0')}';
}

class CarteDispo extends StatelessWidget {
  final ControleurProfil ctrl;
  const CarteDispo({super.key, required this.ctrl});

  void _ouvrir() => Get.bottomSheet(
        _FeuilleDispo(ctrl: ctrl),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(() {
        // lu pour que l'Obx suive aussi la date de fin
        ctrl.dispoJusqua.value;
        final actif = ctrl.dispoActive;
        return GestureDetector(
          onTap: _ouvrir,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: actif
                  ? AppColors.online.withOpacity(0.12)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: actif
                      ? AppColors.online.withOpacity(0.5)
                      : AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: actif ? AppColors.online : AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                    child: Text('🙋', style: TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(actif ? ctrl.dispoTexte.value! : 'Dispo maintenant ?',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        actif
                            ? '${dureeRestanteDispo(ctrl.dispoJusqua.value!)} · visible sur l\'accueil'
                            : 'Dis aux autres ce que tu as envie de faire',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
              if (actif)
                IconButton(
                  tooltip: 'Arrêter',
                  onPressed: () => ctrl.definirDispo(null, Duration.zero),
                  icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
                )
              else
                Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ]),
          ),
        );
      }),
    );
  }
}

class _FeuilleDispo extends StatefulWidget {
  final ControleurProfil ctrl;
  const _FeuilleDispo({required this.ctrl});

  @override
  State<_FeuilleDispo> createState() => _FeuilleDispoState();
}

class _FeuilleDispoState extends State<_FeuilleDispo> {
  late final TextEditingController _perso = TextEditingController();
  String? _choisi;
  Duration _duree = const Duration(hours: 3);
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    final actuel = widget.ctrl.dispoActive ? widget.ctrl.dispoTexte.value : null;
    if (actuel != null) {
      if (statutsDispo.contains(actuel)) {
        _choisi = actuel;
      } else {
        _perso.text = actuel;
      }
    } else {
      _choisi = statutsDispo.first;
    }
  }

  @override
  void dispose() {
    _perso.dispose();
    super.dispose();
  }

  String? get _texte {
    final p = _perso.text.trim();
    return p.isNotEmpty ? p : _choisi;
  }

  Future<void> _publier() async {
    final t = _texte;
    if (t == null) return;
    setState(() => _envoi = true);
    final ok = await widget.ctrl.definirDispo(t, _duree);
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) Get.back();
  }

  Widget _puce(String label, bool actif, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: actif ? AppColors.online.withOpacity(0.18) : AppColors.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: actif ? AppColors.online : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final persoActif = _perso.text.trim().isNotEmpty;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
              const SizedBox(height: 16),
              Text('🙋 Dispo maintenant',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                  'Ton statut s\'affiche sur ta carte dans l\'accueil, '
                  'puis disparaît tout seul.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in statutsDispo)
                    _puce(s, !persoActif && _choisi == s,
                        () => setState(() {
                              _choisi = s;
                              _perso.clear();
                              FocusScope.of(context).unfocus();
                            })),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _perso,
                maxLength: 40,
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ou écris le tien…',
                  hintStyle: TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('Pendant',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Row(children: [
                for (final d in _durees) ...[
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _duree = d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _duree == d
                              ? AppColors.online.withOpacity(0.18)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _duree == d
                                  ? AppColors.online
                                  : AppColors.border),
                        ),
                        child: Center(
                          child: Text('${d.inHours} h',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                        ),
                      ),
                    ),
                  ),
                  if (d != _durees.last) const SizedBox(width: 8),
                ],
              ]),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _envoi ? null : _publier,
                child: Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _envoi
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Publier mon statut',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
