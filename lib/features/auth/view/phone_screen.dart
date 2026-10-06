import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';

// ── Liste des pays (Afrique + monde) ──────────────────────────────

class CountryCode {
  final String flag, name, code;
  const CountryCode(this.flag, this.name, this.code);
}

const List<CountryCode> kCountries = [
  // Afrique de l'Ouest
  CountryCode('🇨🇮', 'Côte d\'Ivoire', '+225'),
  CountryCode('🇸🇳', 'Sénégal', '+221'),
  CountryCode('🇲🇱', 'Mali', '+223'),
  CountryCode('🇬🇳', 'Guinée', '+224'),
  CountryCode('🇧🇫', 'Burkina Faso', '+226'),
  CountryCode('🇧🇯', 'Bénin', '+229'),
  CountryCode('🇹🇬', 'Togo', '+228'),
  CountryCode('🇬🇭', 'Ghana', '+233'),
  CountryCode('🇳🇬', 'Nigeria', '+234'),
  CountryCode('🇳🇪', 'Niger', '+227'),
  CountryCode('🇬🇼', 'Guinée-Bissau', '+245'),
  CountryCode('🇱🇷', 'Liberia', '+231'),
  CountryCode('🇸🇱', 'Sierra Leone', '+232'),
  CountryCode('🇲🇷', 'Mauritanie', '+222'),
  CountryCode('🇬🇲', 'Gambie', '+220'),
  CountryCode('🇨🇻', 'Cap-Vert', '+238'),
  // Afrique Centrale
  CountryCode('🇨🇲', 'Cameroun', '+237'),
  CountryCode('🇨🇩', 'Congo RDC', '+243'),
  CountryCode('🇨🇬', 'Congo', '+242'),
  CountryCode('🇬🇦', 'Gabon', '+241'),
  CountryCode('🇹🇩', 'Tchad', '+235'),
  // Afrique de l'Est
  CountryCode('🇰🇪', 'Kenya', '+254'),
  CountryCode('🇹🇿', 'Tanzanie', '+255'),
  CountryCode('🇺🇬', 'Ouganda', '+256'),
  CountryCode('🇪🇹', 'Ethiopie', '+251'),
  // Afrique du Nord
  CountryCode('🇲🇦', 'Maroc', '+212'),
  CountryCode('🇩🇿', 'Algérie', '+213'),
  CountryCode('🇹🇳', 'Tunisie', '+216'),
  // Europe
  CountryCode('🇫🇷', 'France', '+33'),
  CountryCode('🇧🇪', 'Belgique', '+32'),
  CountryCode('🇨🇭', 'Suisse', '+41'),
  CountryCode('🇬🇧', 'Royaume-Uni', '+44'),
  CountryCode('🇩🇪', 'Allemagne', '+49'),
  CountryCode('🇪🇸', 'Espagne', '+34'),
  CountryCode('🇮🇹', 'Italie', '+39'),
  CountryCode('🇵🇹', 'Portugal', '+351'),
  // Amériques
  CountryCode('🇺🇸', 'États-Unis', '+1'),
  CountryCode('🇨🇦', 'Canada', '+1'),
];

// ── Écran principal ───────────────────────────────────────────────
// ✅ SMS désactivé — cet écran informe l'utilisateur et le redirige
// vers les méthodes disponibles : Email ou Google

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  CountryCode _selected = kCountries.first;

  void _showCountryPicker() {
    final search = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) {
          final filtered = kCountries
              .where((c) =>
                  c.name.toLowerCase().contains(search.text.toLowerCase()) ||
                  c.code.contains(search.text))
              .toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(children: [
              Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
               Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Choisir un pays',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: search,
                  style:  TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle:  TextStyle(color: AppColors.textMuted),
                    prefixIcon:  Icon(Icons.search_rounded,
                        color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onChanged: (_) => setModal(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final isSelected =
                        c.code == _selected.code && c.name == _selected.name;
                    return ListTile(
                      leading:
                          Text(c.flag, style: const TextStyle(fontSize: 24)),
                      title: Text(c.name,
                          style: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400)),
                      trailing: Text(c.code,
                          style: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textMuted,
                              fontWeight: FontWeight.w600)),
                      onTap: () {
                        setState(() => _selected = c);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // Bouton retour
                GestureDetector(
                  onTap: () => Get.back(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                    child:  Icon(Icons.arrow_back_ios_rounded,
                        size: 18, color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 32),

                const Text('📱', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),

                Text('Connexion par\ntéléphone',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          height: 1.2)),
                const SizedBox(height: 8),
                 Text(
                  'Connecte-toi avec ton numéro de téléphone via SMS.',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textMuted, height: 1.5),
                ),
                const SizedBox(height: 32),

                // Sélecteur pays + numéro (affiché mais désactivé)
                Opacity(
                  opacity: 0.45,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.border, width: 1.5),
                    ),
                    child: Row(children: [
                      GestureDetector(
                        onTap: _showCountryPicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 16),
                          decoration:  BoxDecoration(
                              border: Border(
                                  right: BorderSide(color: AppColors.border))),
                          child: Row(children: [
                            Text(_selected.flag,
                                style: const TextStyle(fontSize: 20)),
                            const SizedBox(width: 6),
                            Text(_selected.code,
                                style:  TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            const SizedBox(width: 4),
                             Icon(Icons.keyboard_arrow_down_rounded,
                                size: 18, color: AppColors.textMuted),
                          ]),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          enabled: false,
                          style:  TextStyle(
                              fontSize: 15, color: AppColors.textPrimary),
                          decoration:  InputDecoration(
                            hintText: 'Numéro de téléphone',
                            hintStyle: TextStyle(color: AppColors.textMuted),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 14, vertical: 16),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),

                // ✅ Badge "bientôt disponible"
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.accent2.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: AppColors.accent2.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accent2.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                          child: Text('🔔', style: TextStyle(fontSize: 18))),
                    ),
                    const SizedBox(width: 12),
                     Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connexion SMS bientôt disponible',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Cette fonctionnalité arrive prochainement. Utilise Email ou Google pour te connecter.',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 32),

                // Bouton Email
                _ActionButton(
                  icon: Icons.email_outlined,
                  label: 'Continuer avec Email',
                  onTap: () => Get.toNamed('/login'),
                ),
                const SizedBox(height: 12),

                // Bouton Inscription
                _ActionButton(
                  icon: Icons.person_add_outlined,
                  label: 'Créer un compte',
                  onTap: () => Get.toNamed('/signup'),
                  isPrimary: true,
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── BOUTON ACTION ────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: isPrimary ? AppColors.gradientPink : null,
          color: isPrimary ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: isPrimary
              ? null
              : Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18,
                color: isPrimary ? AppColors.surAccent : AppColors.textPrimary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isPrimary ? AppColors.surAccent : AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
