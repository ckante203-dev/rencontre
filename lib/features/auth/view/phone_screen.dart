import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

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

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  CountryCode _selected = kCountries.first; // CI par défaut

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
          final filtered = kCountries.where((c) =>
            c.name.toLowerCase().contains(search.text.toLowerCase()) ||
            c.code.contains(search.text)).toList();

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                // Handle
                Container(margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border,
                    borderRadius: BorderRadius.circular(2))),
                // Titre
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Choisir un pays',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
                ),
                // Recherche
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: search,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Rechercher...',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(Icons.search_rounded,
                        color: AppColors.textMuted),
                      filled: true, fillColor: AppColors.surface2,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (_) => setModal(() {}),
                  ),
                ),
                // Liste
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final isSelected = c.code == _selected.code && c.name == _selected.name;
                      return ListTile(
                        leading: Text(c.flag, style: const TextStyle(fontSize: 24)),
                        title: Text(c.name,
                          style: TextStyle(color: isSelected
                            ? AppColors.accent : AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400)),
                        trailing: Text(c.code,
                          style: TextStyle(color: isSelected
                            ? AppColors.accent : AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                        onTap: () {
                          setState(() => _selected = c);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Obx(() => ctrl.codeSent.value
              ? _OtpView(ctrl: ctrl)
              : _buildPhoneView(ctrl),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneView(AuthController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => Get.back(),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.surface2,
              shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.arrow_back_ios_rounded,
              size: 18, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 32),
        const Text('📱', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (b) => AppColors.gradientPink.createShader(b),
          child: const Text('Ton numéro\nde téléphone',
            style: TextStyle(fontFamily: 'Syne', fontSize: 28,
              fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
        ),
        const SizedBox(height: 8),
        const Text('On t\'envoie un code SMS pour confirmer ton identité',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5)),
        const SizedBox(height: 32),

        // Sélecteur pays + numéro
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              // Bouton pays
              GestureDetector(
                onTap: _showCountryPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AppColors.border))),
                  child: Row(
                    children: [
                      Text(_selected.flag, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 6),
                      Text(_selected.code, style: const TextStyle(fontSize: 14,
                        fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: AppColors.textMuted),
                    ],
                  ),
                ),
              ),
              // Numéro
              Expanded(
                child: TextField(
                  controller: ctrl.phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: 'Numéro de téléphone',
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  ),
                  onChanged: (_) => ctrl.clearError(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Message info Twilio
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'L\'authentification par SMS nécessite une configuration Twilio. Utilise Email ou Google pour l\'instant.',
                  style: TextStyle(fontSize: 12, color: Colors.orange, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
        const SizedBox(height: 20),

        Obx(() => AuthPrimaryButton(
          label: 'Recevoir le code SMS',
          onTap: () {
            final fullNumber = '${_selected.code}${ctrl.phoneController.text}';
            ctrl.phoneController.text = fullNumber;
            ctrl.sendOtp();
          },
          isLoading: ctrl.isLoading.value,
        )),
        const SizedBox(height: 16),

        // Retour vers email
        Center(
          child: GestureDetector(
            onTap: () => Get.back(),
            child: RichText(
              text: const TextSpan(
                text: 'Plutôt utiliser ',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                children: [
                  TextSpan(text: 'Email / Google',
                    style: TextStyle(color: AppColors.accent,
                      fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── OTP VIEW ─────────────────────────────────────────────────────

class _OtpView extends StatelessWidget {
  final AuthController ctrl;
  const _OtpView({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => ctrl.codeSent.value = false,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.surface2,
              shape: BoxShape.circle, border: Border.all(color: AppColors.border)),
            child: const Icon(Icons.arrow_back_ios_rounded,
              size: 18, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 32),
        const Text('🔐', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (b) => AppColors.gradientPink.createShader(b),
          child: const Text('Code de\nvérification',
            style: TextStyle(fontFamily: 'Syne', fontSize: 28,
              fontWeight: FontWeight.w900, color: Colors.white, height: 1.2)),
        ),
        const SizedBox(height: 8),
        Obx(() => Text('Code envoyé au ${ctrl.phoneController.text}',
          style: const TextStyle(fontSize: 14, color: AppColors.textMuted))),
        const SizedBox(height: 32),
        _OtpInputRow(controller: ctrl.otpController),
        const SizedBox(height: 16),
        Obx(() => AuthErrorMessage(message: ctrl.errorMessage.value)),
        const SizedBox(height: 20),
        Obx(() => AuthPrimaryButton(
          label: 'Vérifier le code →',
          onTap: ctrl.verifyOtp,
          isLoading: ctrl.isLoading.value,
        )),
        const SizedBox(height: 20),
        Center(
          child: GestureDetector(
            onTap: ctrl.sendOtp,
            child: RichText(
              text: const TextSpan(
                text: 'Pas reçu le code ? ',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                children: [
                  TextSpan(text: 'Renvoyer',
                    style: TextStyle(color: AppColors.accent,
                      fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── OTP INPUT ────────────────────────────────────────────────────

class _OtpInputRow extends StatefulWidget {
  final TextEditingController controller;
  const _OtpInputRow({required this.controller});

  @override
  State<_OtpInputRow> createState() => _OtpInputRowState();
}

class _OtpInputRowState extends State<_OtpInputRow> {
  final List<TextEditingController> _ctrls =
    List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (var c in _ctrls) c.dispose();
    for (var f in _nodes) f.dispose();
    super.dispose();
  }

  void _onChanged(int i, String v) {
    if (v.length == 1 && i < 5) _nodes[i + 1].requestFocus();
    else if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
    widget.controller.text = _ctrls.map((c) => c.text).join();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(6, (i) => SizedBox(
        width: 46,
        child: TextField(
          controller: _ctrls[i], focusNode: _nodes[i],
          textAlign: TextAlign.center, keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
          decoration: InputDecoration(
            counterText: '', filled: true, fillColor: AppColors.surface2,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border, width: 1.5)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 2)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onChanged: (v) => _onChanged(i, v),
        ),
      )),
    );
  }
}