import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class MatchDialog extends StatefulWidget {
  final UserModel matchedUser;
  const MatchDialog({super.key, required this.matchedUser});

  @override
  State<MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<MatchDialog>
    with TickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late AnimationController _heartCtrl;
  late Animation<double> _scaleAnim;
  late Animation<double> _heartAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _heartCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _scaleCtrl, curve: Curves.elasticOut);
    _heartAnim = CurvedAnimation(parent: _heartCtrl, curve: Curves.elasticOut);
    _scaleCtrl.forward();
    Future.delayed(
        const Duration(milliseconds: 150), () => _heartCtrl.forward());
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    _heartCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.matchedUser;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: AppColors.accent.withOpacity(0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withOpacity(0.2),
                blurRadius: 50,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cœur animé
              ScaleTransition(
                scale: _heartAnim,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accent2],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.55),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.favorite_rounded,
                      color: Colors.white, size: 38),
                ),
              ),
              const SizedBox(height: 20),

              // Titre
              ShaderMask(
                shaderCallback: (b) => LinearGradient(
                  colors: [AppColors.accent, AppColors.accent2],
                ).createShader(b),
                child: const Text(
                  "C'est un Match !",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Avatar
              _MatchAvatar(user: user),
              const SizedBox(height: 14),

              Text(user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  )),
              const SizedBox(height: 6),
              Text(
                'Vous vous êtes likés mutuellement 💫',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.55),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Bouton message
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.accent, AppColors.accent2],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Get.back();
                      _ouvrirChat(user);
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 9),
                        Text('Envoyer un message',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              TextButton(
                onPressed: () => Get.back(),
                child: Text(
                  'Continuer à explorer',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ouvrirChat(UserModel user) async {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final existing = await Supabase.instance.client
          .from('conversations')
          .select()
          .or('and(user1_id.eq.$myId,user2_id.eq.${user.id}),'
              'and(user1_id.eq.${user.id},user2_id.eq.$myId)')
          .maybeSingle();

      final convData = existing ??
          await Supabase.instance.client
              .from('conversations')
              .insert({'user1_id': myId, 'user2_id': user.id})
              .select()
              .single();

      final conv = ConversationModel(
        id: convData['id'],
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        isOnline: user.isOnline,
        unreadCount: 0,
      );
      Get.toNamed('/chat/conversation', arguments: conv);
    } catch (_) {}
  }
}

class _MatchAvatar extends StatelessWidget {
  final UserModel user;
  const _MatchAvatar({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.accent, AppColors.accent2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.4),
            blurRadius: 22,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: ClipOval(
        child: user.photoUrl != null && user.photoUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: user.photoUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback(user.name),
              )
            : _fallback(user.name),
      ),
    );
  }

  Widget _fallback(String name) => Container(
        color: AppColors.surface2,
        child: Center(
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
                fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white),
          ),
        ),
      );
}
