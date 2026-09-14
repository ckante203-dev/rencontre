import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/core/theme/theme_controller.dart';
import 'package:rencontre/core/utils/app_routes.dart';

class ControleurProfil extends GetxController {
  static ControleurProfil get to => Get.find();

  final _service = SupabaseService();
  final _picker = ImagePicker();

  final Rx<UserModel?> monProfil = Rx<UserModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isUploadingPhoto = false.obs;
  final RxBool isSaving = false.obs;

  // ✅ Statut premium (badge certifié)
  final RxBool isPremium = false.obs;

  final nomController = TextEditingController();
  final bioController = TextEditingController();
  final tailleController = TextEditingController();
  final poidsController = TextEditingController();
  final RxList<String> selectedInterests = <String>[].obs;
  final Rx<DateTime?> birthdate = Rx<DateTime?>(null);
  final RxString selectedMorphologie = ''.obs;
  final RxString selectedLieuRencontre = ''.obs;

  final RxString selectedGender = ''.obs;
  final RxString selectedLookingFor = ''.obs;
  final RxBool showBirthdate = true.obs;
  final RxBool notifMessages = true.obs;
  final RxBool notifNearby = true.obs;
  final RxBool notifStories = true.obs;
  final RxBool notifAnnonces = true.obs;
  final RxBool notifSon = true.obs;
  final RxBool profilPublic = true.obs;
  final RxBool showDistance = true.obs;
  final RxString selectedTheme = 'dark'.obs;

  final RxList<Map<String, dynamic>> blockedProfiles =
      <Map<String, dynamic>>[].obs;
  final RxBool isLoadingBlocked = false.obs;

  // ✅ Galerie de photos multiples (défilables sur le profil public)
  static const int maxPhotos = 4;
  final RxList<String> photoUrls = <String>[].obs;

  RealtimeChannel? _profilChannel;

  static const List<String> genders = ['homme', 'femme'];
  static const List<String> lookingForOptions = [
    'hommes',
    'femmes',
    'tout le monde',
  ];
  static const List<String> morphologies = [
    'Mince',
    'Athlétique',
    'Normale',
    'Ronde',
    'Musclée'
  ];
  static const List<String> lieuxRencontre = [
    'Café',
    'Restaurant',
    'Parc',
    'Cinéma',
    'Sport',
    'Voyage',
    'Soirée',
    'Domicile',
    'Travail',
    'En ligne'
  ];
  static const List<Map<String, String>> allInterests = [
    {'emoji': '🌿', 'label': 'Nature'},
    {'emoji': '🍕', 'label': 'Food'},
    {'emoji': '🎵', 'label': 'Musique'},
    {'emoji': '🥾', 'label': 'Rando'},
    {'emoji': '📸', 'label': 'Photo'},
    {'emoji': '🎮', 'label': 'Gaming'},
    {'emoji': '✈️', 'label': 'Voyage'},
    {'emoji': '📚', 'label': 'Lecture'},
    {'emoji': '🏋️', 'label': 'Sport'},
    {'emoji': '🎨', 'label': 'Art'},
    {'emoji': '🍷', 'label': 'Œnologie'},
    {'emoji': '🐾', 'label': 'Animaux'},
    {'emoji': '🎬', 'label': 'Cinéma'},
    {'emoji': '🧘', 'label': 'Yoga'},
    {'emoji': '🏄', 'label': 'Surf'},
    {'emoji': '🎤', 'label': 'Chant'},
    {'emoji': '💃', 'label': 'Danse'},
    {'emoji': '🌙', 'label': 'Astronomie'},
    {'emoji': '👗', 'label': 'Mode'},
    {'emoji': '🚴', 'label': 'Vélo'},
  ];

  @override
  void onInit() {
    super.onInit();
    _setOnlineEtCharger();
    _ecouterMonProfil();
  }

