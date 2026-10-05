import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/features/notifications/model/notification_model.dart';

class NotificationController extends GetxController {
  final _sb = Supabase.instance.client;

  final RxList<NotificationModel> notifications = <NotificationModel>[].obs;
  final RxInt unreadCount = 0.obs;
  final RxBool isLoading = false.obs;
  // Non lues au moment d'ouvrir l'écran : restent surlignées pendant la
  // visite, même si elles sont déjà marquées « vues » (façon Instagram)
  final RxSet<String> nouvellesCetteVisite = <String>{}.obs;

  RealtimeChannel? _channel;

  String? get _myUid => _sb.auth.currentUser?.id;

  @override
  void onInit() {
    super.onInit();
    loadNotifications();
    _subscribeRealtime();
  }

  @override
  void onClose() {
    _channel?.unsubscribe();
    super.onClose();
  }

  Future<void> loadNotifications() async {
    final uid = _myUid;
    if (uid == null) return;
    isLoading.value = true;
    try {
      final data = await _sb
          .from('notifications')
          .select('*, profiles!notifications_actor_id_fkey(name, photo_url)')
          .eq('user_id', uid)
          // Historique de 30 jours (au-delà : supprimées, SQL 045)
          .gte(
              'created_at',
              DateTime.now()
                  .toUtc()
                  .subtract(const Duration(days: 30))
                  .toIso8601String())
          .order('created_at', ascending: false)
          .limit(100);

      notifications.value =
          (data as List).map((row) => _rowToModel(row)).toList();
      _updateUnreadCount();
    } catch (e) {
      Get.log('NotificationController.loadNotifications error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _subscribeRealtime() {
    final uid = _myUid;
    if (uid == null) return;
    _channel = _sb
        .channel('notifications:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (_) => loadNotifications(),
        )
        .subscribe();
  }

  NotificationModel _rowToModel(Map<String, dynamic> row) {
    final actor = row['profiles'] as Map<String, dynamic>?;
    return NotificationModel(
      id: row['id'],
      userId: row['user_id'],
      actorId: row['actor_id'],
      actorName: actor?['name'] ?? 'Quelqu\'un',
      actorPhotoUrl: actor?['photo_url'],
      type: row['type'] ?? '',
      referenceId: row['reference_id'],
      preview: row['preview'],
      isRead: row['is_read'] ?? false,
      createdAt: DateTime.parse(row['created_at']),
    );
  }

  void _updateUnreadCount() {
    unreadCount.value = notifications.where((n) => !n.isRead).length;
  }

  Future<void> markAsRead(String id) async {
    final idx = notifications.indexWhere((n) => n.id == id);
    if (idx == -1 || notifications[idx].isRead) return;
    notifications[idx] = notifications[idx].copyWith(isRead: true);
    _updateUnreadCount();
    try {
      await _sb.from('notifications').update({'is_read': true}).eq('id', id);
    } catch (e) {
      Get.log('markAsRead error: $e');
    }
  }

  /// Ouverture de l'écran Notifications : tout passe en « vu » (le badge
  /// de la cloche repart à 0), les nouvelles restent surlignées.
  Future<void> ouvrirEcran() async {
    await loadNotifications();
    nouvellesCetteVisite
      ..clear()
      ..addAll(notifications.where((n) => !n.isRead).map((n) => n.id));
    if (nouvellesCetteVisite.isEmpty) return;
    notifications.value =
        notifications.map((n) => n.copyWith(isRead: true)).toList();
    unreadCount.value = 0;
    try {
      await _sb.rpc('marquer_notifications_lues');
    } catch (e) {
      // Script 045 pas encore exécuté : mise à jour directe
      Get.log('marquer_notifications_lues : $e');
      final uid = _myUid;
      if (uid == null) return;
      try {
        await _sb
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', uid)
            .eq('is_read', false);
      } catch (e2) {
        Get.log('markAllAsRead error: $e2');
      }
    }
  }

  Future<void> markAllAsRead() async {
    final uid = _myUid;
    if (uid == null) return;
    final unread = notifications.where((n) => !n.isRead).toList();
    if (unread.isEmpty) return;
    notifications.value =
        notifications.map((n) => n.copyWith(isRead: true)).toList();
    unreadCount.value = 0;
    try {
      await _sb
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (e) {
      Get.log('markAllAsRead error: $e');
    }
  }
}
