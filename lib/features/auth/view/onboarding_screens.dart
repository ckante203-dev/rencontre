import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

// ─── BASE ONBOARDING LAYOUT ──────────────────────────────────────

class _OnboardBase extends StatelessWidget {
  final int step;
  final int totalSteps;
  final Color heroColor1;
  final Color heroColor2;
  final String emoji;
  final Color tagColor;
  final Color tagBg;
  final String tag;
  final String title;
  final String titleHighlight;
  final String description;
  final Widget content;
  final String buttonLabel;
  final VoidCallback onNext;
  final bool nextEnabled;
  final String? skipLabel;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;

  const _OnboardBase({
    required this.step,
    this.totalSteps = 5,
    required this.heroColor1,
    required this.heroColor2,
    required this.emoji,
    required this.tagColor,
    required this.tagBg,
    required this.tag,
    required this.title,
    required this.titleHighlight,
    required this.description,
    required this.content,
    required this.buttonLabel,
    required this.onNext,
    this.nextEnabled = true,
    this.skipLabel,
    this.onSkip,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        children: [
          SizedBox(
            height: 240,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [heroColor1, heroColor2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 80))),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, AppColors.surface],
                      ),
                    ),
                  ),
                ),
                if (onBack != null)
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16, top: 8),
                      child: GestureDetector(
                        onTap: onBack,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.arrow_back_ios_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: List.generate(
                      totalSteps,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: i == step - 1 ? 28 : 8,
                        height: 4,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          gradient: i < step ? AppColors.gradientPink : null,
                          color: i < step ? null : AppColors.border,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tagBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: tagBg.withOpacity(0.4)),
                    ),
                    child: Text(tag,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tagColor,
                            letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 10),
                  RichText(
                    text: TextSpan(
                      text: title,
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      children: [
                        WidgetSpan(
                          child: ShaderMask(
                            shaderCallback: (b) =>
                                AppColors.gradientPink.createShader(b),
                            child: Text(titleHighlight,
                                style: const TextStyle(
                                  fontFamily: 'Syne',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                )),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(description,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          height: 1.6)),
                  const SizedBox(height: 20),
                  content,
                  const SizedBox(height: 20),
                  Opacity(
                    opacity: nextEnabled ? 1.0 : 0.45,
                    child: AuthPrimaryButton(
                        label: buttonLabel,
                        onTap: nextEnabled ? onNext : () {}),
                  ),
                  if (skipLabel != null) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onSkip,
                      child: Center(
                        child: Text(skipLabel!,
                            style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w500)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── STEP 0 : DATE DE NAISSANCE (Google Sign-In uniquement) ───────

class OnboardingBirthdateScreen extends StatefulWidget {
  const OnboardingBirthdateScreen({super.key});

  @override
  State<OnboardingBirthdateScreen> createState() =>
      _OnboardingBirthdateScreenState();
}

class _OnboardingBirthdateScreenState extends State<OnboardingBirthdateScreen> {
  final _dateController = TextEditingController();
  final _nameController = TextEditingController();
  String? _errorText;
  bool _isSaving = false;
  bool _editingName = false;

  String? get _googleName =>
      Supabase.instance.client.auth.currentUser?.userMetadata?['full_name']
          as String? ??
      Supabase.instance.client.auth.currentUser?.userMetadata?['name']
          as String?;

  String? get _googlePhoto =>
      Supabase.instance.client.auth.currentUser?.userMetadata?['avatar_url']
          as String?;

  @override
  void initState() {
    super.initState();
    _nameController.text = _googleName ?? '';
  }

  @override
  void dispose() {
    _dateController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _isValid => _dateController.text.length == 10 && _errorText == null;

  void _validateDate(String value) {
    if (value.length != 10) {
      setState(() => _errorText = null);
      return;
    }
    try {
      // ✅ Extraire uniquement les chiffres puis reparser
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length != 8) {
        setState(() => _errorText = 'Format invalide — JJ/MM/AAAA');
        return;
      }
      final day = int.parse(digits.substring(0, 2));
      final month = int.parse(digits.substring(2, 4));
      final year = int.parse(digits.substring(4, 8));
      final now = DateTime.now();

      if (month < 1 || month > 12) {
        setState(() => _errorText = 'Mois invalide (01-12)');
        return;
      }
      if (day < 1 || day > 31) {
        setState(() => _errorText = 'Jour invalide (01-31)');
        return;
      }
      if (year < 1900 || year > now.year) {
        setState(() => _errorText = 'Année invalide');
        return;
      }
      final birthDate = DateTime(year, month, day);
      final age = now.year -
          birthDate.year -
          (now.month < birthDate.month ||
                  (now.month == birthDate.month && now.day < birthDate.day)
              ? 1
              : 0);
      if (age < 18) {
        setState(() => _errorText = 'Tu dois avoir au moins 18 ans');
        return;
      }
      if (age > 100) {
        setState(() => _errorText = 'Date invalide');
        return;
      }
      setState(() => _errorText = null);
    } catch (_) {
      setState(() => _errorText = 'Format invalide — JJ/MM/AAAA');
    }
  }

  // ✅ FIX DÉFINITIF : extraction chiffres depuis le formatter
  // Évite tout problème de parsing avec split('/')
  Future<void> _continuer() async {
    if (!_isValid || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      // ✅ Extraire les chiffres bruts — ignore les '/' et espaces
      final digits = _dateController.text.replaceAll(RegExp(r'[^0-9]'), '');
      debugPrint('📅 Digits bruts: "$digits" (length: ${digits.length})');

      if (digits.length != 8) {
        Get.snackbar('Erreur', 'Date invalide. Entre JJ/MM/AAAA.',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
        return;
      }

      final day = int.parse(digits.substring(0, 2));
      final month = int.parse(digits.substring(2, 4));
      final year = int.parse(digits.substring(4, 8));

      debugPrint('📅 day=$day month=$month year=$year');

      final now = DateTime.now();
      final birthDate = DateTime(year, month, day);
      int age = now.year - birthDate.year;
      if (now.month < birthDate.month ||
          (now.month == birthDate.month && now.day < birthDate.day)) {
        age--;
      }

      debugPrint('🎂 Age: $age');

      if (age < 18 || age > 100) {
        Get.snackbar('Erreur', 'Âge invalide ($age ans).',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
        return;
      }

      // ✅ Format ISO garanti : AAAA-MM-JJ avec padding
      final birthdateStr = '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}';

      debugPrint('📅 birthdateStr: "$birthdateStr"');

      final user = Supabase.instance.client.auth.currentUser;
      final uid = user?.id;

      if (uid == null) {
        Get.snackbar('Erreur', 'Session expirée. Reconnecte-toi.',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
        Get.offAllNamed('/splash');
        return;
      }

      final nom = _nameController.text.trim().isEmpty
          ? (_googleName ?? 'Utilisateur')
          : _nameController.text.trim();

      // Essayer update, puis insert si profil inexistant
      try {
        final updated = await Supabase.instance.client.from('profiles').update({
          'name': nom,
          'birthdate': birthdateStr,
          'age': age,
          'updated_at': now.toUtc().toIso8601String(),
        }).eq('id', uid).select('id');
        // ✅ Un update sur 0 ligne ne lève pas d'erreur : sans ce test
        // l'insert de secours ne s'exécutait jamais.
        if ((updated as List).isEmpty) throw Exception('profil absent');
        debugPrint('✅ Update OK');
      } catch (_) {
        await Supabase.instance.client.from('profiles').insert({
          'id': uid,
          'name': nom,
          'email': user?.email ?? '',
          'photo_url': user?.userMetadata?['avatar_url'] ?? '',
          'photo_urls': [],
          'interests': [],
          'bio': '',
          'birthdate': birthdateStr,
          'age': age,
          'gender': 'non précisé',
          'looking_for': null,
          'is_online': true,
          'onboarding_complete': false,
          'phone_verified': false,
          'followers_count': 0,
          'following_count': 0,
          'matches_count': 0,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        });
        debugPrint('✅ Insert OK');
      }

      Get.offNamed('/onboarding/photo');
    } catch (e) {
      debugPrint('❌ Birthdate error: $e');
      Get.snackbar(
          'Erreur',
          e.toString().length > 100
              ? e.toString().substring(0, 100)
              : e.toString(),
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white,
          duration: const Duration(seconds: 6));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            if (_editingName) setState(() => _editingName = false);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),

                // ── Aperçu profil Google ──────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.accent.withOpacity(0.4), width: 2),
                      ),
                      child: ClipOval(
                        child: _googlePhoto != null && _googlePhoto!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _googlePhoto!,
                                fit: BoxFit.cover,
                                placeholder: (_, __) =>
                                    _InitialAvatar(name: _nameController.text),
                                errorWidget: (_, __, ___) =>
                                    _InitialAvatar(name: _nameController.text),
                              )
                            : _InitialAvatar(name: _nameController.text),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _editingName
                              ? TextField(
                                  controller: _nameController,
                                  autofocus: true,
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.textPrimary),
                                  decoration: InputDecoration(
                                    hintText: 'Ton prénom',
                                    hintStyle:
                                        TextStyle(color: AppColors.textMuted),
                                    border: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: AppColors.accent, width: 1.5),
                                    ),
                                    focusedBorder: UnderlineInputBorder(
                                      borderSide: BorderSide(
                                          color: AppColors.accent, width: 2),
                                    ),
                                    isDense: true,
                                    contentPadding:
                                        const EdgeInsets.only(bottom: 4),
                                  ),
                                  onSubmitted: (_) =>
                                      setState(() => _editingName = false),
                                )
                              : GestureDetector(
                                  onTap: () =>
                                      setState(() => _editingName = true),
                                  child: Text(
                                    _nameController.text.isNotEmpty
                                        ? _nameController.text
                                        : (_googleName ?? 'Utilisateur'),
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary),
                                  ),
                                ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.online.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.online.withOpacity(0.3)),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 11, color: AppColors.online),
                              SizedBox(width: 4),
                              Text('Importé depuis Google',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.online,
                                      fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _editingName = !_editingName),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _editingName
                              ? AppColors.accent.withOpacity(0.15)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: _editingName
                                  ? AppColors.accent.withOpacity(0.4)
                                  : AppColors.border),
                        ),
                        child: Icon(
                          _editingName
                              ? Icons.check_rounded
                              : Icons.edit_rounded,
                          size: 16,
                          color: _editingName
                              ? AppColors.accent
                              : AppColors.textMuted,
                        ),
                      ),
                    ),
                  ]),
                ),

                if (!_editingName) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Appuie sur ✏️ pour modifier ton prénom',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted.withOpacity(0.6)),
                    ),
                  ),
                ],
                const SizedBox(height: 32),

                const Text('🎂', style: TextStyle(fontSize: 40)),
                const SizedBox(height: 16),
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Text('Ta date de\nnaissance',
                      style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.2)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Nous avons besoin de ta date de naissance pour vérifier que tu as au moins 18 ans.',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textMuted, height: 1.6),
                ),
                const SizedBox(height: 28),

                // ── Champ date ────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: _errorText != null
                            ? AppColors.error
                            : _isValid
                                ? AppColors.online
                                : AppColors.border,
                        width: 1.5),
                  ),
                  child: Row(children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 16),
                      child: Text('🎂', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _dateController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          _DateInputFormatter(),
                        ],
                        style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textPrimary,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          hintText: 'JJ / MM / AAAA',
                          hintStyle: TextStyle(
                              color: AppColors.textMuted,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w400,
                              fontSize: 15),
                          border: InputBorder.none,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 18, horizontal: 4),
                        ),
                        onChanged: _validateDate,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _isValid
                          ? Icon(Icons.check_circle_rounded,
                              color: AppColors.online, size: 22)
                          : _errorText != null
                              ? Icon(Icons.cancel_rounded,
                                  color: AppColors.error, size: 22)
                              : const SizedBox.shrink(),
                    ),
                  ]),
                ),

                if (_errorText != null) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.warning_rounded,
                        size: 14, color: AppColors.error),
                    const SizedBox(width: 6),
                    Text(_errorText!,
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.error,
                            fontWeight: FontWeight.w500)),
                  ]),
                ],
                const SizedBox(height: 32),

                GestureDetector(
                  onTap: _isValid && !_isSaving ? _continuer : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: _isValid && !_isSaving
                          ? AppColors.gradientPink
                          : null,
                      color: _isValid && !_isSaving ? null : AppColors.surface2,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _isValid && !_isSaving
                          ? [
                              BoxShadow(
                                  color: AppColors.accent.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6))
                            ]
                          : [],
                    ),
                    child: Center(
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              _isValid
                                  ? 'Continuer →'
                                  : 'Entre ta date de naissance',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _isValid
                                      ? Colors.white
                                      : AppColors.textMuted),
                            ),
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

