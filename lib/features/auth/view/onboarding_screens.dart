import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/auth/widget/auth_widgets.dart';

// ─── BASE ONBOARDING LAYOUT ──────────────────────────────────────

class _OnboardBase extends StatelessWidget {
  final int step;         // 1-4
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
  final String? skipLabel;
  final VoidCallback? onSkip;

  final VoidCallback? onBack;

  const _OnboardBase({
    required this.step,
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
          // Hero
          SizedBox(
            height: 260,
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
                Center(child: Text(emoji,
                  style: const TextStyle(fontSize: 90))),
                // Fade to surface
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, AppColors.surface],
                      ),
                    ),
                  ),
                ),
                // Bouton retour
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16, top: 8),
                    child: Row(
                      children: [
                        if (onBack != null)
                          GestureDetector(
                            onTap: onBack,
                            child: Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Icon(Icons.arrow_back_ios_rounded,
                                size: 16, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step dots
                  Row(
                    children: List.generate(4, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: i == step - 1 ? 28 : 8,
                      height: 4,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: i < step
                          ? AppColors.gradientPink
                          : null,
                        color: i < step ? null : AppColors.border,
                      ),
                    )),
                  ),
                  const SizedBox(height: 16),

                  // Tag
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: tagBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: tagBg.withOpacity(0.4)),
                    ),
                    child: Text(tag,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: tagColor, letterSpacing: 0.5)),
                  ),
                  const SizedBox(height: 10),

                  // Title
                  RichText(
                    text: TextSpan(
                      text: title,
                      style: const TextStyle(
                        fontFamily: 'Syne', fontSize: 24, fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary, height: 1.2,
                      ),
                      children: [
                        WidgetSpan(child: ShaderMask(
                          shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                          child: Text(titleHighlight,
                            style: const TextStyle(
                              fontFamily: 'Syne', fontSize: 24, fontWeight: FontWeight.w900,
                              color: Colors.white,
                            )),
                        )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(description,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.6)),
                  const SizedBox(height: 20),

                  content,
                  const SizedBox(height: 20),

                  AuthPrimaryButton(label: buttonLabel, onTap: onNext),
                  if (skipLabel != null) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: onSkip,
                      child: Center(
                        child: Text(skipLabel!,
                          style: const TextStyle(fontSize: 13,
                            color: AppColors.textMuted, fontWeight: FontWeight.w500)),
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

// ─── STEP 1 : PHOTO ──────────────────────────────────────────────

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
        requestFullMetadata: false, // Fix Android gallery
      );
      if (picked != null) {
        setState(() => _photo = File(picked.path));
      }
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
              Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.camera_alt_rounded,
                    color: Colors.white, size: 22)),
                title: const Text('Prendre une photo',
                  style: TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.camera); },
              ),
              ListTile(
                leading: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border)),
                  child: const Icon(Icons.photo_library_rounded,
                    color: AppColors.textPrimary, size: 22)),
                title: const Text('Choisir depuis la galerie',
                  style: TextStyle(color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
                onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _continuer() async {
    if (_photo == null) {
      // Passe sans photo
      Get.offNamed('/onboarding/interests');
      return;
    }
    setState(() => _isUploading = true);
    try {
      final ctrl = Get.find<AuthController>();
      final uid = ctrl.currentUser.value?.id;
      if (uid != null) {
        final path = 'avatars/$uid/profile.jpg';
        await Supabase.instance.client.storage
          .from('avatars').upload(path, _photo!,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'));
        final url = Supabase.instance.client.storage
          .from('avatars').getPublicUrl(path);
        await ctrl.updateProfile(photoUrl: url);
      }
    } catch (e) {
      debugPrint('Upload photo error: $e');
    } finally {
      setState(() => _isUploading = false);
    }
    Get.offNamed('/onboarding/interests');
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardBase(
      step: 1,
      heroColor1: const Color(0xFF1a0a2e),
      heroColor2: const Color(0xFF2d0a1e),
      emoji: '📸',
      tagColor: AppColors.accent,
      tagBg: const Color(0x1AFF3CAC),
      tag: '✨ Étape 1 / 4',
      title: 'Ajoute ta ',
      titleHighlight: 'photo',
      description: 'Les profils avec photo obtiennent 5× plus de matchs. Choisis une belle photo de toi !',
      buttonLabel: _isUploading ? 'Envoi...' : (_photo != null ? 'Continuer →' : 'Choisir une photo'),
      onNext: _isUploading ? () {} : _continuer,
      skipLabel: "Passer pour l'instant",
      onSkip: () => Get.offNamed('/onboarding/interests'),
      content: Center(
        child: GestureDetector(
          onTap: _showSourcePicker,
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 130, height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _photo != null ? AppColors.accent : AppColors.border,
                    width: _photo != null ? 3 : 1.5),
                  boxShadow: _photo != null ? [BoxShadow(
                    color: AppColors.accent.withOpacity(0.4),
                    blurRadius: 24, spreadRadius: 2)] : null,
                ),
                child: ClipOval(
                  child: _photo != null
                    ? Image.file(_photo!, fit: BoxFit.cover)
                    : Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.accent2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight)),
                        child: const Center(
                          child: Icon(Icons.person_rounded,
                            size: 60, color: Colors.white54))),
                ),
              ),
              Positioned(
                bottom: 4, right: 4,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                    size: 16, color: Colors.white),
                ),
              ),
              if (_isUploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withOpacity(0.5)),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accent, strokeWidth: 2)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── STEP 2 : INTÉRÊTS ───────────────────────────────────────────

