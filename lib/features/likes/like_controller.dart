import 'package:flutter/material.dart' show Color;
import 'package:rencontre/core/services/avis_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:rencontre/features/likes/match_dialog.dart' show MatchDialog;
import 'package:rencontre/core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════
//  LIKE CONTROLLER
// ══════════════════════════════════════════════════════════════════

class LikeController extends GetxController {
  final _sb = Supabase.instance.client;

  final RxSet<String> likedUserIds = <String>{}.obs;
  final RxSet<String> matchedUserIds = <String>{}.obs;
  final RxBool isLoading = false.obs;

  String? get _myId => _sb.auth.currentUser?.id;

  @override
  void onInit() {
    super.onInit();
    _loadMyLikes();
    _loadMyMatches();
  }

  Future<void> _loadMyLikes() async {
    final myId = _myId;
    if (myId == null) return;
    try {
      final data =
          await _sb.from('likes').select('to_user_id').eq('from_user_id', myId);
      likedUserIds.assignAll(
          (data as List).map((r) => r['to_user_id'] as String));
    } catch (_) {}
  }

  Future<void> _loadMyMatches() async {
    final myId = _myId;
    if (myId == null) return;
    try {
      final data = await _sb
          .from('matches')
          .select('user1_id, user2_id')
          .or('user1_id.eq.$myId,user2_id.eq.$myId');
      matchedUserIds.assignAll((data as List).map((r) {
        final u1 = r['user1_id'] as String;
        final u2 = r['user2_id'] as String;
        return u1 == myId ? u2 : u1;
      }));
    } catch (_) {}
  }

  bool hasLiked(String userId) => likedUserIds.contains(userId);
  bool hasMatch(String userId) => matchedUserIds.contains(userId);

  Future<void> toggleLike(UserModel targetUser) async {
    final myId = _myId;
    if (myId == null || myId == targetUser.id) return;

    if (hasMatch(targetUser.id)) {
      Get.snackbar(
        '💘 Match !'.tr,
        'Vous êtes en match — impossible de retirer le like'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: AppColors.textPrimary,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    isLoading.value = true;
    try {
      if (hasLiked(targetUser.id)) {
        await _sb
            .from('likes')
            .delete()
            .eq('from_user_id', myId)
            .eq('to_user_id', targetUser.id);
        likedUserIds.remove(targetUser.id);
        HapticFeedback.lightImpact();
      } else {
        await _sb.from('likes').upsert({
          'from_user_id': myId,
          'to_user_id': targetUser.id,
        });
        likedUserIds.add(targetUser.id);
        HapticFeedback.mediumImpact();

        final mutual = await _sb
            .from('likes')
            .select()
            .eq('from_user_id', targetUser.id)
            .eq('to_user_id', myId)
            .maybeSingle();

        final isMatch = mutual != null;

        if (isMatch) {
          await _createMatch(myId, targetUser.id);
          matchedUserIds.add(targetUser.id);
          _showMatchPopup(targetUser);
        }
        // ✅ La notification push du like / match est envoyée par la base
        // (trigger notify_new_like → fonction dynamic-processor). L'app
        // appelait en plus « send-like-notification », qui n'existe pas.
      }
    } catch (_) {
    } finally {
      isLoading.value = false;
    }
  }

  /// ⭐ Super Like : 1 par jour (5 avec Premium), vérifié par la base
  /// (fonction envoyer_super_like, SQL 053). Retourne true si envoyé.
  Future<bool> superLike(UserModel targetUser) async {
    final myId = _myId;
    if (myId == null || myId == targetUser.id) return false;
    if (hasLiked(targetUser.id)) {
      _info('⭐ Super Like', 'Tu as déjà liké ce profil'.tr);
      return false;
    }
    try {
      final r = await _sb.rpc('envoyer_super_like',
          params: {'p_to': targetUser.id}) as String?;
      if (r != 'ok') {
        _info(
            '⭐ Super Like',
            r == 'limite'
                ? (ControleurProfil.estPremiumMaintenant()
                    ? 'Tu as utilisé tes 5 Super Likes du jour'.tr
                    : 'Ton Super Like du jour est utilisé. Premium : 5 par jour 👑'.tr)
                : 'Action impossible, réessaie'.tr);
        return false;
      }
      likedUserIds.add(targetUser.id);
      HapticFeedback.heavyImpact();
      final mutual = await _sb
          .from('likes')
          .select('from_user_id')
          .eq('from_user_id', targetUser.id)
          .eq('to_user_id', myId)
          .maybeSingle();
      if (mutual != null) {
        await _createMatch(myId, targetUser.id);
        matchedUserIds.add(targetUser.id);
        _showMatchPopup(targetUser);
      } else {
        _info('⭐ Super Like', 'Envoyé ! @nom le verra en premier'.trParams({'nom': targetUser.name}));
      }
      return true;
    } catch (e) {
      debugPrint('Super Like : $e');
      _info('⭐ Super Like', 'Vérifie ta connexion et réessaie'.tr);
      return false;
    }
  }

  void _info(String titre, String texte) => Get.snackbar(titre, texte,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 3));

  Future<void> _createMatch(String myId, String otherId) async {
    final u1 = myId.compareTo(otherId) < 0 ? myId : otherId;
    final u2 = myId.compareTo(otherId) < 0 ? otherId : myId;
    try {
      await _sb.from('matches').upsert({'user1_id': u1, 'user2_id': u2});
    } catch (_) {}
  }

  void _showMatchPopup(UserModel matchedUser) {
    // ✅ fromUserId passé pour que le clic sur la notif ouvre le bon profil
    NotificationService.showMatchNotification(
      userName: matchedUser.name,
      userPhoto: matchedUser.photoUrl,
      fromUserId: matchedUser.id,
    );
    Get.dialog(
      MatchDialog(matchedUser: matchedUser),
      barrierDismissible: true,
      barrierColor: const Color(0xD9000000),
    ).then((_) => AvisService.momentPositif()); // après le match : bon moment pour une note
  }
}
