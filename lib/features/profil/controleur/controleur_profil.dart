import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';

class ControleurProfil extends GetxController {
  static ControleurProfil get to => Get.find();

  final _service = SupabaseService();
  final _picker = ImagePicker();

  final Rx<UserModel?> monProfil = Rx<UserModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isUploadingPhoto = false.obs;

  final bioController = TextEditingController();
  final nomController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    chargerMonProfil();
  }

  // ─── CHARGER PROFIL ────────────────────────────────────────────

  Future<void> chargerMonProfil() async {
    isLoading.value = true;
    try {
      final profil = await _service.fetchMyProfile();
      monProfil.value = profil;
      if (profil != null) {
        nomController.text = profil.name;
        bioController.text = profil.bio ?? '';
      }
    } catch (_) {} finally {
      isLoading.value = false;
    }
  }

  // ─── CHANGER PHOTO ─────────────────────────────────────────────

  Future<void> changerPhoto() async {
    final source = await _choisirSource();
    if (source == null) return;

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked == null) return;

    isUploadingPhoto.value = true;
    try {
      final uid = supabase.auth.currentUser!.id;
      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final path = 'avatars/$uid/photo.$ext';

      // Upload sur Supabase Storage
      await supabase.storage.from('avatars').upload(
        path, file,
        fileOptions: const FileOptions(upsert: true),
      );

      // Récupère l'URL publique
      final url = supabase.storage.from('avatars').getPublicUrl(path);

      // Met à jour le profil
      await supabase.from('profiles').update({
        'photo_url': url,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);

      // Actualise localement
      monProfil.value = monProfil.value != null
        ? UserModel(
            id: monProfil.value!.id,
            name: monProfil.value!.name,
            age: monProfil.value!.age,
            bio: monProfil.value!.bio,
            photoUrl: url,
            interests: monProfil.value!.interests,
            isOnline: monProfil.value!.isOnline,
          )
        : null;

      Get.snackbar('✅ Photo mise à jour', '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF00E676).withOpacity(0.15),
        colorText: Colors.white, duration: const Duration(seconds: 2));
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de changer la photo',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white);
    } finally {
      isUploadingPhoto.value = false;
    }
  }

  Future<ImageSource?> _choisirSource() async {
    return await Get.bottomSheet<ImageSource>(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF11111C),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(color: const Color(0xFF252538),
                borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Choisir une photo',
              style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 20),
            _OptionBtn(icon: '📷', label: 'Prendre une photo',
              onTap: () => Get.back(result: ImageSource.camera)),
            const SizedBox(height: 10),
            _OptionBtn(icon: '🖼️', label: 'Choisir dans la galerie',
              onTap: () => Get.back(result: ImageSource.gallery)),
            const SizedBox(height: 10),
            _OptionBtn(icon: '❌', label: 'Annuler',
              onTap: () => Get.back(), isCancel: true),
          ],
        ),
      ),
    );
  }

  // ─── SAUVEGARDER BIO ───────────────────────────────────────────

  Future<void> sauvegarderBio() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'bio': bioController.text.trim(),
        'name': nomController.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
      Get.snackbar('✅ Profil mis à jour', '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF00E676).withOpacity(0.15),
        colorText: Colors.white);
      chargerMonProfil();
    } catch (_) {}
  }

  // ─── DÉCONNEXION ───────────────────────────────────────────────

  void deconnexion() {
    Get.dialog(
      AlertDialog(
        backgroundColor: const Color(0xFF11111C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Se déconnecter ?',
          style: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800,
            color: Colors.white, fontSize: 18)),
        content: const Text('Tu devras te reconnecter pour accéder à ton compte.',
          style: TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler',
              style: TextStyle(color: Color(0xFF5A5A78), fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: () {
              Get.back();
              AuthController.to.signOut();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Déconnexion',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void onClose() {
    bioController.dispose();
    nomController.dispose();
    super.onClose();
  }
}

class _OptionBtn extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  final bool isCancel;
  const _OptionBtn({required this.icon, required this.label,
    required this.onTap, this.isCancel = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isCancel ? Colors.transparent : const Color(0xFF191926),
          borderRadius: BorderRadius.circular(14),
          border: isCancel ? null : Border.all(color: const Color(0xFF252538)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: isCancel ? const Color(0xFF5A5A78) : Colors.white)),
          ],
        ),
      ),
    );
  }
}
