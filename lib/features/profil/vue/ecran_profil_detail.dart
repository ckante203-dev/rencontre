import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/shared/models/user_model.dart';

class EcranProfilDetail extends StatefulWidget {
  const EcranProfilDetail({super.key});

  @override
  State<EcranProfilDetail> createState() => _EcranProfilDetailState();
}

class _EcranProfilDetailState extends State<EcranProfilDetail>
    with SingleTickerProviderStateMixin {
  late UserModel user;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  bool _isLoadingMsg = false;

  @override
  void initState() {
    super.initState();
    user = Get.arguments as UserModel;
    _animCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  // ─── ENVOYER MESSAGE ─────────────────────────────────────────

  Future<void> _ouvrirChat() async {
    setState(() => _isLoadingMsg = true);
    try {
      final service = SupabaseService();
      final convId = await service.getOrCreateConversation(user.id);

      final conv = ConversationModel(
        id: convId,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        isOnline: user.isOnline,
        unreadCount: 0,
      );

      Get.toNamed('/chat/conversation', arguments: conv);
    } catch (_) {
      Get.snackbar('Erreur', 'Impossible d\'ouvrir la conversation',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white);
    } finally {
      setState(() => _isLoadingMsg = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [

            // ── Photo plein écran ───────────────────────────────
            SizedBox(
              width: size.width,
              height: size.height,
              child: user.photoUrl != null && user.photoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: user.photoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _GradientBg(name: user.name),
                    errorWidget: (_, __, ___) => _GradientBg(name: user.name),
                  )
                : _GradientBg(name: user.name),
            ),

            // ── Gradient haut ───────────────────────────────────
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Gradient bas ────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: size.height * 0.55,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter, end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.95),
                      Colors.black.withOpacity(0.6), Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Bouton retour ───────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              child: GestureDetector(
                onTap: () => Get.back(),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                    size: 18, color: Colors.white),
                ),
              ),
            ),

            // ── Boutons action haut droite ───────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 16,
              child: Row(
                children: [
                  _ActionBtn(icon: Icons.more_horiz_rounded, onTap: _showOptions),
                ],
              ),
            ),

            // ── Contenu bas ─────────────────────────────────────
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [

                      // Nom + âge + online
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${user.name}, ${user.age}',
                              style: const TextStyle(
                                fontFamily: 'Syne', fontSize: 32,
                                fontWeight: FontWeight.w900, color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          if (user.isOnline)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: AppColors.online.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: AppColors.online.withOpacity(0.5)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.circle, size: 8,
                                    color: AppColors.online),
                                  SizedBox(width: 5),
                                  Text('En ligne',
                                    style: TextStyle(fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.online)),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Distance
                      if (user.distanceMeters != null)
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded,
                              size: 14, color: Colors.white60),
                            const SizedBox(width: 4),
                            Text(user.distanceLabel,
                              style: const TextStyle(fontSize: 13,
                                color: Colors.white60, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      const SizedBox(height: 12),

                      // Bio
                      if (user.bio != null && user.bio!.isNotEmpty) ...[
                        Text(user.bio!,
                          style: const TextStyle(fontSize: 14,
                            color: Colors.white70, height: 1.5),
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 12),
                      ],

                      // Intérêts
                      if (user.interests.isNotEmpty) ...[
                        Wrap(
                          spacing: 6, runSpacing: 6,
                          children: user.interests.take(5).map((i) =>
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(i, style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: Colors.white)),
                            ),
                          ).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Boutons action ──────────────────────────
                      Row(
                        children: [

                          // Bouton message principal
                          Expanded(
                            child: GestureDetector(
                              onTap: _ouvrirChat,
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  gradient: AppColors.gradientPink,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.accent.withOpacity(0.4),
                                      blurRadius: 20, offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: _isLoadingMsg
                                    ? const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                    : const Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.chat_bubble_rounded,
                                            size: 18, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text('Envoyer un message',
                                            style: TextStyle(fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                        ],
                                      ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Bouton snap
                          GestureDetector(
                            onTap: () => Get.snackbar(
                              '📸 Snap', 'Bientôt disponible !',
                              snackPosition: SnackPosition.TOP,
                              backgroundColor: const Color(0xFF13131A),
                              colorText: Colors.white,
                            ),
                            child: Container(
                              width: 54, height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Center(
                                child: Text('📸', style: TextStyle(fontSize: 22)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Bouton like/coeur
                          GestureDetector(
                            onTap: () => Get.snackbar(
                              '❤️ Like', 'Bientôt disponible !',
                              snackPosition: SnackPosition.TOP,
                              backgroundColor: const Color(0xFF13131A),
                              colorText: Colors.white,
                            ),
                            child: Container(
                              width: 54, height: 54,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: const Center(
                                child: Text('❤️', style: TextStyle(fontSize: 22)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOptions() {
    Get.bottomSheet(
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
            _OptionItem(icon: '🚫', label: 'Bloquer ${user.name}',
              color: AppColors.error,
              onTap: () { Get.back(); }),
            const SizedBox(height: 10),
            _OptionItem(icon: '⚠️', label: 'Signaler ce profil',
              color: Colors.orange,
              onTap: () { Get.back(); }),
            const SizedBox(height: 10),
            _OptionItem(icon: '❌', label: 'Annuler',
              color: AppColors.textMuted,
              onTap: () => Get.back()),
          ],
        ),
      ),
    );
  }
}

// ─── WIDGETS ───────────────────────────────────────────────────

class _GradientBg extends StatelessWidget {
  final String name;
  const _GradientBg({required this.name});

  @override
  Widget build(BuildContext context) {
    final colors = [
      [const Color(0xFFFF3CAC), const Color(0xFF7B2FFF)],
      [const Color(0xFF7B2FFF), const Color(0xFF00F5D4)],
      [const Color(0xFFFF6B6B), const Color(0xFFFF3CAC)],
    ];
    final idx = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors[idx],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Center(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 120, fontWeight: FontWeight.w900,
            color: Colors.white24)),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}

class _OptionItem extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _OptionItem({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF191926),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF252538)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}