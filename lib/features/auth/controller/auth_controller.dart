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
  final RxBool codeSent = false.obs;
  final RxBool showEmailOtp = false.obs;
  final RxBool showPassword = false.obs;
  final RxInt passwordStrength = 0.obs;

  final emailOtpController = TextEditingController();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  final otpController = TextEditingController();
  final birthdateController = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    currentUser.value = supabase.auth.currentUser;
    supabase.auth.onAuthStateChange.listen((data) {
      currentUser.value = data.session?.user;
      _handleAuthChange(data.event, data.session?.user);
    });
  }

  Future<void> checkOnboardingFromSplash(String userId) async {
    await _checkOnboarding(userId);
  }

  void _handleAuthChange(AuthChangeEvent event, User? user) {
    if (event == AuthChangeEvent.signedIn && user != null) {
      _saveFcmToken();
      _checkOnboarding(user.id);
    } else if (event == AuthChangeEvent.signedOut) {
      Get.offAllNamed('/splash');
    }
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
      debugPrint('✅ FCM Token sauvegardé: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  Future<void> _checkOnboarding(String uid) async {
    try {
      final row = await supabase
          .from('profiles')
          .select('onboarding_complete')
          .eq('id', uid)
          .maybeSingle();

      if (row == null || row['onboarding_complete'] != true) {
        Get.offAllNamed('/onboarding/photo');
      } else {
        Get.offAllNamed('/main');
        // ✅ Vérifie la mise à jour 2 secondes après le chargement
        Future.delayed(const Duration(seconds: 2), () {
          UpdateService.checkForUpdate();
        });
      }
    } catch (_) {
      Get.offAllNamed('/onboarding/photo');
    }
  }

  // ─── EMAIL / PASSWORD ──────────────────────────────────────────

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
      if (res.session != null && res.user != null) {
        await _createProfile(res.user!);
      } else {
        showEmailOtp.value = true;
      }
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } catch (_) {
      errorMessage.value = 'Une erreur est survenue. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  Future<void> verifyEmailOtp() async {
    final code = emailOtpController.text.trim();
    if (code.length != 6) {
      errorMessage.value = 'Entre le code à 6 chiffres';
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
        await _createProfile(res.user!);
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

  Future<void> signInWithEmail() async {
    if (!_validateLogin()) return;
    _setLoading(true);
    try {
      await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      errorMessage.value = '';
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
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
      Get.snackbar(
        'Email envoyé 📧',
        'Vérifie ta boîte mail',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white,
      );
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } finally {
      _setLoading(false);
    }
  }

  // ─── GOOGLE SIGN-IN ────────────────────────────────────────────

  Future<void> signInWithGoogle() async {
    _setLoading(true);
    try {
      const webClientId =
          'REMPLACE_PAR_TON_WEB_CLIENT_ID.apps.googleusercontent.com';
      final GoogleSignIn googleSignIn =
          GoogleSignIn(serverClientId: webClientId);
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        _setLoading(false);
        return;
      }

      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        errorMessage.value = 'Connexion Google échouée';
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
          await _createProfile(
            res.user!,
            name: googleUser.displayName,
            photoUrl: googleUser.photoUrl,
          );
        }
      }
      errorMessage.value = '';
    } catch (_) {
      errorMessage.value = 'Connexion Google échouée. Réessaie.';
    } finally {
      _setLoading(false);
    }
  }

  // ─── PHONE OTP ─────────────────────────────────────────────────

  Future<void> sendOtp() async {
    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      errorMessage.value = 'Entre ton numéro de téléphone';
      return;
    }
    _setLoading(true);
    try {
      await supabase.auth.signInWithOtp(phone: phone);
      codeSent.value = true;
      Get.snackbar(
        'Code envoyé 📱',
        'Vérifie tes SMS',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white,
      );
      errorMessage.value = '';
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } finally {
      _setLoading(false);
    }
  }

  Future<void> verifyOtp() async {
    if (otpController.text.trim().length != 6) {
      errorMessage.value = 'Entre le code à 6 chiffres';
      return;
    }
    _setLoading(true);
    try {
      final res = await supabase.auth.verifyOTP(
        phone: phoneController.text.trim(),
        token: otpController.text.trim(),
        type: OtpType.sms,
      );
      if (res.user != null) {
        final existing = await supabase
            .from('profiles')
            .select('id')
            .eq('id', res.user!.id)
            .maybeSingle();
        if (existing == null) await _createProfile(res.user!);
      }
      errorMessage.value = '';
    } on AuthException catch (e) {
      errorMessage.value = _errorMsg(e.message);
    } finally {
      _setLoading(false);
    }
  }

  // ─── ONBOARDING ────────────────────────────────────────────────

  Future<void> updateProfile({String? photoUrl}) async {
    await saveOnboardingData(photoUrl: photoUrl);
  }

  Future<void> saveOnboardingData({
    String? photoUrl,
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
    if (interests != null) updates['interests'] = interests;
    if (age != null) updates['age'] = age;
    if (bio != null) updates['bio'] = bio;
    if (complete) updates['onboarding_complete'] = true;

    await supabase.from('profiles').update(updates).eq('id', uid);
  }

  // ─── SIGN OUT ──────────────────────────────────────────────────

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  // ─── HELPERS ───────────────────────────────────────────────────

  Future<void> _createProfile(User user,
      {String? name, String? photoUrl}) async {
    await supabase.from('profiles').upsert({
      'id': user.id,
      'name': name ?? user.userMetadata?['name'] ?? 'Utilisateur',
      'email': user.email ?? '',
      'photo_url': photoUrl ?? user.userMetadata?['avatar_url'] ?? '',
      'photo_urls': [],
      'interests': [],
      'bio': '',
      'birthdate': birthdateController.text.trim(),
      'age': 18,
      'is_online': true,
      'onboarding_complete': false,
      'followers_count': 0,
      'following_count': 0,
      'matches_count': 0,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
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
    return true;
  }

  bool _validateLogin() {
    if (emailController.text.trim().isEmpty) {
      errorMessage.value = 'Entre ton email';
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
    if (msg.contains('invalid')) return 'Code SMS incorrect';
    if (msg.contains('Phone')) return 'Numéro de téléphone invalide';
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
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    otpController.dispose();
    birthdateController.dispose();
    super.onClose();
  }
}