// ─── STEP 1 : PHOTO (obligatoire) ────────────────────────────────

class OnboardingPhotoScreen extends StatefulWidget {
  const OnboardingPhotoScreen({super.key});
  @override
  State<OnboardingPhotoScreen> createState() => _OnboardingPhotoScreenState();
}

class _OnboardingPhotoScreenState extends State<OnboardingPhotoScreen> {
  File? _photo;
  bool _isUploading = false;
  final _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      if (picked != null) setState(() => _photo = File(picked.path));
    } catch (e) {
      debugPrint('Image picker error: $e');
    }
  }

  void _showSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        gradient: AppColors.gradientPink,
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 22)),
                title: Text('Prendre une photo',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: Icon(Icons.photo_library_rounded,
                        color: AppColors.textPrimary, size: 22)),
                title: Text('Choisir depuis la galerie',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ La photo est désormais obligatoire — aucun bypass possible.
  Future<void> _continuer() async {
    if (_photo == null) return;
    setState(() => _isUploading = true);
    try {
      final ctrl = Get.find<AuthController>();
      final uid = ctrl.currentUser.value?.id;
      if (uid != null) {
        final path = 'avatars/$uid/profile.jpg';
        await Supabase.instance.client.storage.from('avatars').upload(
            path, _photo!,
            fileOptions:
                const FileOptions(upsert: true, contentType: 'image/jpeg'));
        final url =
            Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
        await ctrl.updateProfile(photoUrl: url);
      }
    } catch (e) {
      debugPrint('Upload photo error: $e');
      return; // ✅ en cas d'erreur d'upload, on reste bloqué sur l'écran
    } finally {
      setState(() => _isUploading = false);
    }
    Get.offNamed('/onboarding/identity');
  }

  @override
  Widget build(BuildContext context) {
    final existingPhoto = Supabase.instance.client.auth.currentUser
        ?.userMetadata?['avatar_url'] as String?;
    final hasGooglePhoto = existingPhoto != null && existingPhoto.isNotEmpty;

    return _OnboardBase(
      step: 1,
      heroColor1: const Color(0xFF1a0a2e),
      heroColor2: const Color(0xFF2d0a1e),
      emoji: '📸',
      tagColor: AppColors.accent,
      tagBg: AppColors.accent.withValues(alpha: 0.1),
      tag: '✨ Étape 1 / 5',
      title: 'Ajoute ta ',
      titleHighlight: 'photo',
      description:
          'Les profils avec photo obtiennent 5× plus de matchs. Choisis une belle photo de toi !',
      buttonLabel: _isUploading
          ? 'Envoi...'
          : (_photo != null ? 'Continuer →' : 'Choisir une photo'),
      nextEnabled: !_isUploading,
      // ✅ Sans photo, le bouton ouvre le sélecteur au lieu de passer à l'étape suivante.
      onNext: _isUploading
          ? () {}
          : (_photo != null ? _continuer : _showSourcePicker),
      onBack: null,
      // ✅ Plus de skipLabel / onSkip — impossible de passer cette étape sans photo.
      content: Column(
        children: [
          Center(
            child: GestureDetector(
              onTap: _showSourcePicker,
              child: Stack(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _photo != null
                              ? AppColors.accent
                              : AppColors.border,
                          width: _photo != null ? 3 : 1.5),
                      boxShadow: _photo != null
                          ? [
                              BoxShadow(
                                  color: AppColors.accent.withOpacity(0.4),
                                  blurRadius: 24,
                                  spreadRadius: 2)
                            ]
                          : null,
                    ),
                    child: ClipOval(
                      child: _photo != null
                          ? Image.file(_photo!, fit: BoxFit.cover)
                          : Container(
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      colors: [
                                    AppColors.accent,
                                    AppColors.accent2
                                  ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight)),
                              child: const Center(
                                  child: Icon(Icons.person_rounded,
                                      size: 60, color: Colors.white54))),
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                            gradient: AppColors.gradientPink,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.surface, width: 2)),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 16, color: Colors.white)),
                  ),
                  if (_isUploading)
                    Positioned.fill(
                        child: Container(
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.5)),
                            child: Center(
                                child: CircularProgressIndicator(
                                    color: AppColors.accent, strokeWidth: 2)))),
                ],
              ),
            ),
          ),
          if (hasGooglePhoto && _photo == null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.online.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.online.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.online),
                SizedBox(width: 8),
                Expanded(
                    child: Text(
                        'Ta photo Google a été importée ✅ Tu peux en choisir une autre ou continuer.',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.online,
                            height: 1.4))),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── STEP 2 : JE SUIS / JE RECHERCHE ────────────────────────────

