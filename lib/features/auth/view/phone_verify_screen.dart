// lib/features/auth/view/phone_verify_screen.dart
//
// Vérification numéro — OPTIONNELLE
// SMS désactivé → numéro sauvegardé sans vérification
// Validation du format selon l'indicatif pays (avertissement, pas bloquant)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

class _Country {
  final String flag, name, code;
  final int digits; // nombre de chiffres attendus APRÈS l'indicatif
  const _Country(this.flag, this.name, this.code, this.digits);
}

// ✅ Chaque pays a son nombre de chiffres attendu pour valider le format
const _countries = [
  _Country('🇨🇮', 'Côte d\'Ivoire', '+225', 10),
  _Country('🇸🇳', 'Sénégal', '+221', 9),
  _Country('🇲🇱', 'Mali', '+223', 8),
  _Country('🇬🇳', 'Guinée', '+224', 9),
  _Country('🇧🇫', 'Burkina Faso', '+226', 8),
  _Country('🇧🇯', 'Bénin', '+229', 8),
  _Country('🇹🇬', 'Togo', '+228', 8),
  _Country('🇬🇭', 'Ghana', '+233', 9),
  _Country('🇳🇬', 'Nigeria', '+234', 10),
  _Country('🇳🇪', 'Niger', '+227', 8),
  _Country('🇲🇷', 'Mauritanie', '+222', 8),
  _Country('🇬🇼', 'Guinée-Bissau', '+245', 9),
  _Country('🇬🇲', 'Gambie', '+220', 7),
  _Country('🇸🇱', 'Sierra Leone', '+232', 8),
  _Country('🇱🇷', 'Liberia', '+231', 8),
  _Country('🇨🇻', 'Cap-Vert', '+238', 7),
  _Country('🇨🇲', 'Cameroun', '+237', 9),
  _Country('🇨🇩', 'Congo RDC', '+243', 9),
  _Country('🇨🇬', 'Congo', '+242', 9),
  _Country('🇬🇦', 'Gabon', '+241', 8),
  _Country('🇹🇩', 'Tchad', '+235', 8),
  _Country('🇨🇫', 'Centrafrique', '+236', 8),
  _Country('🇬🇶', 'Guinée Éq.', '+240', 9),
  _Country('🇰🇪', 'Kenya', '+254', 9),
  _Country('🇹🇿', 'Tanzanie', '+255', 9),
  _Country('🇺🇬', 'Ouganda', '+256', 9),
  _Country('🇷🇼', 'Rwanda', '+250', 9),
  _Country('🇧🇮', 'Burundi', '+257', 8),
  _Country('🇪🇹', 'Éthiopie', '+251', 9),
  _Country('🇲🇬', 'Madagascar', '+261', 9),
  _Country('🇲🇺', 'Maurice', '+230', 8),
  _Country('🇿🇦', 'Afrique du Sud', '+27', 9),
  _Country('🇲🇦', 'Maroc', '+212', 9),
  _Country('🇩🇿', 'Algérie', '+213', 9),
  _Country('🇹🇳', 'Tunisie', '+216', 8),
  _Country('🇪🇬', 'Égypte', '+20', 10),
  _Country('🇫🇷', 'France', '+33', 9),
  _Country('🇧🇪', 'Belgique', '+32', 9),
  _Country('🇨🇭', 'Suisse', '+41', 9),
  _Country('🇬🇧', 'Royaume-Uni', '+44', 10),
  _Country('🇩🇪', 'Allemagne', '+49', 10),
  _Country('🇪🇸', 'Espagne', '+34', 9),
  _Country('🇮🇹', 'Italie', '+39', 10),
  _Country('🇵🇹', 'Portugal', '+351', 9),
  _Country('🇺🇸', 'États-Unis', '+1', 10),
  _Country('🇨🇦', 'Canada', '+1', 10),
  _Country('🇭🇹', 'Haïti', '+509', 8),
];

