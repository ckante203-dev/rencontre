// lib/features/auth/controller/auth_controller.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/services/update_service.dart';

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

  @override
  void onInit() {
    super.onInit();
    currentUser.value = supabase.auth.currentUser;
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
      _setOnlineNow(user.id);
      _saveFcmToken();
      _checkOnboarding(user.id);
    } else if (event == AuthChangeEvent.signedOut) {
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
        // ✅ Onboarding terminé → /main directement
        Get.offAllNamed('/main');
        Future.delayed(const Duration(seconds: 2), () {
          UpdateService.checkForUpdate();
        });
      }
    } catch (e) {
      debugPrint('_checkOnboarding error: $e');
      Get.offAllNamed('/onboarding/photo');
    }
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
    try {
      final existing = await supabase
          .from('profiles')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      usernameAvailable.value = existing == null;
    } catch (e) {
      debugPrint('checkUsernameAvailability error: $e');
      // ✅ En cas d'erreur réseau on ne bloque pas l'utilisateur ;
      // la contrainte unique en base reste le vrai garde-fou.
      usernameAvailable.value = true;
    } finally {
      checkingUsername.value = false;
    }
  }

  // ─── EMAIL / PASSWORD ──────────────────────────────────────

  /// ✅ Inscription simplifiée façon Snapchat : le compte est créé et
  /// utilisable immédiatement, sans étape de validation d'email.
  /// L'email pourra être vérifié plus tard depuis le profil.
  Future<void> signUpWithEmail() async {
    if (!_validateSignUp()) return;
    _setLoading(true);
    try {
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
          backgroundColor: const Color(0xFF13131A),
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
          await _createProfile(res.user!,
              name: googleUser.displayName, photoUrl: googleUser.photoUrl);
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

  // ─── TÉLÉPHONE ─────────────────────────────────────────────

  Future<void> savePhoneNumberOnly(String phone) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({
        'phone': phone,
        'phone_verified': false,
        'updated_at': DateTime.now().toIso8601String(),
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
      'updated_at': DateTime.now().toIso8601String(),
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
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
    } catch (_) {}
    await supabase.auth.signOut();
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
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
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
        return const Color(0xFFFF5252);
      case 2:
        return const Color(0xFFFF3CAC);
      case 3:
        return const Color(0xFF7B2FFF);
      case 4:
        return const Color(0xFF00E676);
      default:
        return const Color(0xFF2A2A3D);
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
      if (day < 1 || day > 31) {
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
