import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/services/moderation_service.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/core/theme/app_palette.dart';
import 'package:rencontre/core/theme/theme_controller.dart';
import 'package:rencontre/core/utils/app_routes.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class ControleurProfil extends GetxController {
  static ControleurProfil get to => Get.find();

  /// Premium = profil (webhook RevenueCat) OU RevenueCat en direct : juste
  /// après un achat, le profil n'est pas encore à jour.
  static bool estPremiumMaintenant() {
    final profil = Get.isRegistered<ControleurProfil>() &&
        Get.find<ControleurProfil>().isPremium.value;
    final rc = Get.isRegistered<RevenueCatService>() &&
        Get.find<RevenueCatService>().isPremium.value;
    return profil || rc;
  }

  final _service = SupabaseService();
  final _picker = ImagePicker();

  final Rx<UserModel?> monProfil = Rx<UserModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isUploadingPhoto = false.obs;
  final RxBool isSaving = false.obs;

  // ✅ Statut premium (badge certifié)
  final RxBool isPremium = false.obs;

  final nomController = TextEditingController();
  final usernameController = TextEditingController();
  // Nom d'utilisateur actuel (affiché « @… » sur le profil)
  final RxString monUsername = ''.obs;
  // Valeur saisie (pour l'affichage réactif du champ)
  final RxString usernameText = ''.obs;
  // null = pas encore vérifié / en cours ; true = libre ; false = pris ou invalide
  final Rx<bool?> usernameDispo = Rx<bool?>(null);
  final RxBool verifUsername = false.obs;
  int _usernameSeq = 0;
  static final _usernameRegex = RegExp(r'^[a-z0-9_.]{3,20}$');
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
    PackageInfo.fromPlatform().then((i) {
      versionApp.value = i.version;
    }).catchError((_) {});
  }

  // ─── AIDE & ABONNEMENT (Paramètres) ─────────────────────────────

  // Laisser vide = l'entrée est masquée dans les Paramètres.
  static const String urlConfidentialite =
      'https://supportsnapmeet-jpg.github.io/zamu-legal/politique-confidentialite.html';
  static const String emailContact = 'support.snapmeet@gmail.com';
  static const String _packageAndroid = 'com.vybestyle.zamu';

  final RxString versionApp = ''.obs;

  Future<void> ouvrirLien(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _snackError('Impossible d\'ouvrir le lien');
    }
  }

  Future<void> contacterSupport() async {
    try {
      final ok = await launchUrl(Uri.parse(
          'mailto:$emailContact?subject=${Uri.encodeComponent('Zamu - aide')}'));
      if (!ok) throw Exception();
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: emailContact));
      _snackSuccess('Adresse copiée : $emailContact');
    }
  }

  /// Gestion de l'abonnement = page Abonnements de Google Play.
  Future<void> gererAbonnement() => ouvrirLien(
      'https://play.google.com/store/account/subscriptions?package=$_packageAndroid');

  void ouvrirPaywall() {
    // RevenueCat pas encore configuré → pas de paywall (évite un crash
    // sur Get.find<RevenueCatService>() dans l'écran paywall).
    if (!Get.isRegistered<RevenueCatService>()) {
      _snackError('Premium sera bientôt disponible');
      return;
    }
    Get.toNamed(AppRoutes.paywall);
  }

  Future<void> restaurerAchats() async {
    if (!Get.isRegistered<RevenueCatService>()) {
      _snackError('Service d\'achat indisponible pour le moment');
      return;
    }
    final premium = await Get.find<RevenueCatService>().restorePurchases();
    if (premium) {
      isPremium.value = true;
      _snackSuccess('Abonnement Premium restauré');
    } else {
      _snackError('Aucun abonnement actif trouvé sur ce compte Google');
    }
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

      if (data == null) {
        debugPrint('chargerMonProfil: aucune ligne profile trouvée pour $uid');
        return;
      }

      final isOnline = SupabaseService.isReallyOnline(
        data['is_online'],
        data['last_seen'],
      );

      // ✅ Un seul appel réseau : on construit le UserModel directement
      // à partir de `data` au lieu de refaire un fetchMyProfile() redondant.
      monProfil.value =
          _service.profileToUser(data).copyWith(isOnline: isOnline);

      // Formulaire / contrôleurs
      nomController.text = data['name']?.toString() ?? '';
      monUsername.value = data['username']?.toString() ?? '';
      usernameController.text = monUsername.value;
      usernameText.value = monUsername.value;
      usernameDispo.value = null;
      bioController.text = data['bio']?.toString() ?? '';
      tailleController.text = data['taille']?.toString() ?? '';
      poidsController.text = data['poids']?.toString() ?? '';

      // Sélections sécurisées
      selectedGender.value = data['gender']?.toString() ?? '';
      selectedLookingFor.value = data['looking_for']?.toString() ?? '';
      selectedMorphologie.value = data['morphologie']?.toString() ?? '';
      selectedLieuRencontre.value = data['lieu_rencontre']?.toString() ?? '';

      // ✅ Toujours réinitialisé (sinon l'ancienne valeur restait si null)
      selectedInterests.value = data['interests'] is List
          ? List<String>.from(data['interests'])
          : <String>[];

      // Booléens sécurisés
      showBirthdate.value = data['show_birthdate'] ?? true;
      notifMessages.value = data['notif_messages'] ?? true;
      notifNearby.value = data['notif_nearby'] ?? true;
      notifStories.value = data['notif_stories'] ?? true;
      notifSon.value = data['notif_son'] ?? true;
      NotificationService.sonActive = notifSon.value;
      profilPublic.value = data['is_public'] ?? true;
      showDistance.value = data['show_distance'] ?? true;
      isPremium.value = data['is_premium'] ?? false;

      // Thème et photos
      // Thème retiré (ex. gold, forest) → on affiche celui réellement actif.
      final theme = data['theme']?.toString();
      selectedTheme.value = AppPalettes.all.containsKey(theme)
          ? theme!
          : ThemeController.to.palette.value.id;
      photoUrls.value = data['photo_urls'] is List
          ? List<String>.from(data['photo_urls'])
          : <String>[];

      // Date de naissance sécurisée
      birthdate.value = data['birthdate'] != null
          ? DateTime.tryParse(data['birthdate'].toString())
          : null;
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
      // ✅ Nom unique à chaque envoi : une photo refusée ou en attente
      // n'écrase plus la photo actuelle (et plus de souci de cache).
      final path = '$uid/photo_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await supabase.storage.from('avatars').upload(path, file);
      final url = supabase.storage.from('avatars').getPublicUrl(path);
      // ✅ Modération : c'est le serveur qui pose la photo sur le profil
      // si elle est acceptée.
      final result = await ModerationService.photoProfil(url);
      monProfil.value = await _service.fetchMyProfile();
      switch (result) {
        case ModerationResult.approved:
          _snackSuccess('Photo mise à jour');
          break;
        case ModerationResult.pending:
          _snackSuccess(ModerationService.messageAttente);
          break;
        case ModerationResult.rejected:
          _snackError(ModerationService.messageRefus);
          break;
        case ModerationResult.full:
        case ModerationResult.error:
          _snackError('Impossible de vérifier la photo. Réessaie.');
          break;
      }
    } catch (e) {
      debugPrint('changerPhoto error: $e');
      _snackError('Impossible de changer la photo : $e');
    } finally {
      isUploadingPhoto.value = false;
    }
  }

  Future<void> supprimerPhoto() async {
    final confirm = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Supprimer la photo ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white)),
      content: Text('Ta photo de profil sera supprimée définitivement.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Supprimer',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
      ],
    ));
    if (confirm != true) return;
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('profiles').update({
        'photo_url': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
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
      // ✅ Modération : le serveur ajoute la photo à la galerie si elle
      // est acceptée ; on relit ensuite la galerie depuis la base.
      final result = await ModerationService.photoGalerie(url);
      await _rechargerPhotoUrls();
      switch (result) {
        case ModerationResult.approved:
          _snackSuccess('Photo ajoutée');
          break;
        case ModerationResult.pending:
          _snackSuccess(ModerationService.messageAttente);
          break;
        case ModerationResult.rejected:
          _snackError(ModerationService.messageRefus);
          break;
        case ModerationResult.full:
          _snackError('Maximum $maxPhotos photos (en comptant celles en '
              'cours de vérification)');
          break;
        case ModerationResult.error:
          _snackError('Impossible de vérifier la photo. Réessaie.');
          break;
      }
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

  Future<void> _rechargerPhotoUrls() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final data = await supabase
          .from('profiles')
          .select('photo_urls')
          .eq('id', uid)
          .maybeSingle();
      photoUrls.value = data?['photo_urls'] is List
          ? List<String>.from(data!['photo_urls'])
          : <String>[];
    } catch (e) {
      debugPrint('_rechargerPhotoUrls error: $e');
    }
  }

  Future<void> _sauvegarderPhotoUrls() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'photo_urls': photoUrls.toList(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    // ✅ Bornes au jour près (18 ans aujourd'hui inclus, 100 ans comme à
    // l'inscription) et date initiale ramenée dans l'intervalle : sinon
    // assertion/plantage pour quelqu'un qui a eu 18 ans cette année.
    final firstDate = DateTime(now.year - 100, now.month, now.day);
    final lastDate = DateTime(now.year - 18, now.month, now.day);
    var initialDate = birthdate.value ?? DateTime(now.year - 25);
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.accent,
            onPrimary: Colors.white,
            surface: AppColors.surface,
            onSurface: Colors.white,
          ),
          dialogBackgroundColor: AppColors.surface,
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

  // ─── NOM D'UTILISATEUR ───────────────────────────────────────────

  /// Vérifie en direct la disponibilité (mêmes règles qu'à l'inscription).
  Future<void> verifierUsername(String value) async {
    final u = value.trim().toLowerCase();
    final seq = ++_usernameSeq;
    if (u == monUsername.value) {
      usernameDispo.value = true;
      verifUsername.value = false;
      return;
    }
    if (!_usernameRegex.hasMatch(u)) {
      usernameDispo.value = false;
      verifUsername.value = false;
      return;
    }
    verifUsername.value = true;
    usernameDispo.value = null;
    try {
      final libre = await supabase
          .rpc('username_available', params: {'p_username': u});
      if (seq != _usernameSeq) return;
      usernameDispo.value = libre == true;
    } catch (_) {
      if (seq != _usernameSeq) return;
      // Réseau : on laisse la contrainte unique en base trancher à l'enregistrement
      usernameDispo.value = null;
    } finally {
      if (seq == _usernameSeq) verifUsername.value = false;
    }
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
    final username = usernameController.text.trim().toLowerCase();
    final usernameChange = username != monUsername.value;
    if (usernameChange) {
      if (!_usernameRegex.hasMatch(username)) {
        _snackError(
            'Nom d\'utilisateur invalide (3-20 caractères : lettres, chiffres, . ou _)');
        return;
      }
      if (usernameDispo.value == false) {
        _snackError('Ce nom d\'utilisateur est déjà pris');
        return;
      }
    }
    isSaving.value = true;
    try {
      final updates = <String, dynamic>{
        'name': nomController.text.trim(),
        if (usernameChange) 'username': username,
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    } on PostgrestException catch (e) {
      // 23505 = contrainte unique : nom pris entre la vérification et l'enregistrement
      if (e.code == '23505') {
        usernameDispo.value = false;
        _snackError('Ce nom d\'utilisateur est déjà pris');
      } else {
        _snackError('Erreur : ${e.message}');
      }
    } catch (e) {
      _snackError(
          'Erreur : ${e.toString().substring(0, e.toString().length.clamp(0, 120))}');
    } finally {
      isSaving.value = false;
    }
  }

  // ─── PARAMÈTRES ─────────────────────────────────────────────────

  void setGender(String v) {
    selectedGender.value = v;
    _enregistrerReglage('gender', v.isEmpty ? null : v);
  }

  void setLookingFor(String v) {
    selectedLookingFor.value = v;
    _enregistrerReglage('looking_for', v.isEmpty ? null : v);
  }

  /// Thème : appliqué tout de suite (ThemeController l'enregistre aussi
  /// dans profiles.theme).
  void setTheme(String v) {
    selectedTheme.value = v;
    ThemeController.to.setTheme(v);
  }

  /// ✅ Interrupteurs des paramètres : enregistrés dès qu'on les touche
  /// (avant, un réglage était perdu si on quittait sans « Sauvegarder »).
  void majReglage(RxBool reglage, String colonne, bool valeur) {
    reglage.value = valeur;
    if (colonne == 'notif_son') NotificationService.sonActive = valeur;
    _enregistrerReglage(colonne, valeur, annuler: () {
      reglage.value = !valeur;
      if (colonne == 'notif_son') NotificationService.sonActive = !valeur;
    });
  }

  Future<void> _enregistrerReglage(String colonne, Object? valeur,
      {VoidCallback? annuler}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        colonne: valeur,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      debugPrint('_enregistrerReglage($colonne) error: $e');
      annuler?.call();
      _snackError('Réglage non enregistré, vérifie ta connexion');
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
      // ✅ Le dialog est déjà fermé par la vue : un 2e Get.back() fermait
      // l'écran Paramètres.
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
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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
        'created_at': DateTime.now().toUtc().toIso8601String(),
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Tout débloquer ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white)),
      content: Text('Tous les profils bloqués seront débloqués.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
            onTap: () => Get.back(result: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accent2]),
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
        'updated_at': DateTime.now().toUtc().toIso8601String(),
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
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Se déconnecter ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18)),
      content: Text('Tu devras te reconnecter pour accéder à ton compte.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            Get.back();
            AuthController.to.signOut();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [AppColors.accent, AppColors.accent2]),
                borderRadius: BorderRadius.circular(12)),
            child: const Text('Déconnexion',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  void supprimerCompte() {
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Supprimer ton compte ?',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18)),
      content: Text(
          'Cette action est irréversible. Toutes tes données (profil, photos, messages, matchs) seront définitivement supprimées.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler',
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () async {
            Get.back();
            isSaving.value = true;
            try {
              await supabase.functions.invoke('delete-account');
              await AuthController.to.signOut();
              Get.offAllNamed('/login');
            } catch (e) {
              _snackError('Impossible de supprimer le compte : $e');
            } finally {
              isSaving.value = false;
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12)),
            child: const Text('Supprimer définitivement',
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
      backgroundColor: AppColors.online.withOpacity(0.15),
      colorText: Colors.white,
      duration: const Duration(seconds: 2));

  void _snackError(String msg) => Get.snackbar('Erreur', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white,
      duration: const Duration(seconds: 4));

  @override
  void onClose() {
    nomController.dispose();
    usernameController.dispose();
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
          border: isCancel ? null : Border.all(color: AppColors.surface2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCancel ? AppColors.textMuted : Colors.white)),
        ]),
      ),
    );
  }
}
