import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ✅ Système de "suivre" un compte (indépendant du match/like)
/// "Ami" = suivi mutuel (je le suis ET il me suit)
/// "Compte suivi" = je le suis (mutuel ou non)
class FollowController extends GetxController {
  final _sb = Supabase.instance.client;

  final RxSet<String> followingIds = <String>{}.obs; // gens que je suis
  final RxSet<String> followerIds = <String>{}.obs; // gens qui me suivent
  final RxBool isLoading = true.obs;

  final Set<String> _pending = {};

  String? get _myUid => _sb.auth.currentUser?.id;

  @override
  void onInit() {
    super.onInit();
    loadFollowData();
  }

  bool isFollowing(String userId) => followingIds.contains(userId);

  /// ✅ Ami = suivi mutuel
  bool isFriend(String userId) =>
      followingIds.contains(userId) && followerIds.contains(userId);

  Future<void> loadFollowData() async {
    final uid = _myUid;
    if (uid == null) {
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    try {
      final results = await Future.wait([
        _sb.from('follows').select('followed_id').eq('follower_id', uid),
        _sb.from('follows').select('follower_id').eq('followed_id', uid),
      ]);
      final following = results[0] as List;
      final followers = results[1] as List;
      followingIds.value =
          following.map((r) => r['followed_id'] as String).toSet();
      followerIds.value =
          followers.map((r) => r['follower_id'] as String).toSet();
    } catch (e) {
      Get.log('FollowController.loadFollowData error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> toggleFollow(String targetId) async {
    final uid = _myUid;
    if (uid == null || uid == targetId) return;
    if (_pending.contains(targetId)) return;
    _pending.add(targetId);

    final wasFollowing = followingIds.contains(targetId);
    // Optimiste
    if (wasFollowing) {
      followingIds.remove(targetId);
    } else {
      followingIds.add(targetId);
    }

    try {
      if (wasFollowing) {
        await _sb
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('followed_id', targetId);
      } else {
        await _sb.from('follows').insert({
          'follower_id': uid,
          'followed_id': targetId,
        });
      }
    } catch (e) {
      // rollback
      if (wasFollowing) {
        followingIds.add(targetId);
      } else {
        followingIds.remove(targetId);
      }
      Get.log('FollowController.toggleFollow error: $e');
    } finally {
      _pending.remove(targetId);
    }
  }
}