class OnboardingInterestsScreen extends StatefulWidget {
  const OnboardingInterestsScreen({super.key});

  @override
  State<OnboardingInterestsScreen> createState() => _OnboardingInterestsScreenState();
}

class _OnboardingInterestsScreenState extends State<OnboardingInterestsScreen> {
  final Set<String> _selected = {};

  static const _interests = [
    '🎵 Musique', '🏔️ Rando', '🎨 Art', '📸 Photo',
    '🍕 Food', '✈️ Voyage', '🎮 Jeux vidéo', '🏋️ Sport',
    '📚 Lecture', '🎭 Théâtre', '🌿 Nature', '💃 Danse',
    '🎸 Concerts', '🏄 Surf', '🧘 Yoga', '🍷 Gastronomie',
  ];

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AuthController>();
    final enoughSelected = _selected.length >= 3;

    return _OnboardBase(
      step: 2,
      heroColor1: const Color(0xFF0a1a2e),
      heroColor2: const Color(0xFF0a2d1e),
      emoji: '🎯',
      tagColor: AppColors.accent3,
      tagBg: Color(0x1A00F5D4),
      tag: '🎯 Étape 2 / 4',
      title: 'Tes ',
      titleHighlight: 'passions',
      description: 'Choisis au moins 3 centres d\'intérêt pour trouver des personnes compatibles avec toi.',
      buttonLabel: enoughSelected ? 'Continuer (${_selected.length}) →' : 'Choisis 3 min.',
      onNext: enoughSelected
        ? () async {
            await ctrl.saveOnboardingData(interests: _selected.toList());
            Get.offNamed('/onboarding/permissions');
          }
        : () {},
      content: Wrap(
        spacing: 8, runSpacing: 8,
        children: _interests.map((interest) {
          final isSelected = _selected.contains(interest);
          return GestureDetector(
            onTap: () => setState(() {
              isSelected ? _selected.remove(interest) : _selected.add(interest);
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.gradientPink : null,
                color: isSelected ? null : AppColors.surface2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? Colors.transparent : AppColors.border,
                  width: 1.5,
                ),
                boxShadow: isSelected ? [
                  BoxShadow(color: AppColors.accent.withOpacity(0.25),
                    blurRadius: 12, spreadRadius: 1),
                ] : null,
              ),
              child: Text(interest,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textMuted,
                )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── STEP 3 : PERMISSIONS ────────────────────────────────────────

class OnboardingPermissionsScreen extends StatelessWidget {
  const OnboardingPermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _OnboardBase(
      step: 3,
      heroColor1: const Color(0xFF0a2e1a),
      heroColor2: const Color(0xFF2e2a0a),
      emoji: '📍',
      tagColor: AppColors.accent2,
      tagBg: Color(0x1A7B2FFF),
      tag: '📍 Étape 3 / 4',
      title: 'Active ta ',
      titleHighlight: 'position',
      description: 'Pour voir les personnes autour de toi en temps réel, on a besoin de quelques autorisations.',
      buttonLabel: 'Autoriser et continuer →',
      onNext: () => Get.offNamed('/onboarding/ready'),
      skipLabel: 'Pas maintenant',
      onSkip: () => Get.offNamed('/onboarding/ready'),
      content: Column(
        children: [
          _PermissionCard(
            icon: '📍',
            color: AppColors.accent,
            title: 'Localisation',
            description: 'Voir les profils à proximité et apparaître sur la carte en temps réel.',
            isRequired: true,
          ),
          const SizedBox(height: 10),
          _PermissionCard(
            icon: '🔔',
            color: AppColors.accent2,
            title: 'Notifications',
            description: 'Reçois les matchs, messages et snaps instantanément.',
            isRequired: false,
          ),
          const SizedBox(height: 10),
          _PermissionCard(
            icon: '📷',
            color: AppColors.accent3,
            title: 'Caméra & Photos',
            description: 'Pour prendre et envoyer des snaps éphémères.',
            isRequired: false,
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final String icon;
  final Color color;
  final String title;
  final String description;
  final bool isRequired;

  const _PermissionCard({
    required this.icon, required this.color, required this.title,
    required this.description, required this.isRequired,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                    if (isRequired) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Requis',
                          style: TextStyle(fontSize: 9, color: AppColors.accent,
                            fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(description,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── STEP 4 : PRÊT ! ─────────────────────────────────────────────

class OnboardingReadyScreen extends StatelessWidget {
  const OnboardingReadyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<AuthController>();

    return _OnboardBase(
      step: 4,
      heroColor1: const Color(0xFF1a0a2e),
      heroColor2: const Color(0xFF0a1a2e),
      emoji: '🎉',
      tagColor: AppColors.online,
      tagBg: Color(0x1A00E676),
      tag: '🎉 Tout est prêt !',
      title: 'Bienvenue sur ',
      titleHighlight: 'SnapMeet !',
      description: 'Ton profil est créé. Découvre les personnes autour de toi, envoie des snaps et crée des connexions authentiques.',
      buttonLabel: 'Découvrir l\'app 🚀',
      onNext: () async {
        await ctrl.saveOnboardingData(complete: true);
        Get.offAllNamed('/main');
      },
      content: Column(
        children: [
          // Stats card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatItem(value: '247', label: 'Personnes\nà proximité', color: AppColors.accent),
                Container(width: 1, height: 40, color: AppColors.border),
                _StatItem(value: '12', label: 'Stories\nactives', color: AppColors.accent2),
                Container(width: 1, height: 40, color: AppColors.border),
                _StatItem(value: '3', label: 'Matchs\npotentiels', color: AppColors.accent3),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Features
          _FeatureRow(icon: '🗺️', label: 'Voir les gens sur la carte en temps réel'),
          const SizedBox(height: 8),
          _FeatureRow(icon: '📸', label: 'Envoyer des snaps éphémères'),
          const SizedBox(height: 8),
          _FeatureRow(icon: '💬', label: 'Chatter et créer des connexions'),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatItem({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (b) => LinearGradient(
            colors: [color, color.withOpacity(0.7)]).createShader(b),
          child: Text(value,
            style: const TextStyle(fontFamily: 'Syne', fontSize: 26,
              fontWeight: FontWeight.w900, color: Colors.white)),
        ),
        const SizedBox(height: 4),
        Text(label, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, color: AppColors.textMuted, height: 1.4)),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final String icon;
  final String label;
  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ],
    );
  }
}