class OnboardingIdentityScreen extends StatefulWidget {
  const OnboardingIdentityScreen({super.key});
  @override
  State<OnboardingIdentityScreen> createState() =>
      _OnboardingIdentityScreenState();
}

class _OnboardingIdentityScreenState extends State<OnboardingIdentityScreen> {
  String? _gender;
  String? _lookingFor;
  bool get _canContinue => _gender != null && _lookingFor != null;

  static const _genders = [
    {'value': 'homme', 'emoji': '👨', 'label': 'Homme'},
    {'value': 'femme', 'emoji': '👩', 'label': 'Femme'},
  ];
  static const _lookingForOptions = [
    {'value': 'hommes', 'emoji': '👨', 'label': 'Des hommes'},
    {'value': 'femmes', 'emoji': '👩', 'label': 'Des femmes'},
    {'value': 'tout le monde', 'emoji': '💑', 'label': 'Tout le monde'},
  ];

  Future<void> _continuer() async {
    if (!_canContinue) return;
    final ctrl = Get.find<AuthController>();
    await ctrl.saveOnboardingData(gender: _gender, lookingFor: _lookingFor);
    Get.offNamed('/onboarding/interests');
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardBase(
      step: 2,
      heroColor1: const Color(0xFF1a0a2e),
      heroColor2: const Color(0xFF0a1a2e),
      emoji: '💫',
      tagColor: AppColors.accent,
      tagBg: AppColors.accent.withValues(alpha: 0.1),
      tag: '💫 Étape 2 / 5',
      title: 'Qui ',
      titleHighlight: 'es-tu ?',
      description:
          'Ces infos permettent de te montrer les bons profils et d\'éviter les mauvaises rencontres.',
      buttonLabel: _canContinue ? 'Continuer →' : 'Choisis tes préférences',
      nextEnabled: _canContinue,
      onNext: _continuer,
      onBack: () => Get.offNamed('/onboarding/photo'),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('JE SUIS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Row(
            children: _genders.map((g) {
          final isSelected = _gender == g['value'];
          return Expanded(
              child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: GestureDetector(
              onTap: () => setState(() => _gender = g['value'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.gradientPink : null,
                  color: isSelected ? null : AppColors.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isSelected ? Colors.transparent : AppColors.border,
                      width: 1.5),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: AppColors.accent.withOpacity(0.3),
                              blurRadius: 16,
                              spreadRadius: 1)
                        ]
                      : null,
                ),
                child: Column(children: [
                  Text(g['emoji'] as String,
                      style: const TextStyle(fontSize: 32)),
                  const SizedBox(height: 8),
                  Text(g['label'] as String,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary)),
                ]),
              ),
            ),
          ));
        }).toList()),
        const SizedBox(height: 24),
        Text('JE RECHERCHE',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
                letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Column(
            children: _lookingForOptions.map((opt) {
          final isSelected = _lookingFor == opt['value'];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () => setState(() => _lookingFor = opt['value'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.gradientPink : null,
                  color: isSelected ? null : AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isSelected ? Colors.transparent : AppColors.border,
                      width: 1.5),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: AppColors.accent.withOpacity(0.25),
                              blurRadius: 12)
                        ]
                      : null,
                ),
                child: Row(children: [
                  Text(opt['emoji'] as String,
                      style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 14),
                  Text(opt['label'] as String,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : AppColors.textPrimary)),
                  const Spacer(),
                  if (isSelected)
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 20),
                ]),
              ),
            ),
          );
        }).toList()),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent3.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent3.withOpacity(0.2)),
          ),
          child: Row(children: [
            Text('🔒', style: TextStyle(fontSize: 14)),
            SizedBox(width: 8),
            Expanded(
                child: Text(
                    'Tu ne verras que les profils compatibles avec tes préférences.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        height: 1.4))),
          ]),
        ),
      ]),
    );
  }
}