  // ✅ setOnline(true) AVANT de lire le profil
  // → évite "Hors ligne" affiché sur la page profil au chargement
  Future<void> _setOnlineEtCharger() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      try {
        await supabase
            .from('profiles')
            .update({
              'is_online': true,
              'last_seen': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', uid)
            .timeout(const Duration(seconds: 8)); // ✅
      } catch (_) {}
    }
    await chargerMonProfil();
  }

  Future<void> chargerMonProfil() async {
    isLoading.value = true;
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final data = await supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (isClosed) return;
      if (data == null) return;

      final isOnline = SupabaseService.isReallyOnline(
        data['is_online'],
        data['last_seen'],
      );

      final fetchedProfile =
          await _service.fetchMyProfile().timeout(const Duration(seconds: 10));

      if (isClosed) return;

      monProfil.value = fetchedProfile?.copyWith(isOnline: isOnline);

      nomController.text = data['name'] ?? '';
      bioController.text = data['bio'] ?? '';
      tailleController.text =
          data['taille'] != null ? data['taille'].toString() : '';
      poidsController.text =
          data['poids'] != null ? data['poids'].toString() : '';
      selectedGender.value = data['gender'] ?? '';
      selectedLookingFor.value = data['looking_for'] ?? '';
      selectedMorphologie.value = data['morphologie'] ?? '';
      selectedLieuRencontre.value = data['lieu_rencontre'] ?? '';
      selectedInterests.value = List<String>.from(data['interests'] ?? []);
      showBirthdate.value = data['show_birthdate'] ?? true;
      notifMessages.value = data['notif_messages'] ?? true;
      notifNearby.value = data['notif_nearby'] ?? true;
      notifStories.value = data['notif_stories'] ?? true;
      notifAnnonces.value = data['notif_annonces'] ?? true;
      notifSon.value = data['notif_son'] ?? true;
      profilPublic.value = data['is_public'] ?? true;
      showDistance.value = data['show_distance'] ?? true;
      selectedTheme.value = data['theme'] ?? 'dark';
      isPremium.value = data['is_premium'] ?? false;
      photoUrls.value = List<String>.from(data['photo_urls'] ?? []);
      if (data['birthdate'] != null) {
        birthdate.value = DateTime.tryParse(data['birthdate'].toString());
      }
    } catch (e) {
      debugPrint('chargerMonProfil error: $e');
    } finally {
      if (!isClosed) isLoading.value = false;
    }
  }

  // ✅ Écoute Realtime les mises à jour de ton propre profil
  // → is_online + last_seen + is_premium se mettent à jour automatiquement
  void _ecouterMonProfil() {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    _profilChannel = supabase
        .channel('mon_profil_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) async {
            // ✅ FIX : le canal peut recevoir un événement juste après
            // dispose (course entre unsubscribe et un message déjà en vol)
            if (isClosed) return;
            final data = payload.newRecord;
            // ✅ Recalculer isReallyOnline à chaque update Realtime
            final isOnline = SupabaseService.isReallyOnline(
              data['is_online'],
              data['last_seen'],
            );
            // ✅ Mettre à jour le statut premium en direct
            isPremium.value = data['is_premium'] ?? isPremium.value;
            if (monProfil.value != null) {
              monProfil.value = monProfil.value!.copyWith(isOnline: isOnline);
            } else {
              final fetched = await _service.fetchMyProfile();
              if (isClosed) return;
              monProfil.value = fetched;
            }
          },
        )
        .subscribe();
  }

  // ─── PHOTO PRINCIPALE ───────────────────────────────────────────

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
      final path = '$uid/photo.$ext';
      await supabase.storage.from('avatars').upload(
            path,
            file,
            fileOptions: const FileOptions(upsert: true),
          );
      final baseUrl = supabase.storage.from('avatars').getPublicUrl(path);
      await supabase.from('profiles').update({
        'photo_url': baseUrl,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
      monProfil.value = await _service.fetchMyProfile();
      _snackSuccess('Photo mise à jour');
    } catch (e) {
      debugPrint('changerPhoto error: $e');
      _snackError('Impossible de changer la photo : $e');
    } finally {
      isUploadingPhoto.value = false;
    }
  }

  Future<void> supprimerPhoto() async {
    final confirm = await Get.dialog<bool>(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Supprimer la photo ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white)),
      content: const Text('Ta photo de profil sera supprimée définitivement.',
          style: TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Supprimer',
                style: TextStyle(
                    color: Color(0xFFFF3CAC), fontWeight: FontWeight.w700))),
      ],
    ));
    if (confirm != true) return;
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('profiles').update({
        'photo_url': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
      if (monProfil.value != null) {
        monProfil.value = monProfil.value!.copyWith(clearPhoto: true);
      }
      _snackSuccess('Photo supprimée');
    } catch (e) {
      _snackError('Impossible de supprimer la photo : $e');
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFF252538),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Photo de profil',
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 20),
          _SheetBtn(
              icon: '📷',
              label: 'Prendre une photo',
              onTap: () => Get.back(result: ImageSource.camera)),
          const SizedBox(height: 10),
          _SheetBtn(
              icon: '🖼️',
              label: 'Choisir dans la galerie',
              onTap: () => Get.back(result: ImageSource.gallery)),
          const SizedBox(height: 10),
          _SheetBtn(
              icon: '❌',
              label: 'Annuler',
              onTap: () => Get.back(),
              isCancel: true),
        ]),
      ),
    );
  }

  // ─── GALERIE DE PHOTOS (défilable sur le profil) ─────────────────

  Future<void> ajouterPhotoProfil() async {
    if (photoUrls.length >= maxPhotos) {
      _snackError('Maximum $maxPhotos photos');
      return;
    }
    final source = await _choisirSource();
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (picked == null) return;
    isUploadingPhoto.value = true;
    try {
      final uid = supabase.auth.currentUser!.id;
      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      final path = '$uid/$fileName';
      await supabase.storage.from('profile-photos').upload(path, file);
      final url = supabase.storage.from('profile-photos').getPublicUrl(path);
      photoUrls.add(url);
      await _sauvegarderPhotoUrls();
      _snackSuccess('Photo ajoutée');
    } catch (e) {
      debugPrint('ajouterPhotoProfil error: $e');
      _snackError('Impossible d\'ajouter la photo : $e');
    } finally {
      isUploadingPhoto.value = false;
    }
  }

  Future<void> supprimerPhotoProfil(int index) async {
    if (index < 0 || index >= photoUrls.length) return;
    final url = photoUrls[index];
    try {
      final uid = supabase.auth.currentUser!.id;
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      final bucketIdx = segments.indexOf('profile-photos');
      if (bucketIdx != -1 && bucketIdx + 1 < segments.length) {
        final storagePath = segments.sublist(bucketIdx + 1).join('/');
        await supabase.storage.from('profile-photos').remove([storagePath]);
      } else {
        debugPrint('supprimerPhotoProfil: chemin introuvable pour $url');
      }
    } catch (e) {
      debugPrint('supprimerPhotoProfil storage error: $e');
    }
    photoUrls.removeAt(index);
    await _sauvegarderPhotoUrls();
    _snackSuccess('Photo supprimée');
  }

  void reordonnerPhotos(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= photoUrls.length) return;
    if (newIndex < 0 || newIndex >= photoUrls.length) return;
    final item = photoUrls.removeAt(oldIndex);
    photoUrls.insert(newIndex, item);
    _sauvegarderPhotoUrls();
  }

  Future<void> _sauvegarderPhotoUrls() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'photo_urls': photoUrls.toList(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      debugPrint('_sauvegarderPhotoUrls error: $e');
      _snackError('Erreur de synchronisation : $e');
    }
  }

  // ─── MODIFIER INFOS ─────────────────────────────────────────────

  void toggleInterest(String label) {
    if (selectedInterests.contains(label)) {
      selectedInterests.remove(label);
    } else {
      if (selectedInterests.length >= 10) {
        _snackError('Maximum 10 intérêts');
        return;
      }
      selectedInterests.add(label);
    }
  }

  void setMorphologie(String v) => selectedMorphologie.value = v;
  void setLieuRencontre(String v) => selectedLieuRencontre.value = v;

  Future<void> choisirDateNaissance(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: birthdate.value ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 80),
      lastDate: DateTime(now.year - 18),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFFFF3CAC),
            onPrimary: Colors.white,
            surface: Color(0xFF11111C),
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: const Color(0xFF11111C),
        ),
        child: child!,
      ),
    );
    if (picked != null) birthdate.value = picked;
  }

  String get birthdateLabel {
    final d = birthdate.value;
    if (d == null) return 'Non renseignée';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  int get calculatedAge {
    final d = birthdate.value;
    if (d == null) return monProfil.value?.age ?? 18;
    final now = DateTime.now();
    int age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age;
  }

  Future<void> sauvegarderInfos() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      _snackError('Utilisateur non connecté');
      return;
    }
    if (nomController.text.trim().isEmpty) {
      _snackError('Le prénom est obligatoire');
      return;
    }
    isSaving.value = true;
    try {
      final updates = <String, dynamic>{
        'name': nomController.text.trim(),
        'bio': bioController.text.trim().isEmpty
            ? null
            : bioController.text.trim(),
        'interests': selectedInterests.toList(),
        'morphologie': selectedMorphologie.value.isEmpty
            ? null
            : selectedMorphologie.value,
        'lieu_rencontre': selectedLieuRencontre.value.isEmpty
            ? null
            : selectedLieuRencontre.value,
        'looking_for':
            selectedLookingFor.value.isEmpty ? null : selectedLookingFor.value,
        'updated_at': DateTime.now().toIso8601String(),
      };
      final tailleStr = tailleController.text.trim();
      if (tailleStr.isNotEmpty) {
        final t = int.tryParse(tailleStr);
        if (t == null || t < 100 || t > 250) {
          _snackError('Taille invalide (100–250 cm)');
          isSaving.value = false;
          return;
        }
        updates['taille'] = t;
      } else {
        updates['taille'] = null;
      }
      final poidsStr = poidsController.text.trim();
      if (poidsStr.isNotEmpty) {
        final p = int.tryParse(poidsStr);
        if (p == null || p < 30 || p > 300) {
          _snackError('Poids invalide (30–300 kg)');
          isSaving.value = false;
          return;
        }
        updates['poids'] = p;
      } else {
        updates['poids'] = null;
      }
      if (birthdate.value != null) {
        updates['birthdate'] =
            birthdate.value!.toIso8601String().split('T').first;
      }
      await supabase.from('profiles').update(updates).eq('id', uid);
      await chargerMonProfil();
      // ✅ FIX : redirige vers l'accueil et affiche le message de
      // confirmation AVANT la navigation (le snackbar GetX vit dans un
      // overlay indépendant de la pile de navigation, il survit au
      // changement de route).
      _snackSuccess('Informations mises à jour');
      Get.until((route) => route.settings.name == AppRoutes.main); // ✅
    } catch (e) {
      _snackError(
          'Erreur : ${e.toString().substring(0, e.toString().length.clamp(0, 120))}');
    } finally {
      isSaving.value = false;
    }
  }

  // ─── PARAMÈTRES ─────────────────────────────────────────────────

  void setGender(String v) => selectedGender.value = v;
  void setLookingFor(String v) => selectedLookingFor.value = v;
  void setTheme(String v) => selectedTheme.value = v;

  Future<void> sauvegarderParametres() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      _snackError('Utilisateur non connecté');
      return;
    }
    isSaving.value = true;
    try {
      await supabase.from('profiles').update({
        'gender': selectedGender.value.isEmpty ? null : selectedGender.value,
        'looking_for':
            selectedLookingFor.value.isEmpty ? null : selectedLookingFor.value,
        'show_birthdate': showBirthdate.value,
        'notif_messages': notifMessages.value,
        'notif_nearby': notifNearby.value,
        'notif_stories': notifStories.value,
        'notif_annonces': notifAnnonces.value,
        'notif_son': notifSon.value,
        'is_public': profilPublic.value,
        'show_distance': showDistance.value,
        'theme': selectedTheme.value,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);

      // ✅ FIX : on diffère le changement de thème + la navigation à la
      // frame suivante. Changer le thème (touche un Obx global) juste
      // avant Get.offAllNamed (qui reconstruit tout l'écran d'accueil,
      // plein de nouveaux Obx) faisait chevaucher deux reconstructions
      // dans la même frame → "setState() or markNeedsBuild() called
      // during build".
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await ThemeController.to.setTheme(selectedTheme.value);
        _snackSuccess('Paramètres sauvegardés');
        Get.until((route) => route.settings.name == AppRoutes.main); // ✅
      });
    } catch (e) {
      _snackError(
          'Erreur : ${e.toString().substring(0, e.toString().length.clamp(0, 120))}');
    } finally {
      isSaving.value = false;
    }
  }

  // ─── EMAIL / MOT DE PASSE ────────────────────────────────────────

  Future<void> modifierEmail(String newEmail) async {
    if (newEmail.trim().isEmpty || !GetUtils.isEmail(newEmail.trim())) {
      _snackError('Email invalide');
      return;
    }
    isSaving.value = true;
    try {
      await supabase.auth.updateUser(UserAttributes(email: newEmail.trim()));
      _snackSuccess('Email mis à jour — vérifie ta boîte mail pour confirmer');
      Get.back();
    } catch (e) {
      _snackError('Impossible de modifier l\'email : $e');
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> modifierMotDePasse(String newPassword) async {
    if (newPassword.length < 6) {
      _snackError('Minimum 6 caractères requis');
      return;
    }
    isSaving.value = true;
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
      _snackSuccess('Mot de passe mis à jour');
      Get.back();
    } catch (e) {
      _snackError('Impossible de modifier le mot de passe : $e');
    } finally {
      isSaving.value = false;
    }
  }

  // ─── BLOQUER / SIGNALER ──────────────────────────────────────────

  Future<void> bloquerProfil(String targetId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await supabase
          .from('profiles')
          .select('blocked_users')
          .eq('id', uid)
          .maybeSingle();
      final current = List<String>.from(data?['blocked_users'] ?? []);
      if (!current.contains(targetId)) {
        current.add(targetId);
        await supabase.from('profiles').update({
          'blocked_users': current,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', uid);
      }
      if (Get.isRegistered<ChatListController>()) {
        final chatCtrl = Get.find<ChatListController>();
        chatCtrl.conversations.removeWhere((c) => c.userId == targetId);
        chatCtrl.update();
      }
      if (Get.isRegistered<HomeController>()) {
        Get.find<HomeController>().removeUser(targetId);
      }
      await chargerProfilsBloques();
      _snackSuccess('Profil bloqué');
      Get.until((route) => route.settings.name == '/main');
    } catch (e) {
      _snackError('Impossible de bloquer ce profil');
    }
  }

  Future<void> signalerProfil(String targetId, String reason) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('reports').insert({
        'reporter_id': uid,
        'reported_id': targetId,
        'reason': reason,
        'created_at': DateTime.now().toIso8601String(),
      });
      _snackSuccess('Signalement envoyé. Merci !');
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _snackError('Tu as déjà signalé ce profil');
      } else {
        _snackError('Impossible d\'envoyer le signalement');
      }
    } catch (e) {
      _snackError('Impossible d\'envoyer le signalement');
    }
  }

  // ─── PROFILS BLOQUÉS ────────────────────────────────────────────

  Future<void> chargerProfilsBloques() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    isLoadingBlocked.value = true;
    try {
      final data = await supabase
          .from('profiles')
          .select('blocked_users')
          .eq('id', uid)
          .maybeSingle();
      final blockedIds = List<String>.from(data?['blocked_users'] ?? []);
      if (blockedIds.isEmpty) {
        blockedProfiles.clear();
        return;
      }
      final profiles = await supabase
          .from('profiles')
          .select('id, name, photo_url')
          .inFilter('id', blockedIds);
      blockedProfiles.value = List<Map<String, dynamic>>.from(profiles);
    } catch (e) {
      debugPrint('chargerProfilsBloques error: $e');
    } finally {
      isLoadingBlocked.value = false;
    }
  }

  Future<void> debloquerProfil(String blockedId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await supabase
          .from('profiles')
          .select('blocked_users')
          .eq('id', uid)
          .maybeSingle();
      final current = List<String>.from(data?['blocked_users'] ?? []);
      current.remove(blockedId);
      await supabase.from('profiles').update({
        'blocked_users': current,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
      blockedProfiles.removeWhere((p) => p['id'] == blockedId);
      _snackSuccess('Utilisateur débloqué');
    } catch (e) {
      _snackError('Impossible de débloquer : $e');
    }
  }

  Future<void> toutDebloquer() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final confirmed = await Get.dialog<bool>(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tout débloquer ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white)),
      content: const Text('Tous les profils bloqués seront débloqués.',
          style: TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
        GestureDetector(
            onTap: () => Get.back(result: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('Débloquer tout',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            )),
      ],
    ));
    if (confirmed != true) return;
    try {
      await supabase.from('profiles').update({
        'blocked_users': [],
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uid);
      blockedProfiles.clear();
      _snackSuccess('Tous les profils débloqués');
    } catch (e) {
      _snackError('Impossible de débloquer');
    }
  }

  // ─── UTILITAIRES ────────────────────────────────────────────────

  void copierNumero(String numero) {
    Clipboard.setData(ClipboardData(text: numero));
    _snackSuccess('Numéro copié : $numero');
  }

  Future<void> ouvrirWhatsApp() async {
    const phone = '2250720457945';
    final msg = Uri.encodeComponent(
        'Bonjour SnapMeet, je vous contacte depuis l\'application.');
    final uri = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snackError('WhatsApp non disponible');
    }
  }

  // ─── DÉCONNEXION ────────────────────────────────────────────────

  void deconnexion() {
    Get.dialog(AlertDialog(
      backgroundColor: const Color(0xFF11111C),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Se déconnecter ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18)),
      content: const Text('Tu devras te reconnecter pour accéder à ton compte.',
          style: TextStyle(color: Color(0xFF5A5A78), fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: const Text('Annuler',
                style: TextStyle(color: Color(0xFF5A5A78)))),
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
                borderRadius: BorderRadius.circular(12)),
            child: const Text('Déconnexion',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  void _snackSuccess(String msg) => Get.snackbar('✅ $msg', '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFF00E676).withOpacity(0.15),
      colorText: Colors.white,
      duration: const Duration(seconds: 2));

  void _snackError(String msg) => Get.snackbar('Erreur', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: const Color(0xFF13131A),
      colorText: Colors.white,
      duration: const Duration(seconds: 4));

  @override
  void onClose() {
    nomController.dispose();
    bioController.dispose();
    tailleController.dispose();
    poidsController.dispose();
    _profilChannel?.unsubscribe();
    super.onClose();
  }
}

// ─── SHEET BTN ──────────────────────────────────────────────────

class _SheetBtn extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  final bool isCancel;
  const _SheetBtn(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.isCancel = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isCancel ? Colors.transparent : const Color(0xFF191926),
          borderRadius: BorderRadius.circular(14),
          border: isCancel ? null : Border.all(color: const Color(0xFF252538)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCancel ? const Color(0xFF5A5A78) : Colors.white)),
        ]),
      ),
    );
  }
}