class PhoneVerifyScreen extends StatefulWidget {
  const PhoneVerifyScreen({super.key});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final ctrl = Get.find<AuthController>();
  _Country _selected = _countries.first; // CI par défaut
  final _phoneController = TextEditingController();
  String? _formatWarning; // avertissement format (pas bloquant)

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  // ✅ Validation format — avertit mais laisse continuer
  void _validateFormat(String value) {
    if (value.isEmpty) {
      setState(() => _formatWarning = null);
      return;
    }
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length != _selected.digits) {
      setState(() => _formatWarning =
          '${_selected.name} : ${_selected.digits} chiffres attendus (tu en as ${digits.length})');
    } else {
      setState(() => _formatWarning = null);
    }
  }

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
          final filtered = _countries
              .where((c) =>
                  c.name.toLowerCase().contains(search.text.toLowerCase()) ||
                  c.code.contains(search.text))
              .toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(children: [
              Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text('Choisir un pays',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: search,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Rechercher...',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    prefixIcon: const Icon(Icons.search_rounded,
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
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final c = filtered[i];
                    final isSel =
                        c.code == _selected.code && c.name == _selected.name;
                    return ListTile(
                      leading:
                          Text(c.flag, style: const TextStyle(fontSize: 24)),
                      title: Text(c.name,
                          style: TextStyle(
                              color: isSel
                                  ? AppColors.accent
                                  : AppColors.textPrimary,
                              fontWeight:
                                  isSel ? FontWeight.w700 : FontWeight.w400)),
                      trailing: Text('${c.code} · ${c.digits} chiffres',
                          style: TextStyle(
                              color: isSel
                                  ? AppColors.accent
                                  : AppColors.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                      onTap: () {
                        setState(() {
                          _selected = c;
                          _validateFormat(_phoneController.text);
                        });
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

  Future<void> _saveAndContinue() async {
    final number = _phoneController.text.trim();
    if (number.isEmpty) {
      ctrl.skipPhoneVerify();
      return;
    }
    // ✅ Avertissement si format incorrect — on laisse quand même continuer
    if (_formatWarning != null) {
      final confirm = await Get.dialog<bool>(AlertDialog(
        backgroundColor: const Color(0xFF11111C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Format inhabituel',
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                color: Colors.white,
                fontSize: 16)),
        content: Text(
          '$_formatWarning\n\nTu peux quand même continuer si ton numéro est correct.',
          style: const TextStyle(
              color: Color(0xFF5A5A78), fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Get.back(result: false),
              child: const Text('Corriger',
                  style: TextStyle(color: Color(0xFF5A5A78)))),
          GestureDetector(
            onTap: () => Get.back(result: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Continuer quand même',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
          ),
        ],
      ));
      if (confirm != true) return;
    }

    try {
      final uid = ctrl.currentUser.value?.id;
      if (uid != null) {
        final fullNumber = '${_selected.code}$number';
        await ctrl.savePhoneNumberOnly(fullNumber);
      }
    } catch (_) {}
    ctrl.skipPhoneVerify();
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () => Get.back(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: AppColors.surface2,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.border)),
                        child: const Icon(Icons.arrow_back_ios_rounded,
                            size: 18, color: AppColors.textPrimary),
                      ),
                    ),
                    GestureDetector(
                      onTap: ctrl.skipPhoneVerify,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Text('Passer',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),

                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.gradientPink,
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withOpacity(0.4),
                          blurRadius: 24,
                          spreadRadius: 2)
                    ],
                  ),
                  child: const Center(
                      child: Text('📱', style: TextStyle(fontSize: 36))),
                ),
                const SizedBox(height: 24),

                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Text('Ajoute ton\nnuméro 📱',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.2)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ton numéro sera sauvegardé pour sécuriser ton compte et faciliter la récupération.',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 16),

                // Badge SMS bientôt disponible
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent2.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.accent2.withOpacity(0.25)),
                  ),
                  child: const Row(children: [
                    Text('🔔', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Vérification SMS bientôt disponible — ton numéro est sauvegardé sans vérification pour l\'instant.',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                            height: 1.4),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),

                // Sélecteur pays + numéro
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _formatWarning != null
                            ? Colors.orange.withOpacity(0.6)
                            : AppColors.border,
                        width: 1.5),
                  ),
                  child: Row(children: [
                    GestureDetector(
                      onTap: _showCountryPicker,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                        decoration: const BoxDecoration(
                            border: Border(
                                right: BorderSide(color: AppColors.border))),
                        child: Row(children: [
                          Text(_selected.flag,
                              style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 6),
                          Text(_selected.code,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              size: 18, color: AppColors.textMuted),
                        ]),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(15),
                        ],
                        style: const TextStyle(
                            fontSize: 15, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: '${_selected.digits} chiffres',
                          hintStyle:
                              const TextStyle(color: AppColors.textMuted),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 16),
                        ),
                        onChanged: _validateFormat,
                      ),
                    ),
                  ]),
                ),

                // ✅ Avertissement format (orange, pas bloquant)
                if (_formatWarning != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 14, color: Colors.orange),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_formatWarning!,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.orange, height: 1.4)),
                    ),
                  ]),
                ],
                const SizedBox(height: 24),

                AuthPrimaryButton(
                  label: 'Enregistrer et continuer →',
                  onTap: _saveAndContinue,
                ),
                const SizedBox(height: 16),

                Center(
                  child: GestureDetector(
                    onTap: ctrl.skipPhoneVerify,
                    child: const Text(
                      'Je ferai ça plus tard',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
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