// ─── STEP 3 : INTÉRÊTS ───────────────────────────────────────────

class OnboardingInterestsScreen extends StatefulWidget {
  const OnboardingInterestsScreen({super.key});
  @override
  State<OnboardingInterestsScreen> createState() =>
      _OnboardingInterestsScreenState();
}

class _OnboardingInterestsScreenState extends State<OnboardingInterestsScreen> {
  final Set<String> _selected = {};
  static const _interests = [
    '🎵 Musique',
    '🏔️ Rando',
    '🎨 Art',
    '📸 Photo',
    '🍕 Food',
    '✈️ Voyage',
    '🎮 Jeux vidéo',
    '🏋️ Sport',
    '📚 Lecture',
    '🎭 Théâtre',
    '🌿 Nature',
    '💃 Danse',
    '🎸 Concerts',
    '🏄 Surf',
    '🧘 Yoga',
    '🍷 Gastronomie',
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AuthController>();
    final enoughSelected = _selected.length >= 3;
    return _OnboardBase(
      step: 3,
      heroColor1: const Color(0xFF0a1a2e),
      heroColor2: const Color(0xFF0a2d1e),
      emoji: '🎯',
      tagColor: AppColors.accent3,
      tagBg: const Color(0x1A00F5D4),
      tag: '🎯 Étape 3 / 5',
      title: 'Tes ',
      titleHighlight: 'passions',
      description:
          'Choisis au moins 3 centres d\'intérêt pour trouver des personnes compatibles.',
      buttonLabel: enoughSelected
          ? 'Continuer (${_selected.length}) →'
          : 'Choisis 3 min.',
      nextEnabled: enoughSelected,
      onNext: () async {
        await ctrl.saveOnboardingData(interests: _selected.toList());
        Get.offNamed('/onboarding/permissions');
      },
      onBack: () => Get.offNamed('/onboarding/identity'),
      content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _interests.map((interest) {
            final isSelected = _selected.contains(interest);
            return GestureDetector(
              onTap: () => setState(() {
                isSelected
                    ? _selected.remove(interest)
                    : _selected.add(interest);
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected ? AppColors.gradientPink : null,
                  color: isSelected ? null : AppColors.surface2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: isSelected ? Colors.transparent : AppColors.border,
                      width: 1.5),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                              color: AppColors.accent.withOpacity(0.25),
                              blurRadius: 12,
                              spreadRadius: 1)
                        ]
                      : null,
                ),
                child: Text(interest,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color:
                            isSelected ? Colors.white : AppColors.textMuted)),
              ),
            );
          }).toList()),
    );
  }
}

