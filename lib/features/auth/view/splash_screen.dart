import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/auth/controller/auth_controller.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    // ✅ Vérifie session après animation
    Future.delayed(const Duration(milliseconds: 1500), _checkSession);
  }

  Future<void> _checkSession() async {
    final authCtrl = Get.find<AuthController>();
    final user = authCtrl.currentUser.value;
    if (user != null) {
      // Utilisateur déjà connecté → vérifie onboarding
      authCtrl.checkOnboardingFromSplash(user.id);
    }
    // Sinon reste sur splash avec les boutons
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Ambient glow background
          Positioned(
            top: -100, left: -100,
            child: Container(
              width: 400, height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accent.withOpacity(0.15), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -80, right: -80,
            child: Container(
              width: 350, height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [AppColors.accent2.withOpacity(0.12), Colors.transparent],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Logo
                    ScaleTransition(
                      scale: _scaleAnim,
                      child: Column(
                        children: [
                          // Vrai logo
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withOpacity(0.45),
                                  blurRadius: 40, spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/logo.png',
                                width: 130, height: 130,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          ShaderMask(
                            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                            child: const Text(
                              'SnapMeet',
                              style: TextStyle(
                                fontFamily: 'Syne', fontSize: 40,
                                fontWeight: FontWeight.w900, color: Colors.white,
                                letterSpacing: -1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Rencontre. Connecte. Vis.',
                            style: TextStyle(
                              fontSize: 15, color: AppColors.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 2),

                    // Buttons
                    Column(
                      children: [
                        // Sign up
                        GestureDetector(
                          onTap: () => Get.toNamed('/signup'),
                          child: Container(
                            width: double.infinity, height: 54,
                            decoration: BoxDecoration(
                              gradient: AppColors.gradientPink,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withOpacity(0.35),
                                  blurRadius: 24, offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text('Créer un compte',
                                style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700,
                                  color: Colors.white, letterSpacing: 0.3,
                                )),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Sign in
                        GestureDetector(
                          onTap: () => Get.toNamed('/login'),
                          child: Container(
                            width: double.infinity, height: 54,
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: AppColors.border, width: 1.5),
                            ),
                            child: const Center(
                              child: Text('Se connecter',
                                style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                )),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Terms
                    Text(
                      'En continuant, tu acceptes nos Conditions d\'utilisation\net notre Politique de confidentialité',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11, color: AppColors.textMuted.withOpacity(0.7),
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}