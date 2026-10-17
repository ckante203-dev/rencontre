import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:rencontre/features/profil/vue/ecran_profil.dart';
import 'package:get_storage/get_storage.dart';
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
  /// ⚡ Un Boost en cours donne aussi tous les droits Premium (le serveur
  /// applique la même règle : premium_effectif, migration 043).
  static bool estPremiumMaintenant() {
    final profil = Get.isRegistered<ControleurProfil>() &&
        Get.find<ControleurProfil>().isPremium.value;
    final rc = Get.isRegistered<RevenueCatService>() &&
        Get.find<RevenueCatService>().isPremium.value;
    final boost = Get.isRegistered<HomeController>() &&
        Get.find<HomeController>().boostActif.value;
    return profil || rc || boost;
  }

  final _service = SupabaseService();
  final _picker = ImagePicker();

  final Rx<UserModel?> monProfil = Rx<UserModel?>(null);
  final RxBool isLoading = true.obs;
  final RxBool isUploadingPhoto = false.obs;
  final RxBool isSaving = false.obs;

  // ✅ Statut premium (badge Premium)
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
  // Premium : les autres ne voient pas « Lu » sur mes conversations
  final RxBool lecturesMasquees = false.obs;
  // Profil enrichi (SQL 051)
  final metierController = TextEditingController();
  final etudesController = TextEditingController();
  final RxList<String> languesChoisies = <String>[].obs;
  final RxList<Map<String, String>> questionsChoisies = <Map<String, String>>[].obs;

  static const List<String> languesDisponibles = [
    'Français', 'Anglais', 'Dioula', 'Baoulé', 'Bété', 'Sénoufo', 'Agni',
    'Yacouba', 'Arabe', 'Espagnol', 'Portugais', 'Allemand', 'Chinois',
  ];

  static const List<String> questionsDisponibles = [
    'Mon dimanche idéal…',
    'Ce qui me fait craquer…',
    'Je suis fier(e) de…',
    'Mon plat préféré…',
    'Le meilleur endroit d\'Abidjan…',
    'Un rendez-vous parfait, c\'est…',
    'Ma chanson du moment…',
    'On va bien s\'entendre si…',
    'Mon talent caché…',
    'Ce que je cherche ici…',
  ];

  void basculerLangue(String langue) {
    languesChoisies.contains(langue)
        ? languesChoisies.remove(langue)
        : languesChoisies.add(langue);
  }

  /// Ajoute ou remplace la réponse à une question (3 au maximum)
  void definirQuestion(String question, String reponse) {
    final r = reponse.trim();
    final i = questionsChoisies.indexWhere((e) => e['q'] == question);
    if (r.isEmpty) {
      if (i >= 0) questionsChoisies.removeAt(i);
      return;
    }
    final texte = r.substring(0, r.length.clamp(0, 200));
    if (i >= 0) {
      questionsChoisies[i] = {'q': question, 'r': texte};
    } else if (questionsChoisies.length < 3) {
      questionsChoisies.add({'q': question, 'r': texte});
    }
  }

  final RxString selectedGender = ''.obs;
  final RxString selectedLookingFor = ''.obs;
  final RxBool showBirthdate = true.obs;
  final RxBool notifMessages = true.obs;
  final RxBool notifNearby = true.obs;
  final RxBool notifStories = true.obs;
  final RxBool notifSon = true.obs;
  // ⭐ Alertes : favori en ligne / proche / dans ma ville
  final RxBool notifFavoris = true.obs;
  // Recherche par pseudo dans Messages : désactivé = introuvable
  final RxBool trouvableParPseudo = true.obs;
  // Compte privé : désactivé = personne ne peut m'envoyer de demande d'ami
  final RxBool accepteDemandesAmi = true.obs;
  // Statut « Dispo maintenant »
  final RxnString dispoTexte = RxnString();
  final Rxn<DateTime> dispoJusqua = Rxn<DateTime>();
  bool get dispoActive =>
      (dispoTexte.value ?? '').isNotEmpty &&
      dispoJusqua.value != null &&
      dispoJusqua.value!.isAfter(DateTime.now());
  final RxBool profilPublic = true.obs;
  final RxBool showDistance = true.obs;
  final RxString selectedTheme = 'zamu'.obs;

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
  // Où se rencontrer (jusqu'à 3, enregistrés « Chez moi, Maquis » dans
  // profiles.lieu_rencontre — même colonne qu'avant)
  static const List<String> lieuxRencontre = [
    'Chez moi',
    'Chez toi',
    'Maquis',
    'Restaurant',
    'Café',
    'Soirée',
    'Lieu public',
  ];

  /// Lieux choisis (anciennes valeurs reprises : « Domicile » → « Chez moi »)
  List<String> get lieuxChoisis => selectedLieuRencontre.value
      .split(',')
      .map((e) => e.trim())
      .map((e) => e == 'Domicile' ? 'Chez moi' : e)
      .where(lieuxRencontre.contains)
      .toSet()
      .toList();
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
  static const String emailContact = 'support.zamuapp@gmail.com';
  static const String _packageAndroid = 'com.vybestyle.zamu';

  final RxString versionApp = ''.obs;

  Future<void> ouvrirLien(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _snackError('Impossible d\'ouvrir le lien'.tr);
    }
  }

  Future<void> contacterSupport() async {
    try {
      final ok = await launchUrl(Uri.parse(
          'mailto:$emailContact?subject=${Uri.encodeComponent('Zamu - aide')}'));
      if (!ok) throw Exception();
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: emailContact));
      _snackSuccess('Adresse copiée : @emailContact'.trParams({'emailContact': emailContact.toString()}));
    }
  }

  /// Gestion de l'abonnement = page Abonnements de Google Play.
  Future<void> gererAbonnement() => ouvrirLien(
      'https://play.google.com/store/account/subscriptions?package=$_packageAndroid');

  void ouvrirPaywall() {
    // RevenueCat pas encore configuré → pas de paywall (évite un crash
    // sur Get.find<RevenueCatService>() dans l'écran paywall).
    if (!Get.isRegistered<RevenueCatService>()) {
      _snackError('Premium sera bientôt disponible'.tr);
      return;
    }
    Get.toNamed(AppRoutes.paywall);
  }

  Future<void> restaurerAchats() async {
    if (!Get.isRegistered<RevenueCatService>()) {
      _snackError('Service d\'achat indisponible pour le moment'.tr);
      return;
    }
    final premium = await Get.find<RevenueCatService>().restorePurchases();
    if (premium) {
      isPremium.value = true;
      _snackSuccess('Abonnement Premium restauré'.tr);
    } else {
      _snackError('Aucun abonnement actif trouvé sur ce compte Google'.tr);
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
      // « Je cherche » sert à la visibilité mutuelle (SQL 070) : on le
      // demande d'abord ; le pseudo attendra la prochaine ouverture.
      if ((data['looking_for']?.toString() ?? '').isEmpty) {
        _demanderCherche();
      } else if (monUsername.value.isEmpty) {
        _proposerPseudo();
      }
      usernameDispo.value = null;
      bioController.text = data['bio']?.toString() ?? '';
      tailleController.text = data['taille']?.toString() ?? '';
      poidsController.text = data['poids']?.toString() ?? '';

      // Sélections sécurisées
      selectedGender.value = data['gender']?.toString() ?? '';
      selectedLookingFor.value = data['looking_for']?.toString() ?? '';
      selectedMorphologie.value = data['morphologie']?.toString() ?? '';
      selectedLieuRencontre.value = data['lieu_rencontre']?.toString() ?? '';
      metierController.text = data['metier']?.toString() ?? '';
      etudesController.text = data['etudes']?.toString() ?? '';
      languesChoisies.assignAll(List<String>.from(data['langues'] ?? const []));
      questionsChoisies
          .assignAll(SupabaseService.questionsDepuis(data['questions']));

      // ✅ Toujours réinitialisé (sinon l'ancienne valeur restait si null)
      // Les intérêts choisis à l'inscription (« 🎮 Jeux vidéo ») sont
      // ramenés aux libellés de cet écran (« Gaming ») pour être cochés.
      selectedInterests.value = data['interests'] is List
          ? List<String>.from(data['interests'])
              .map(normaliserInteret)
              .where((i) => allInterests.any((e) => e['label'] == i))
              .toSet()
              .take(3)
              .toList()
          : <String>[];

      // Booléens sécurisés
      showBirthdate.value = data['show_birthdate'] ?? true;
      notifMessages.value = data['notif_messages'] ?? true;
      notifNearby.value = data['notif_nearby'] ?? true;
      notifStories.value = data['notif_stories'] ?? true;
      notifSon.value = data['notif_son'] ?? true;
      notifFavoris.value = data['notif_favoris'] ?? true;
      trouvableParPseudo.value = data['trouvable_par_pseudo'] ?? true;
      accepteDemandesAmi.value = data['accepte_demandes_ami'] ?? true;
      dispoTexte.value = data['dispo_texte'] as String?;
      dispoJusqua.value = data['dispo_jusqua'] != null
          ? DateTime.tryParse(data['dispo_jusqua'].toString())?.toLocal()
          : null;
      NotificationService.sonActive = notifSon.value;
      profilPublic.value = data['is_public'] ?? true;
      showDistance.value = data['show_distance'] ?? true;
      lecturesMasquees.value = data['lectures_masquees'] == true;
      isPremium.value = data['is_premium'] ?? false;

      // Thème et photos
      // Thème retiré (ex. gold, forest) → on affiche celui réellement actif.
      final theme = data['theme']?.toString();
      selectedTheme.value = AppPalettes.resoudre(theme)?.id ??
          ThemeController.to.choix.value.id;
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

  /// Recadrage après le choix de la photo (format portrait 3:4 des cartes).
  /// null si la personne annule.
  Future<String?> _recadrer(String chemin) async {
    try {
      final r = await ImageCropper().cropImage(
        sourcePath: chemin,
        aspectRatio: const CropAspectRatio(ratioX: 3, ratioY: 4),
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recadrer'.tr,
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.accent,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(title: 'Recadrer'.tr),
        ],
      );
      return r?.path;
    } catch (e) {
      debugPrint('Recadrage indisponible, photo gardée telle quelle : $e');
      return chemin;
    }
  }

  Future<void> changerPhoto() async {
    final source = await _choisirSource();
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1080,
      maxHeight: 1440,
      imageQuality: 90,
    );
    if (picked == null) return;
    final chemin = await _recadrer(picked.path);
    if (chemin == null) return;
    isUploadingPhoto.value = true;
    try {
      final uid = supabase.auth.currentUser!.id;
      final file = File(chemin);
      final ext = chemin.split('.').last;
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
          _snackSuccess('Photo mise à jour'.tr);
          break;
        case ModerationResult.pending:
          _snackSuccess(ModerationService.messageAttente);
          break;
        case ModerationResult.rejected:
          _snackError(ModerationService.messageRefus);
          break;
        case ModerationResult.full:
        case ModerationResult.error:
          _snackError('Impossible de vérifier la photo. Réessaie.'.tr);
          break;
      }
    } catch (e) {
      debugPrint('changerPhoto error: $e');
      debugPrint('$e');
      _snackError('Impossible de changer la photo. Réessaie.'.tr);
    } finally {
      isUploadingPhoto.value = false;
    }
  }

  Future<void> supprimerPhoto() async {
    final confirm = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Supprimer la photo ?'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary)),
      content: Text('Ta photo de profil sera supprimée définitivement.'.tr,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Supprimer'.tr,
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
      _snackSuccess('Photo supprimée'.tr);
    } catch (e) {
      debugPrint('$e');
      _snackError('Impossible de supprimer la photo. Réessaie.'.tr);
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
          Text('Photo de profil'.tr,
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          _SheetBtn(
              icon: '📷',
              label: 'Prendre une photo'.tr,
              onTap: () => Get.back(result: ImageSource.camera)),
          const SizedBox(height: 10),
          _SheetBtn(
              icon: '🖼️',
              label: 'Choisir dans la galerie'.tr,
              onTap: () => Get.back(result: ImageSource.gallery)),
          const SizedBox(height: 10),
          _SheetBtn(
              icon: '❌',
              label: 'Annuler'.tr,
              onTap: () => Get.back(),
              isCancel: true),
        ]),
      ),
    );
  }

  // ─── GALERIE DE PHOTOS (défilable sur le profil) ─────────────────

  Future<void> ajouterPhotoProfil() async {
    if (photoUrls.length >= maxPhotos) {
      _snackError('Maximum @maxPhotos photos'.trParams({'maxPhotos': maxPhotos.toString()}));
      return;
    }
    final source = await _choisirSource();
    if (source == null) return;
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1080,
      maxHeight: 1440,
      imageQuality: 90,
    );
    if (picked == null) return;
    final chemin = await _recadrer(picked.path);
    if (chemin == null) return;
    isUploadingPhoto.value = true;
    try {
      final uid = supabase.auth.currentUser!.id;
      final file = File(chemin);
      final ext = chemin.split('.').last;
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
          _snackSuccess('Photo ajoutée'.tr);
          break;
        case ModerationResult.pending:
          _snackSuccess(ModerationService.messageAttente);
          break;
        case ModerationResult.rejected:
          _snackError(ModerationService.messageRefus);
          break;
        case ModerationResult.full:
          _snackError('Maximum @maxPhotos photos (en comptant celles en cours de vérification)'.trParams({'maxPhotos': maxPhotos.toString()}));
          break;
        case ModerationResult.error:
          _snackError('Impossible de vérifier la photo. Réessaie.'.tr);
          break;
      }
    } catch (e) {
      debugPrint('ajouterPhotoProfil error: $e');
      debugPrint('$e');
      _snackError('Impossible d\'ajouter la photo. Réessaie.'.tr);
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
    _snackSuccess('Photo supprimée'.tr);
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
      debugPrint('$e');
      _snackError('Erreur de synchronisation. Réessaie.'.tr);
    }
  }

  // ─── MODIFIER INFOS ─────────────────────────────────────────────

  /// « 🎮 Jeux vidéo » (inscription) → « Gaming » (liste de l'écran Modifier)
  static String normaliserInteret(String valeur) {
    final texte = valeur
        .replaceFirst(RegExp(r'^[^\p{L}]+', unicode: true), '')
        .trim();
    const synonymes = {
      'Jeux vidéo': 'Gaming',
      'Gastronomie': 'Food',
      'Concerts': 'Musique',
      'Théâtre': 'Art',
    };
    return synonymes[texte] ?? texte;
  }

  void toggleInterest(String label) {
    if (selectedInterests.contains(label)) {
      selectedInterests.remove(label);
    } else {
      if (selectedInterests.length >= 3) {
        _snackError('3 intérêts maximum : retires-en un pour en choisir un autre'.tr);
        return;
      }
      selectedInterests.add(label);
    }
  }

  void setMorphologie(String v) => selectedMorphologie.value = v;
  /// Coche / décoche un lieu (3 maximum)
  void setLieuRencontre(String v) {
    final lieux = lieuxChoisis;
    if (lieux.contains(v)) {
      lieux.remove(v);
    } else {
      if (lieux.length >= 3) {
        _snackError('3 lieux maximum : retires-en un pour en choisir un autre'.tr);
        return;
      }
      lieux.add(v);
    }
    // Ordre de la liste (Chez moi avant Maquis…)
    lieux.sort((a, b) =>
        lieuxRencontre.indexOf(a).compareTo(lieuxRencontre.indexOf(b)));
    selectedLieuRencontre.value = lieux.join(', ');
  }

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
          // Calendrier aux couleurs du thème (fond blanc ou sombre)
          colorScheme: AppColors.clair
              ? ColorScheme.light(
                  primary: AppColors.accent,
                  onPrimary: AppColors.surAccent,
                  surface: AppColors.surface,
                  onSurface: AppColors.textPrimary,
                )
              : ColorScheme.dark(
                  primary: AppColors.accent,
                  onPrimary: AppColors.surAccent,
                  surface: AppColors.surface,
                  onSurface: AppColors.textPrimary,
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
    if (d == null) return 'Non renseignée'.tr;
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

  /// Compte sans pseudo (souvent créé avec Google) : on propose d'en
  /// choisir un, au plus une fois tous les 3 jours.
  /// Une fois par jour au plus, tant que « Je cherche » est vide.
  void _demanderCherche() {
    final box = GetStorage();
    final dernier = box.read<int>('cherche_demande_le') ?? 0;
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    if (maintenant - dernier < const Duration(days: 1).inMilliseconds) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (isClosed || selectedLookingFor.value.isNotEmpty) return;
      if (Get.isBottomSheetOpen == true || Get.isDialogOpen == true) return;
      box.write('cherche_demande_le', maintenant);
      Get.bottomSheet(
        SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Qui veux-tu rencontrer ?'.tr,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                  'Tu verras seulement les personnes qui te cherchent aussi. Ce choix reste privé.'
                      .tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 18),
              for (final opt in lookingForOptions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        setLookingFor(opt);
                        Get.back();
                        // L'Accueil se recharge avec les bons profils
                        if (Get.isRegistered<HomeController>()) {
                          Get.find<HomeController>().loadProfiles();
                        }
                      },
                      child: Text(opt.capitalizeFirst!.tr,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
    });
  }

  void _proposerPseudo() {
    final box = GetStorage();
    final dernier = box.read<int>('pseudo_propose_le') ?? 0;
    final maintenant = DateTime.now().millisecondsSinceEpoch;
    if (maintenant - dernier < const Duration(days: 3).inMilliseconds) return;
    Future.delayed(const Duration(seconds: 3), () {
      if (isClosed || monUsername.value.isNotEmpty) return;
      if (Get.isBottomSheetOpen == true || Get.isDialogOpen == true) return;
      box.write('pseudo_propose_le', maintenant);
      Get.bottomSheet(
        FeuillePseudo(ctrl: this, premiereFois: true),
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
      );
    });
  }

  /// Enregistre le @pseudo seul (carte « Mon @pseudo » du profil).
  /// Renvoie true si c'est enregistré.
  Future<bool> enregistrerPseudo(String saisi) async {
    final uid = supabase.auth.currentUser?.id;
    final u = saisi.trim().toLowerCase();
    if (uid == null) return false;
    if (u == monUsername.value) return true;
    if (!_usernameRegex.hasMatch(u)) {
      _snackError(
          'Nom d\'utilisateur invalide (3-20 caractères : lettres, chiffres, . ou _)'.tr);
      return false;
    }
    if (usernameDispo.value == false) {
      _snackError('Ce nom d\'utilisateur est déjà pris'.tr);
      return false;
    }
    try {
      await supabase.from('profiles').update({
        'username': u,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
      monUsername.value = u;
      usernameController.text = u;
      usernameText.value = u;
      _snackSuccess('Ton pseudo est maintenant @@u'.trParams({'u': u.toString()}));
      return true;
    } on PostgrestException catch (e) {
      // 23505 : quelqu'un l'a pris entre-temps (contrainte unique)
      _snackError(e.code == '23505'
          ? 'Ce nom d\'utilisateur est déjà pris'.tr
          : 'Impossible d\'enregistrer le pseudo'.tr);
      return false;
    } catch (_) {
      _snackError('Impossible d\'enregistrer le pseudo'.tr);
      return false;
    }
  }

  Future<void> sauvegarderInfos() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      _snackError('Utilisateur non connecté'.tr);
      return;
    }
    if (nomController.text.trim().isEmpty) {
      _snackError('Le prénom est obligatoire'.tr);
      return;
    }
    final username = usernameController.text.trim().toLowerCase();
    final usernameChange = username != monUsername.value;
    if (usernameChange) {
      if (!_usernameRegex.hasMatch(username)) {
        _snackError(
            'Nom d\'utilisateur invalide (3-20 caractères : lettres, chiffres, . ou _)'.tr);
        return;
      }
      if (usernameDispo.value == false) {
        _snackError('Ce nom d\'utilisateur est déjà pris'.tr);
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
          _snackError('Taille invalide (100–250 cm)'.tr);
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
          _snackError('Poids invalide (30–300 kg)'.tr);
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
      // Profil enrichi : enregistré à part, pour ne pas bloquer le reste
      // si les colonnes (SQL 051) ne sont pas encore créées.
      try {
        final metier = metierController.text.trim();
        final etudes = etudesController.text.trim();
        await supabase.from('profiles').update({
          'metier': metier.isEmpty ? null : metier.substring(0, metier.length.clamp(0, 60)),
          'etudes': etudes.isEmpty ? null : etudes.substring(0, etudes.length.clamp(0, 80)),
          'langues': languesChoisies.toList(),
          'questions': questionsChoisies.toList(),
        }).eq('id', uid);
      } catch (e) {
        debugPrint('Profil enrichi non enregistré (SQL 051 ?) : $e');
      }
      await chargerMonProfil();
      // ✅ FIX : redirige vers l'accueil et affiche le message de
      // confirmation AVANT la navigation (le snackbar GetX vit dans un
      // overlay indépendant de la pile de navigation, il survit au
      // changement de route).
      _snackSuccess('Informations mises à jour'.tr);
      Get.until((route) => route.settings.name == AppRoutes.main); // ✅
    } on PostgrestException catch (e) {
      // 23505 = contrainte unique : nom pris entre la vérification et l'enregistrement
      if (e.code == '23505') {
        usernameDispo.value = false;
        _snackError('Ce nom d\'utilisateur est déjà pris'.tr);
      } else {
        debugPrint(e.message);
        _snackError('Enregistrement impossible. Réessaie.'.tr);
      }
    } catch (e) {
      _snackError(
          'Enregistrement impossible. Réessaie.'.tr);
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

  /// Publie (ou arrête si [texte] est null) le statut « Dispo maintenant ».
  Future<bool> definirDispo(String? texte, Duration duree) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    final t = texte?.trim();
    final fin = (t == null || t.isEmpty) ? null : DateTime.now().add(duree);
    try {
      await supabase.from('profiles').update({
        'dispo_texte': fin == null ? null : t,
        'dispo_jusqua': fin?.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
      dispoTexte.value = fin == null ? null : t;
      dispoJusqua.value = fin;
      return true;
    } catch (e) {
      debugPrint('definirDispo : $e'); // script SQL 028 absent ?
      _snackError('Statut non enregistré, vérifie ta connexion'.tr);
      return false;
    }
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
      _snackError('Réglage non enregistré, vérifie ta connexion'.tr);
    }
  }

  // ─── EMAIL / MOT DE PASSE ────────────────────────────────────────

  Future<void> modifierEmail(String newEmail) async {
    if (newEmail.trim().isEmpty || !GetUtils.isEmail(newEmail.trim())) {
      _snackError('Email invalide'.tr);
      return;
    }
    isSaving.value = true;
    try {
      await supabase.auth.updateUser(UserAttributes(email: newEmail.trim()));
      _snackSuccess('Email mis à jour — vérifie ta boîte mail pour confirmer'.tr);
      // ✅ Le dialog est déjà fermé par la vue : un 2e Get.back() fermait
      // l'écran Paramètres.
    } catch (e) {
      debugPrint('$e');
      _snackError('Impossible de modifier l\'email. Réessaie.'.tr);
    } finally {
      isSaving.value = false;
    }
  }

  Future<void> modifierMotDePasse(String newPassword) async {
    if (newPassword.length < 6) {
      _snackError('Minimum 6 caractères requis'.tr);
      return;
    }
    isSaving.value = true;
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
      _snackSuccess('Mot de passe mis à jour'.tr);
    } catch (e) {
      debugPrint('$e');
      _snackError('Impossible de modifier le mot de passe. Réessaie.'.tr);
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
      _snackSuccess('Profil bloqué'.tr);
      Get.until((route) => route.settings.name == '/main');
    } catch (e) {
      _snackError('Impossible de bloquer ce profil'.tr);
    }
  }

  /// [preuves] : extrait de la conversation (derniers messages de la
  /// personne signalée), joint pour l'équipe de modération.
  Future<void> signalerProfil(String targetId, String reason,
      {String? preuves}) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('reports').insert({
        'reporter_id': uid,
        'reported_id': targetId,
        'reason': reason,
        if ((preuves ?? '').isNotEmpty) 'description': preuves,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _snackSuccess('Signalement envoyé. Merci !'.tr);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _snackError('Tu as déjà signalé ce profil'.tr);
      } else {
        _snackError('Impossible d\'envoyer le signalement'.tr);
      }
    } catch (e) {
      _snackError('Impossible d\'envoyer le signalement'.tr);
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
      _snackSuccess('Utilisateur débloqué'.tr);
    } catch (e) {
      debugPrint('$e');
      _snackError('Impossible de débloquer. Réessaie.'.tr);
    }
  }

  Future<void> toutDebloquer() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final confirmed = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Tout débloquer ?'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary)),
      content: Text('Tous les profils bloqués seront débloqués.'.tr,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
            onTap: () => Get.back(result: true),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accent2]),
                  borderRadius: BorderRadius.circular(12)),
              child:  Text('Débloquer tout'.tr,
                  style: TextStyle(
                      color: AppColors.surAccent, fontWeight: FontWeight.w700)),
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
      _snackSuccess('Tous les profils débloqués'.tr);
    } catch (e) {
      _snackError('Impossible de débloquer'.tr);
    }
  }

  // ─── UTILITAIRES ────────────────────────────────────────────────

  void copierNumero(String numero) {
    Clipboard.setData(ClipboardData(text: numero));
    _snackSuccess('Numéro copié : @numero'.trParams({'numero': numero.toString()}));
  }

  Future<void> ouvrirWhatsApp() async {
    const phone = '2250720457945';
    final msg = Uri.encodeComponent(
        'Bonjour Zamu, je vous contacte depuis l\'application.');
    final uri = Uri.parse('https://wa.me/$phone?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _snackError('WhatsApp non disponible'.tr);
    }
  }

  // ─── DÉCONNEXION ────────────────────────────────────────────────

  void deconnexion() {
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Se déconnecter ?'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: 18)),
      content: Text('Tu devras te reconnecter pour accéder à ton compte.'.tr,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler'.tr,
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
            child:  Text('Déconnexion'.tr,
                style: TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  void supprimerCompte() {
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Supprimer ton compte ?'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: 18)),
      content: Text(
          "Ton compte sera masqué tout de suite, puis supprimé définitivement dans 30 jours (profil, photos, messages, matchs). Tu changes d'avis ? Reconnecte-toi avant la fin des 30 jours pour le garder."
              .tr,
          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () async {
            Get.back();
            isSaving.value = true;
            try {
              // ✅ Suppression différée de 30 jours (SQL 077) : le compte est
              // masqué tout de suite, puis supprimé par la purge de nuit.
              final fin = await supabase.rpc('demander_suppression_compte');
              final date = DateTime.tryParse('$fin')?.toLocal();
              await AuthController.to.signOut();
              Get.offAllNamed('/login');
              Get.snackbar(
                  'Compte masqué'.tr,
                  date == null
                      ? 'Il sera supprimé définitivement dans 30 jours.'.tr
                      : 'Il sera supprimé définitivement le @date.'.trParams({
                          'date':
                              '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                        }),
                  snackPosition: SnackPosition.TOP,
                  duration: const Duration(seconds: 6),
                  backgroundColor: AppColors.surface,
                  colorText: AppColors.textPrimary);
            } catch (e) {
              debugPrint('$e');
      _snackError('Impossible de supprimer le compte. Réessaie.'.tr);
            } finally {
              isSaving.value = false;
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(12)),
            child:  Text('Supprimer définitivement'.tr,
                style: TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  // ─── HELPERS ────────────────────────────────────────────────────

  void _snackSuccess(String msg) => Get.snackbar('✅ $msg', '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.online.withOpacity(0.15),
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 2));

  void _snackError(String msg) => Get.snackbar('Erreur'.tr, msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary,
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
          color: isCancel ? Colors.transparent : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: isCancel ? null : Border.all(color: AppColors.surface2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isCancel ? AppColors.textMuted : AppColors.textPrimary)),
        ]),
      ),
    );
  }
}