// ─── STEP 4 : PERMISSIONS (dernière étape → /main directement) ──

class OnboardingPermissionsScreen extends StatelessWidget {
  const OnboardingPermissionsScreen({super.key});

  // ✅ Termine l'onboarding et va directement à l'accueil.
  // Plus d'écran "bienvenue" ni d'étape numéro de téléphone.
  Future<void> _finish() async {
    final ctrl = Get.find<AuthController>();
    await ctrl.saveOnboardingData(complete: true);
    Get.offAllNamed('/main');
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardBase(
      step: 4,
      totalSteps: 4,
      heroColor1: const Color(0xFF0a2e1a),
      heroColor2: const Color(0xFF2e2a0a),
      emoji: '📍',
      tagColor: AppColors.accent2,
      tagBg: AppColors.accent2.withValues(alpha: 0.1),
      tag: '📍 Étape 4 / 4',
      title: 'Active ta ',
      titleHighlight: 'position',
      description:
          'Pour voir les personnes autour de toi en temps réel, on a besoin de quelques autorisations.',
      buttonLabel: 'Terminer →',
      onNext: _finish,
      onBack: () => Get.offNamed('/onboarding/interests'),
      skipLabel: 'Pas maintenant',
      onSkip: _finish,
      content: Column(children: [
        _PermissionCard(
            icon: '📍',
            color: AppColors.accent,
            title: 'Localisation',
            description:
                'Voir les profils à proximité et apparaître sur la carte.',
            isRequired: true),
        const SizedBox(height: 10),
        _PermissionCard(
            icon: '🔔',
            color: AppColors.accent2,
            title: 'Notifications',
            description: 'Reçois les matchs, messages et snaps instantanément.',
            isRequired: false),
        const SizedBox(height: 10),
        _PermissionCard(
            icon: '📷',
            color: AppColors.accent3,
            title: 'Caméra & Photos',
            description: 'Pour prendre et envoyer des snaps éphémères.',
            isRequired: false),
      ]),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final String icon, title, description;
  final Color color;
  final bool isRequired;
  const _PermissionCard(
      {required this.icon,
      required this.color,
      required this.title,
      required this.description,
      required this.isRequired});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14)),
            child: Center(
                child: Text(icon, style: const TextStyle(fontSize: 22)))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            if (isRequired) ...[
              const SizedBox(width: 6),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('Requis',
                      style: TextStyle(
                          fontSize: 9,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700))),
            ],
          ]),
          const SizedBox(height: 3),
          Text(description,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textMuted, height: 1.4)),
        ])),
      ]),
    );
  }
}

// ─── WIDGETS COMMUNS ─────────────────────────────────────────────
// ℹ️ L'ancien "STEP 5 : PRÊT !" (OnboardingReadyScreen, _StatItem,
// _FeatureRow) a été retiré : l'onboarding se termine désormais à
// l'étape Permissions et va directement sur /main.

class _InitialAvatar extends StatelessWidget {
  final String name;
  const _InitialAvatar({required this.name});
  @override
  Widget build(BuildContext context) {
    return Container(
        color: AppColors.surface2,
        child: Center(
            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54))));
  }
}

// ✅ FIX DÉFINITIF : formatter utilise substring sur les chiffres bruts
// Pas de split('/') qui peut introduire des espaces ou caractères parasites
class _DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    // Extraire uniquement les chiffres
    final digits = next.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buf = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buf.write('/');
      buf.write(digits[i]);
    }
    final str = buf.toString();
    return TextEditingValue(
        text: str, selection: TextSelection.collapsed(offset: str.length));
  }
}
