import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileInsightsController extends GetxController {
  final _sb = Supabase.instance.client;

  final RxInt viewersCount = 0.obs;
  final RxInt likersCount = 0.obs;
  final RxInt matchesCount = 0.obs;
  final RxBool isLoading = false.obs;

  String? get _myId => _sb.auth.currentUser?.id;

  @override
  void onInit() {
    super.onInit();
    loadCounts();
  }

  Future<void> loadCounts() async {
    final myId = _myId;
    if (myId == null) return;
    isLoading.value = true;
    try {
      await Future.wait([
        _loadViewersCount(myId),
        _loadLikersCount(myId),
        _loadMatchesCount(myId),
      ]);
    } catch (_) {
      // ✅ Sans catch, une erreur réseau devenait une exception non gérée.
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadViewersCount(String myId) async {
    // ✅ RPC (fonctionne même quand la liste des vues sera réservée aux
    // Premium) ; repli sur le comptage direct si la fonction n'existe pas.
    try {
      final n = await _sb.rpc('compter_vues');
      if (n is int) {
        viewersCount.value = n;
        return;
      }
    } catch (_) {}
    final res = await _sb
        .from('profile_views')
        .select('viewer_id')
        .eq('viewed_id', myId)
        .count(CountOption.exact);
    viewersCount.value = res.count;
  }

  // ✅ Vrai nombre de matchs (profiles.matches_count n'est jamais mis à jour)
  Future<void> _loadMatchesCount(String myId) async {
    try {
      final res = await _sb
          .from('matches')
          .select('user1_id')
          .or('user1_id.eq.$myId,user2_id.eq.$myId')
          .count(CountOption.exact);
      matchesCount.value = res.count;
    } catch (_) {}
  }

  Future<void> _loadLikersCount(String myId) async {
    final res = await _sb
        .from('likes')
        .select('from_user_id')
        .eq('to_user_id', myId)
        .count(CountOption.exact);
    likersCount.value = res.count;
  }
}
