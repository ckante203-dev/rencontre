import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_palette.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/theme/fond_theme.dart';
import 'package:rencontre/core/theme/theme_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

/// Choix du thème avec aperçu en direct (façon Snapchat) : toucher un
/// rond change l'aperçu, rien n'est appliqué avant « Appliquer ».
class EcranThemes extends StatefulWidget {
  const EcranThemes({super.key});

  @override
  State<EcranThemes> createState() => _EcranThemesState();
}

class _EcranThemesState extends State<EcranThemes> {
  late AppPalette _choisi = ThemeController.to.choix.value;

  AppPalette get _actuel => ThemeController.to.choix.value;

  void _appliquer() {
    if (Get.isRegistered<ControleurProfil>()) {
      Get.find<ControleurProfil>().setTheme(_choisi.id);
    } else {
      ThemeController.to.setTheme(_choisi.id);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final proposes = AppPalettes.proposes(DateTime.now(), actuel: _actuel.id);
    final unis = proposes.where((p) => p.motif == Motif.aucun).toList();
    final illustres =
        proposes.where((p) => p.motif != Motif.aucun && !p.estSaison).toList();
    final saison = proposes.where((p) => p.estSaison).toList();
    final dejaActif = _choisi.id == _actuel.id;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text('Thèmes'.tr)),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Center(child: _Apercu(p: _choisi)),
                const SizedBox(height: 22),
                // Clair / Sombre / Système : en préparation, visible en
                // développement seulement (écrans pas tous prêts en clair)
                if (kDebugMode) const _ChoixApparence(),
                _Section('Classiques'.tr, unis, _choisi,
                    (p) => setState(() => _choisi = p)),
                if (illustres.isNotEmpty)
                  _Section('Illustrés'.tr, illustres, _choisi,
                      (p) => setState(() => _choisi = p)),
                if (saison.isNotEmpty)
                  _Section('De saison'.tr, saison, _choisi,
                      (p) => setState(() => _choisi = p)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: dejaActif ? null : _choisi.gradientPink,
                  color: dejaActif ? AppColors.surface2 : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextButton(
                  onPressed: dejaActif ? null : _appliquer,
                  child: Text(
                    dejaActif ? 'Thème actuel ✓'.tr : 'Appliquer le thème'.tr,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: dejaActif
                            ? AppColors.textMuted
                            : AppColors.surAccent),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Une rangée de ronds de thèmes avec un titre
class _Section extends StatelessWidget {
  final String titre;
  final List<AppPalette> themes;
  final AppPalette choisi;
  final void Function(AppPalette) onChoix;
  const _Section(this.titre, this.themes, this.choisi, this.onChoix);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titre,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: themes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) {
              final p = themes[i];
              final selectionne = p.id == choisi.id;
              return GestureDetector(
                onTap: () => onChoix(p),
                child: SizedBox(
                  width: 80,
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 60,
                      height: 60,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: selectionne ? p.accent3 : AppColors.border,
                            width: selectionne ? 2.5 : 1),
                      ),
                      child: ClipOval(
                        child: FondTheme(
                          palette: p,
                          child: Center(
                            child: p.emoji != null
                                ? Text(p.emoji!,
                                    style: const TextStyle(fontSize: 22))
                                : Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: p.gradientPink),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Nom en entier (« Lettre d'amour ») : réduit si besoin
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(p.label.tr,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color: selectionne
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontWeight: selectionne
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Faux écran « Messages » dessiné avec la palette [p] (sans l'appliquer)
class _Apercu extends StatelessWidget {
  final AppPalette p;
  const _Apercu({required this.p});

  static const _faux = [
    ('Aïcha', 'On se voit ce soir ? 😊', 2, 1),
    ('Yann', 'Toi : Trop bien, à demain !', 0, 3),
    ('Fatou', 'Haha t\'es drôle 😂', 1, 5),
    ('Marc', 'Toi : Salut, ça va ?', 0, 2),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 250,
      height: 340,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.border, width: 2),
        boxShadow: [
          BoxShadow(
              color: p.accent.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: FondTheme(
          palette: p,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Messages'.tr,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary)),
                if (p.emoji != null) ...[
                  const SizedBox(width: 6),
                  Text(p.emoji!, style: const TextStyle(fontSize: 16)),
                ],
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      gradient: p.gradientPink,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('Tous'.tr,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.surAccent)),
                ),
              ]),
              const SizedBox(height: 12),
              for (final (nom, texte, nonLus, avatar) in _faux)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient:
                            LinearGradient(colors: degradesAvatar[avatar]),
                      ),
                      alignment: Alignment.center,
                      child: Text(nom[0],
                          style: const TextStyle(
                              color: AppColors.surMedia,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nom,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary)),
                            Text(texte,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: nonLus > 0
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: nonLus > 0
                                        ? (p.nouveau ?? p.textPrimary)
                                        : p.textMuted)),
                          ]),
                    ),
                    if (nonLus > 0)
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, gradient: p.gradientPink),
                        child: Text('$nonLus',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.surAccent)),
                      ),
                  ]),
                ),
              const Spacer(),
              // Faux champ de message + bouton
              Row(children: [
                Expanded(
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                        color: p.surface,
                        border: Border.all(color: p.border),
                        borderRadius: BorderRadius.circular(17)),
                    child: Text('Message...'.tr,
                        style: TextStyle(fontSize: 11, color: p.textMuted)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, gradient: p.gradientPink),
                  child: const Icon(Icons.send_rounded,
                      size: 16, color: AppColors.surAccent),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Apparence : Système / Sombre / Clair (en préparation)
class _ChoixApparence extends StatelessWidget {
  const _ChoixApparence();

  @override
  Widget build(BuildContext context) {
    final ctrl = ThemeController.to;
    const options = [
      (Apparence.systeme, 'Système', Icons.brightness_auto_rounded),
      (Apparence.sombre, 'Sombre', Icons.dark_mode_rounded),
      (Apparence.clair, 'Clair', Icons.light_mode_rounded),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Apparence (test)'.tr,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Obx(() => Row(children: [
              for (final (a, nom, icone) in options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => ctrl.setApparence(a),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: ctrl.apparence.value == a
                                  ? AppColors.accent
                                  : AppColors.border,
                              width: ctrl.apparence.value == a ? 2 : 1),
                        ),
                        child: Column(children: [
                          Icon(icone, color: AppColors.textPrimary, size: 22),
                          const SizedBox(height: 4),
                          Text(nom.tr,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ])),
      ]),
    );
  }
}
