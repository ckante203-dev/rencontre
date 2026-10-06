import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';

// ═══════════════════════════════════════════════════════════════════
//  « Quoi de neuf » : présenté UNE fois après la mise à jour 1.1.0 aux
//  membres qui avaient déjà l'app (les nouveaux comptes découvrent déjà
//  tout pendant l'inscription).
// ═══════════════════════════════════════════════════════════════════

const _version = '1.1.0';
const _cle = 'nouveautes_vues';

/// À appeler une fois l'écran principal affiché.
Future<void> afficherNouveautesSiBesoin() async {
  final box = GetStorage();
  if (box.read<String>(_cle) == _version) return;

  // Laisse le temps au profil de se charger (date de création)
  await Future.delayed(const Duration(milliseconds: 2500));
  final moi = Get.isRegistered<HomeController>()
      ? Get.find<HomeController>().myProfile
      : null;
  if (moi == null) return; // réessayé au prochain lancement
  final cree = moi.createdAt;
  final nouveauCompte =
      cree != null && DateTime.now().difference(cree).inDays < 2;
  await box.write(_cle, _version);
  if (nouveauCompte) return;

  await Get.to(() => const EcranNouveautes(),
      fullscreenDialog: true, transition: Transition.downToUp);
}

class _Page {
  final String emoji, titre, texte;
  final List<String> points;
  const _Page(this.emoji, this.titre, this.texte, this.points);
}

const _pages = [
  _Page('📸', 'Des stories façon Snapchat',
      'Un onglet rien que pour elles : tes proches en haut, le reste à découvrir.', [
    'Caméra Zamu : stickers, emojis, GIF et textes',
    'Glisse vers le haut pour répondre, vers le bas pour fermer',
    'Réponds avec ❤️ ou 👍 en un appui',
  ]),
  _Page('📅', 'Les événements',
      'Sorties, soirées et rencontres près de chez toi, choisies par Zamu.', [
    '« J\'y vais » : vois qui vient',
    '« Je suis sur place » le jour J',
    'Le lendemain : « Tu as croisé… » 👋',
  ]),
  _Page('👥', 'Amis et groupes',
      'Garde le lien avec ceux qui comptent.', [
    'Demandes d\'ami et liste d\'amis',
    'Discussions de groupe',
    'Stories réservées à tes amis proches',
  ]),
  _Page('⚡', 'Le Boost',
      'Ton profil passe en tête chez les gens autour de toi.', [
    'Badge ⚡ et contour qui attirent les regards',
    'Tes stories passent en premier',
    'Le bilan de tes vues et likes à la fin',
  ]),
  _Page('💬', 'Un chat plus pro',
      'Plus rapide, plus clair, à ton style.', [
    'Glisse un message pour y répondre',
    'Coches de lecture et « vu à 14:32 »',
    'Thèmes de couleur dans ton profil',
  ]),
];

class EcranNouveautes extends StatefulWidget {
  const EcranNouveautes({super.key});
  @override
  State<EcranNouveautes> createState() => _EcranNouveautesState();
}

class _EcranNouveautesState extends State<EcranNouveautes> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _derniere => _page == _pages.length - 1;

  void _suivant() {
    if (_derniere) {
      Get.back();
      return;
    }
    _ctrl.nextPage(
        duration: const Duration(milliseconds: 320), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final bas = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // En-tête : « Quoi de neuf » + Passer
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(children: [
              Text('Quoi de neuf',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AppColors.textMuted)),
              const Spacer(),
              if (!_derniere)
                TextButton(
                  onPressed: Get.back,
                  child: Text('Passer',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _ctrl,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => _Diapo(page: _pages[i]),
            ),
          ),
          // Points de progression
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pages.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: i == _page ? 22 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  gradient: i == _page ? AppColors.gradientPink : null,
                  color: i == _page ? null : AppColors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, bas + 20),
            child: GestureDetector(
              onTap: _suivant,
              child: Container(
                width: double.infinity,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(_derniere ? 'C\'est parti 🚀' : 'Suivant',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Diapo extends StatelessWidget {
  final _Page page;
  const _Diapo({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 120,
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent.withValues(alpha: 0.12),
            border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.4), width: 2),
          ),
          child: Text(page.emoji, style: const TextStyle(fontSize: 56)),
        ),
        const SizedBox(height: 28),
        Text(page.titre,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        Text(page.texte,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 14.5, height: 1.45, color: AppColors.textMuted)),
        const SizedBox(height: 26),
        ...page.points.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(p,
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ]),
            )),
      ]),
    );
  }
}
