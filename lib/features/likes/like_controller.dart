import 'package:flutter/material.dart' show Color, Colors;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:rencontre/features/likes/match_dialog.dart' show MatchDialog;

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
      likedUserIds.value =
          (data as List).map((r) => r['to_user_id'] as String).toSet();
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
      matchedUserIds.value = (data as List).map((r) {
        final u1 = r['user1_id'] as String;
        final u2 = r['user2_id'] as String;
        return u1 == myId ? u2 : u1;
      }).toSet();
    } catch (_) {}
  }

  bool hasLiked(String userId) => likedUserIds.contains(userId);
  bool hasMatch(String userId) => matchedUserIds.contains(userId);

  Future<void> toggleLike(UserModel targetUser) async {
    final myId = _myId;
    if (myId == null || myId == targetUser.id) return;

    if (hasMatch(targetUser.id)) {
      Get.snackbar(
        '💘 Match !',
        'Vous êtes en match — impossible de retirer le like',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF13131A),
        colorText: Colors.white,
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

        await _sendLikeNotification(
          fromUserId: myId,
          toUserId: targetUser.id,
          isMatch: isMatch,
        );
      }
    } catch (_) {
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _createMatch(String myId, String otherId) async {
    final u1 = myId.compareTo(otherId) < 0 ? myId : otherId;
    final u2 = myId.compareTo(otherId) < 0 ? otherId : myId;
    try {
      await _sb.from('matches').upsert({'user1_id': u1, 'user2_id': u2});
    } catch (_) {}
  }

  Future<void> _sendLikeNotification({
    required String fromUserId,
    required String toUserId,
    required bool isMatch,
  }) async {
    try {
      await _sb.functions.invoke(
        'send-like-notification',
        body: {
          'from_user_id': fromUserId,
          'to_user_id': toUserId,
          'is_match': isMatch,
        },
      );
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
    );
  }
}
