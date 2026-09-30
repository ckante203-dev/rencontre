// lib/features/auth/controller/auth_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/services/update_service.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/home_screen.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';
import 'package:rencontre/features/likes/like_controller.dart';
import 'package:rencontre/features/likes/profile_insights_controller.dart';
import 'package:rencontre/features/notifications/controller/notification_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class AuthController extends GetxController {
  static AuthController get to => Get.find();

  final Rx<User?> currentUser = Rx<User?>(null);
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;
  final RxBool showEmailOtp = false.obs;
  final RxBool showPassword = false.obs;
  final RxBool showConfirmPassword = false.obs;
  final RxInt passwordStrength = 0.obs;

  // ✅ Vérification de disponibilité du nom d'utilisateur (inscription)
  final RxBool usernameAvailable = true.obs;
  final RxBool checkingUsername = false.obs;
  final RxString usernameText = ''.obs;

  final emailOtpController = TextEditingController();
  final nameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneController = TextEditingController();
  final birthdateController = TextEditingController();

  // ✅ Utilisateur auquel appartiennent les contrôleurs permanents
  // (accueil, chat, likes, profil…). S'il change, on les recrée.
  String? _sessionUserId;

  @override
  void onInit() {
    super.onInit();
    currentUser.value = supabase.auth.currentUser;
    _sessionUserId = supabase.auth.currentUser?.id;
    supabase.auth.onAuthStateChange.listen((data) {
      currentUser.value = data.session?.user;
      _handleAuthChange(data.event, data.session?.user);
    });

    // ✅ Si déjà connecté au démarrage → redirige directement
    final user = supabase.auth.currentUser;
    if (user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkOnboarding(user.id);
      });
    }
  }

  Future<void> checkOnboardingFromSplash(String userId) async {
    await _checkOnboarding(userId);
  }

  void _handleAuthChange(AuthChangeEvent event, User? user) {
    if (event == AuthChangeEvent.signedIn && user != null) {
      if (_sessionUserId != user.id) {
        _resetUserControllers();
        _sessionUserId = user.id;
      }
      _setOnlineNow(user.id);
      _saveFcmToken();
      _checkOnboarding(user.id);

      // ✅ Lie l'identité RevenueCat à l'utilisateur Supabase
      if (Get.isRegistered<RevenueCatService>()) {
        Get.find<RevenueCatService>().loginRevenueCat(user.id);
      }
    } else if (event == AuthChangeEvent.signedOut) {
      _sessionUserId = null;
      _setOfflineNow();
      // ✅ Après déconnexion → page LOGIN (pas splash)
      Get.offAllNamed('/login');
    }
  }

  Future<void> _setOnlineNow(String uid) async {
    try {
      await supabase.from('profiles').update({
        'is_online': true,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      debugPrint('_setOnlineNow error: $e');
    }
  }

  Future<void> _setOfflineNow() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      await supabase.from('profiles').update({
        'is_online': false,
        'last_seen': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (_) {}
  }

  Future<void> _saveFcmToken() async {
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await supabase
          .from('profiles')
          .update({'fcm_token': token}).eq('id', uid);
      debugPrint('✅ FCM token mis à jour: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  Future<void> _checkOnboarding(String uid) async {
    try {
      final row = await supabase
          .from('profiles')
          .select('onboarding_complete, birthdate, gender')
          .eq('id', uid)
          .maybeSingle();

      debugPrint('📋 Profile onboarding: $row');

      // ✅ Compte sans profil (création échouée à l'inscription) : on crée
      // un profil minimal, sans écraser celui que l'inscription est peut-
      // être en train d'enregistrer en parallèle.
      final authUser = supabase.auth.currentUser;
      if (row == null && authUser != null && authUser.id == uid) {
        try {
          await _createProfile(authUser, onlyIfMissing: true);
        } catch (e) {
          debugPrint('_checkOnboarding create profile error: $e');
        }
      }

      if (row == null || row['onboarding_complete'] != true) {
        final hasBirthdate = row != null &&
            row['birthdate'] != null &&
            (row['birthdate'] as String).isNotEmpty;

        final identities = supabase.auth.currentUser?.identities ?? [];
        final isGoogleUser = identities.any((i) => i.provider == 'google');

        if (isGoogleUser && !hasBirthdate) {
          Get.offAllNamed('/onboarding/birthdate');
        } else {
          Get.offAllNamed('/onboarding/photo');
        }
      } else {
        GetStorage().write('onboarding_done_$uid', true);
        // ✅ Onboarding terminé → /main directement. Si l'app y est déjà
        // (route initiale calculée dans main.dart), on ne renavigue pas :
        // ça effaçait la conversation ouverte depuis une notification.
        if (!_isInsideApp()) Get.offAllNamed('/main');
        Future.delayed(const Duration(seconds: 2), () {
          UpdateService.checkForUpdate();
        });
      }
    } catch (e) {
      debugPrint('_checkOnboarding error: $e');
      // ✅ Hors ligne : un utilisateur déjà inscrit reste dans l'app.
      final done = GetStorage().read<bool>('onboarding_done_$uid') ?? false;
      if (done) {
        if (!_isInsideApp()) Get.offAllNamed('/main');
      } else {
        Get.offAllNamed('/onboarding/photo');
      }
    }
  }

  bool _isInsideApp() {
    final r = Get.currentRoute;
    const outside = ['', '/', '/splash', '/login', '/signup', '/phone'];
    return !(outside.contains(r) ||
        r.startsWith('/login') ||
        r.startsWith('/onboarding') ||
        r.startsWith('/phone'));
  }

  // ─── USERNAME ────────────────────────────────────────────

  /// ✅ Vérifie en direct si le nom d'utilisateur saisi est disponible.
  Future<void> checkUsernameAvailability(String value) async {
    final username = value.trim().toLowerCase();
    if (username.length < 3) {
      usernameAvailable.value = false;
      return;
    }
    checkingUsername.value = true;
    // ✅ Ignore les réponses arrivées dans le désordre (frappe rapide).
    final seq = ++_usernameCheckSeq;
    try {
      // ✅ RPC : la table profiles n'est plus lisible avant connexion.
      final available = await supabase
          .rpc('username_available', params: {'p_username': username});
      if (seq != _usernameCheckSeq) return;
      usernameAvailable.value = available == true;
    } catch (e) {
      debugPrint('checkUsernameAvailability error: $e');
      if (seq != _usernameCheckSeq) return;
      // ✅ En cas d'erreur réseau on ne bloque pas l'utilisateur ;
      // la contrainte unique en base reste le vrai garde-fou.
      usernameAvailable.value = true;
    } finally {
      if (seq == _usernameCheckSeq) checkingUsername.value = false;
    }
  }

  int _usernameCheckSeq = 0;

  // ─── EMAIL / PASSWORD ──────────────────────────────────────

  /// ✅ Inscription simplifiée façon Snapchat : le compte est créé et
  /// utilisable immédiatement, sans étape de validation d'email.
  /// L'email pourra être vérifié plus tard depuis le profil.
  Future<void> signUpWithEmail() async {
    if (!_validateSignUp()) return;
    _setLoading(true);
    try {
      // ✅ Revérifie le nom juste avant de créer le compte : sinon un nom
      // déjà pris faisait échouer la création du profil après celle du
      // compte, laissant un compte sans profil bloqué dans l'onboarding.
      try {
        final available = await supabase.rpc('username_available', params: {
          'p_username': usernameController.text.trim().toLowerCase()
        });
        if (available == false) {
          usernameAvailable.value = false;
          errorMessage.value = 'Ce nom d\'utilisateur est déjà pris';
          return;
        }
      } catch (_) {}

      final res = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        data: {'name': nameController.text.trim()},
        emailRedirectTo: null,
      );
      errorMessage.value = '';

      if (res.user != null) {
        final parsed = _parseBirthdate(birthdateController.text);
        await _createProfile(
          res.user!,
          username: usernameController.text.trim().toLowerCase(),
          birthdate: parsed['iso'],
          age: parsed['age'],
        );
        // ✅ La navigation vers l'onboarding se déclenche automatiquement
        // via _handleAuthChange dès que la session est active.
      } else {
        errorMessage.value = 'Impossible de créer le compte. Réessaie.';
      }
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } catch (_) {
      errorMessage.value = 'Une erreur est survenue. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  /// ⚠️ Plus appelée pendant l'inscription — conservée pour être réutilisée
  /// plus tard depuis l'écran de profil ("Vérifier mon email").
  Future<void> verifyEmailOtp() async {
    final code = emailOtpController.text.trim();
    if (code.length != 8) {
      errorMessage.value = 'Entre le code à 8 chiffres';
      return;
    }
    _setLoading(true);
    try {
      final res = await supabase.auth.verifyOTP(
        email: emailController.text.trim(),
        token: code,
        type: OtpType.signup,
      );
      if (res.user != null) {
        await supabase
            .from('profiles')
            .update({'email_verified': true}).eq('id', res.user!.id);
        showEmailOtp.value = false;
        errorMessage.value = '';
      }
    } on AuthException catch (e) {
      errorMessage.value = e.message.contains('expired')
          ? 'Code expiré. Renvoie un nouveau code.'
          : 'Code incorrect. Vérifie ton email.';
    } catch (_) {
      errorMessage.value = 'Erreur de vérification. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  /// ⚠️ Plus appelée pendant l'inscription — conservée pour "Vérifier mon
  /// email" depuis le profil.
  Future<void> resendEmailOtp() async {
    _setLoading(true);
    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: emailController.text.trim(),
      );
      errorMessage.value = '';
      Get.snackbar('Code renvoyé', 'Vérifie ta boîte mail 📧',
          snackPosition: SnackPosition.TOP,
          backgroundColor: const Color(0xFF1A1A2E),
          colorText: Colors.white);
    } catch (_) {
      errorMessage.value = 'Impossible de renvoyer. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  /// ✅ Connexion par email OU nom d'utilisateur + mot de passe.
  Future<void> signInWithEmail() async {
    if (!_validateLogin()) return;
    _setLoading(true);
    try {
      final identifier = emailController.text.trim();
      String emailToUse;

      if (identifier.contains('@')) {
        emailToUse = identifier;
      } else {
        final match = await supabase
            .from('profiles')
            .select('email')
            .eq('username', identifier.toLowerCase())
            .maybeSingle();

        final foundEmail = match?['email'] as String?;
        if (foundEmail == null || foundEmail.isEmpty) {
          errorMessage.value = 'Aucun compte trouvé avec ce nom d\'utilisateur';
          _setLoading(false);
          return;
        }
        emailToUse = foundEmail;
      }

      await supabase.auth.signInWithPassword(
        email: emailToUse,
        password: passwordController.text,
      );
      errorMessage.value = '';
      // ✅ La navigation est gérée par _handleAuthChange (signedIn)
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } catch (_) {
      errorMessage.value = 'Une erreur est survenue. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> sendPasswordReset() async {
    if (emailController.text.trim().isEmpty) {
      errorMessage.value = 'Entre ton adresse email';
      return;
    }
    _setLoading(true);
    try {
      await supabase.auth.resetPasswordForEmail(emailController.text.trim());
      Get.snackbar('Email envoyé 📧', 'Vérifie ta boîte mail',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } finally {
      _setLoading(false);
    }
  }

  // ─── GOOGLE SIGN-IN ────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      // Client Web ID OAuth 2.0 généré dans Google Cloud Console (zamu-dcffa)
      const webClientId =
          '70132643190-skak491hsn89vg2qgmfe00ja04rcnb9j.apps.googleusercontent.com';

      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId: webClientId,
        scopes: ['email', 'profile'],
      );

      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        errorMessage.value =
            'Connexion Google échouée (aucun jeton d\'identité ID Token)';
        _setLoading(false);
        return;
      }

      final res = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: googleAuth.idToken!,
        accessToken: googleAuth.accessToken,
      );

      if (res.user != null) {
        final existing = await supabase
            .from('profiles')
            .select('id')
            .eq('id', res.user!.id)
            .maybeSingle();
        if (existing == null) {
          final prenom = (googleUser.displayName ?? '').trim().split(' ').first;
          await _createProfile(res.user!,
              name: prenom.isNotEmpty ? prenom : null,
              photoUrl: googleUser.photoUrl);
        }
      }
      errorMessage.value = '';
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      errorMessage.value = 'Connexion Google échouée. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── SIGN IN WITH APPLE (iOS) ──────────────────────────────
  // Exigé par l'App Store dès qu'une connexion Google est proposée.
  // Nécessite le fournisseur Apple activé dans Supabase (Auth > Providers)
  // avec l'identifiant com.vybestyle.zamu.

  Future<void> signInWithApple() async {
    _setLoading(true);
    try {
      final rawNonce = supabase.auth.generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        errorMessage.value = 'Connexion Apple échouée. Réessaie.';
        return;
      }

      final res = await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      if (res.user != null) {
        final existing = await supabase
            .from('profiles')
            .select('id')
            .eq('id', res.user!.id)
            .maybeSingle();
        if (existing == null) {
          // Apple ne donne le prénom qu'à la toute première connexion.
          final prenom = (credential.givenName ?? '').trim();
          await _createProfile(res.user!,
              name: prenom.isNotEmpty ? prenom : null);
        }
      }
      errorMessage.value = '';
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code != AuthorizationErrorCode.canceled) {
        debugPrint('Apple Sign-In error: $e');
        errorMessage.value = 'Connexion Apple échouée. Réessaie.';
      }
    } catch (e) {
      debugPrint('Apple Sign-In error: $e');
      errorMessage.value = 'Connexion Apple échouée. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── TÉLÉPHONE ─────────────────────────────────────────────

  Future<void> savePhoneNumberOnly(String phone) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'phone': phone,
        'phone_verified': false,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
    } catch (e) {
      debugPrint('savePhoneNumberOnly error: $e');
    }
  }

  void skipPhoneVerify() => Get.offAllNamed('/main');

  // ─── ONBOARDING ────────────────────────────────────────────

  Future<void> updateProfile({String? photoUrl}) async {
    await saveOnboardingData(photoUrl: photoUrl);
  }

  Future<void> saveOnboardingData({
    String? photoUrl,
    String? gender,
    String? lookingFor,
    List<String>? interests,
    int? age,
    String? bio,
    bool complete = false,
  }) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    final Map<String, dynamic> updates = {
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (photoUrl != null) updates['photo_url'] = photoUrl;
    if (gender != null) updates['gender'] = gender;
    if (lookingFor != null) updates['looking_for'] = lookingFor;
    if (interests != null) updates['interests'] = interests;
    if (age != null) updates['age'] = age;
    if (bio != null) updates['bio'] = bio;
    if (complete) updates['onboarding_complete'] = true;

    await supabase.from('profiles').update(updates).eq('id', uid);
  }

  // ─── SIGN OUT ──────────────────────────────────────────────

  Future<void> signOut() async {
    await _setOfflineNow();
    // ✅ Ce téléphone ne doit plus recevoir les push de ce compte.
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        await supabase
            .from('profiles')
            .update({'fcm_token': null}).eq('id', uid);
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('signOut fcm cleanup error: $e');
    }
    // ✅ Sinon un achat du compte suivant serait attribué à celui-ci.
    if (Get.isRegistered<RevenueCatService>()) {
      await Get.find<RevenueCatService>().logoutRevenueCat();
    }
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
    } catch (_) {}
    await supabase.auth.signOut();
  }

  /// ✅ Les contrôleurs permanents gardaient les données (profil, likes,
  /// conversations, Premium, canaux realtime) du compte précédent.
  void _resetUserControllers() {
    void del<T>() {
      if (Get.isRegistered<T>()) Get.delete<T>(force: true);
    }

    del<ControleurProfil>();
    del<HomeController>();
    del<ChatListController>();
    del<LikeController>();
    del<ProfileInsightsController>();
    del<NotificationController>();
    del<UnreadMessagesController>();
    del<NavigationController>();
  }

  // ─── HELPERS ───────────────────────────────────────────────

  Map<String, dynamic> _parseBirthdate(String dateText) {
    try {
      final digits = dateText.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length != 8) return {'iso': null, 'age': 18};

      final day = int.parse(digits.substring(0, 2));
      final month = int.parse(digits.substring(2, 4));
      final year = int.parse(digits.substring(4, 8));

      final isoDate = '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}';

      final now = DateTime.now();
      final birth = DateTime(year, month, day);
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }

      debugPrint('✅ Birthdate: $isoDate (age: $age)');
      return {'iso': isoDate, 'age': age};
    } catch (e) {
      debugPrint('_parseBirthdate error: $e');
      return {'iso': null, 'age': 18};
    }
  }

  Future<void> _createProfile(
    User user, {
    String? name,
    String? username,
    String? photoUrl,
    String? birthdate,
    int? age,
    bool onlyIfMissing = false,
  }) async {
    final now = DateTime.now();
    await supabase.from('profiles').upsert({
      'id': user.id,
      'name': name ?? user.userMetadata?['name'] ?? 'Utilisateur',
      'username': username ?? 'user${user.id.substring(0, 8)}',
      'email': user.email ?? '',
      'email_verified': false,
      'photo_url': photoUrl ?? user.userMetadata?['avatar_url'] ?? '',
      'photo_urls': [],
      'interests': [],
      'bio': '',
      'birthdate': birthdate,
      'age': age ?? 18,
      'gender': 'non précisé',
      'looking_for': null,
      'is_online': true,
      'last_seen': now.toUtc().toIso8601String(),
      'onboarding_complete': false,
      'phone_verified': false,
      'followers_count': 0,
      'following_count': 0,
      'matches_count': 0,
      'app_version': '1.0.3',
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    }, ignoreDuplicates: onlyIfMissing);
    debugPrint('✅ Profil créé — birthdate: $birthdate, age: ${age ?? 18}');
  }

  void updatePasswordStrength(String password) {
    if (password.isEmpty) {
      passwordStrength.value = 0;
      return;
    }
    int s = 0;
    if (password.length >= 8) s++;
    if (password.contains(RegExp(r'[A-Z]'))) s++;
    if (password.contains(RegExp(r'[0-9]'))) s++;
    if (password.contains(RegExp(r'[!@#\$%^&*]'))) s++;
    passwordStrength.value = s;
  }

  String get strengthLabel {
    switch (passwordStrength.value) {
      case 1:
        return 'Faible';
      case 2:
        return 'Moyen';
      case 3:
        return 'Bon';
      case 4:
        return 'Excellent ✓';
      default:
        return '';
    }
  }

  Color get strengthColor {
    switch (passwordStrength.value) {
      case 1:
        return AppColors.error;
      case 2:
        return AppColors.accent;
      case 3:
        return AppColors.accent2;
      case 4:
        return AppColors.online;
      default:
        return AppColors.border;
    }
  }

  bool _validateSignUp() {
    if (nameController.text.trim().isEmpty) {
      errorMessage.value = 'Entre ton prénom';
      return false;
    }

    final username = usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      errorMessage.value = 'Choisis un nom d\'utilisateur';
      return false;
    }
    if (!RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(username)) {
      errorMessage.value =
          'Nom d\'utilisateur invalide (3-20 caractères : lettres, chiffres, . ou _)';
      return false;
    }
    if (!usernameAvailable.value) {
      errorMessage.value = 'Ce nom d\'utilisateur est déjà pris';
      return false;
    }

    final dateText = birthdateController.text.trim();
    if (dateText.isEmpty) {
      errorMessage.value = 'Entre ta date de naissance';
      return false;
    }
    if (dateText.length != 10) {
      errorMessage.value = 'Date invalide — format JJ/MM/AAAA';
      return false;
    }
    try {
      final parts = dateText.split('/');
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      final now = DateTime.now();
      if (month < 1 || month > 12) {
        errorMessage.value = 'Mois invalide (01-12)';
        return false;
      }
      // ✅ Refuse aussi les dates inexistantes (31/02, 31/04…) que
      // Postgres rejetait à la création du profil.
      if (day < 1 || day > 31 || DateTime(year, month, day).day != day) {
        errorMessage.value = 'Jour invalide (01-31)';
        return false;
      }
      if (year < 1900 || year > now.year) {
        errorMessage.value = 'Année invalide';
        return false;
      }
      final birthDate = DateTime(year, month, day);
      final age = now.year -
          birthDate.year -
          (now.month < birthDate.month ||
                  (now.month == birthDate.month && now.day < birthDate.day)
              ? 1
              : 0);
      if (age < 18) {
        errorMessage.value = 'Tu dois avoir au moins 18 ans';
        return false;
      }
      if (age > 100) {
        errorMessage.value = 'Date de naissance invalide';
        return false;
      }
    } catch (_) {
      errorMessage.value = 'Date invalide — format JJ/MM/AAAA';
      return false;
    }
    if (!emailController.text.contains('@')) {
      errorMessage.value = 'Adresse email invalide';
      return false;
    }
    if (passwordController.text.length < 8) {
      errorMessage.value = 'Mot de passe trop court (min. 8 caractères)';
      return false;
    }
    if (confirmPasswordController.text != passwordController.text) {
      errorMessage.value = 'Les mots de passe ne correspondent pas';
      return false;
    }
    return true;
  }

  bool _validateLogin() {
    if (emailController.text.trim().isEmpty) {
      errorMessage.value = 'Entre ton email ou ton nom d\'utilisateur';
      return false;
    }
    if (passwordController.text.isEmpty) {
      errorMessage.value = 'Entre ton mot de passe';
      return false;
    }
    return true;
  }

  String _errorMsg(String msg) {
    if (msg.contains('already registered')) return 'Cet email est déjà utilisé';
    if (msg.contains('Invalid login')) return 'Email ou mot de passe incorrect';
    if (msg.contains('Email not confirmed'))
      return 'Confirme ton email avant de te connecter';
    if (msg.contains('Password should be'))
      return 'Mot de passe trop court (min. 6 caractères)';
    if (msg.contains('network') || msg.contains('Network'))
      return 'Pas de connexion internet';
    if (msg.contains('rate limit'))
      return 'Trop de tentatives. Réessaie plus tard';
    return msg;
  }

  void _setLoading(bool v) => isLoading.value = v;
  void clearError() => errorMessage.value = '';

  @override
  void onClose() {
    emailOtpController.dispose();
    nameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    birthdateController.dispose();
    super.onClose();
  }
}
