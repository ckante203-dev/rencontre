import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/shared/models/user_model.dart';

class HomeController extends GetxController with WidgetsBindingObserver {
  final _service = SupabaseService();

  final RxList<UserModel> _allUsers = <UserModel>[].obs;
  final RxList<UserModel> profiles = <UserModel>[].obs;
  final RxBool isLoading = false.obs;
  RxBool get isLoadingUsers => isLoading;

  final Rx<UserModel?> _myProfile = Rx<UserModel?>(null);
  UserModel? get myProfile => _myProfile.value;

  final RxList<StoryModel> _allStories = <StoryModel>[].obs;
  final Set<String> _viewedStoryIds = {};

  Timer? _heartbeatTimer;

  // ✅ Heartbeat toutes les 60 secondes
  // → last_seen mis à jour toutes les 60s
  // → Si l'app crashe ou est fermée, last_seen > 3min → affiché HORS LIGNE automatiquement
  static const _heartbeatInterval = Duration(seconds: 60);

  RealtimeChannel? _onlineChannel;

  List<StoryModel> get stories {
    final seen = <String>{};
    final result = <StoryModel>[];
    for (final s
        in _allStories.where((s) => s.userId != _myUid && s.isActive)) {
      if (!seen.contains(s.userId)) {
        seen.add(s.userId);
        result.add(s.copyWith(isSeen: _viewedStoryIds.contains(s.id)));
      }
    }
    return result;
  }

  StoryModel? get myActiveStory =>
      _allStories.where((s) => s.userId == _myUid && s.isActive).firstOrNull;

  double? _myLat;
  double? _myLng;

  final RxBool locationError = false.obs;
  final RxString filterMode = 'all'.obs;
  final RxString filterGender = 'tous'.obs;
  final RxDouble filterDistance = 50.0.obs;

  static const double _storyRadiusKm = 50.0;

  String? get _myUid => _service.currentUserId;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _loadMyProfile();
    await _locateMe();
    // ✅ setOnline(true) dès le démarrage
    await _service.setOnline(true);
    _startHeartbeat();
    _subscribeToOnlineChanges();
    await _ensureFcmToken();
    await loadProfiles();
    await loadStories();
  }

  // ✅ Écoute Realtime les changements is_online + last_seen des autres profils
  void _subscribeToOnlineChanges() {
    _onlineChannel = Supabase.instance.client
        .channel('profiles:online')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final updated = payload.newRecord;
            final userId = updated['id'] as String?;
            if (userId == null || userId == _myUid) return;

            // ✅ Utiliser isReallyOnline — pas juste le booléen brut
            final isOnline = SupabaseService.isReallyOnline(
                updated['is_online'], updated['last_seen']);

            final idx = profiles.indexWhere((u) => u.id == userId);
            if (idx != -1) {
              profiles[idx] = profiles[idx].copyWith(isOnline: isOnline);
            }
            final idx2 = _allUsers.indexWhere((u) => u.id == userId);
            if (idx2 != -1) {
              _allUsers[idx2] = _allUsers[idx2].copyWith(isOnline: isOnline);
            }
          },
        )
        .subscribe();
  }

  Future<void> _ensureFcmToken() async {
    try {
      final uid = _myUid;
      if (uid == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', uid);
      debugPrint('✅ FCM token mis à jour: ${token.substring(0, 20)}...');
    } catch (e) {
      debugPrint('_ensureFcmToken error: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      // ✅ heartbeat() = update last_seen uniquement — plus léger que setOnline()
      await _service.heartbeat();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // ✅ App au premier plan → en ligne IMMÉDIATEMENT
        _service.setOnline(true);
        _startHeartbeat();
        _ensureFcmToken();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // ✅ App en arrière-plan → hors ligne IMMÉDIATEMENT
        // Plus de délai — avec last_seen la règle des 3 min gère le reste
        _heartbeatTimer?.cancel();
        _service.setOnline(false);
        break;
    }
  }

  Future<void> _loadMyProfile() async {
    _myProfile.value = await _service.fetchMyProfile();
  }

  Future<void> _locateMe() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        locationError.value = true;
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          locationError.value = true;
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        locationError.value = true;
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      _myLat = pos.latitude;
      _myLng = pos.longitude;
      locationError.value = false;
      await _service.updateLocation(pos.latitude, pos.longitude);
    } catch (e) {
      locationError.value = true;
      debugPrint('_locateMe error: $e');
    }
  }

  Future<void> loadProfiles() async {
    isLoading.value = true;
    try {
      final myProfile = _myProfile.value;
      final fetched = await _service.fetchProfiles(
        genderFilter: myProfile?.lookingFor,
        myLat: _myLat,
        myLng: _myLng,
      );
      _allUsers.value = fetched;
      profiles.value = fetched;
    } catch (e) {
      debugPrint('loadProfiles error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void removeUser(String userId) {
    _allUsers.removeWhere((u) => u.id == userId);
    profiles.removeWhere((u) => u.id == userId);
  }

  void setFilter(String mode) => filterMode.value = mode;

  List<UserModel> get filteredUsers {
    return profiles.where((u) {
      if (filterMode.value == 'online' && !u.isOnline) return false;
      if (filterMode.value == 'nearby') {
        final dist = u.distanceMeters;
        if (dist == null || dist > filterDistance.value * 1000) return false;
      }
      if (filterGender.value != 'tous') {
        final g = u.gender?.toLowerCase();
        if (g != filterGender.value.toLowerCase() &&
            g != null &&
            g != 'non précisé' &&
            g.isNotEmpty) {
          return false;
        }
      }
      if (filterMode.value != 'nearby') {
        final dist = u.distanceMeters;
        if (dist != null && dist > filterDistance.value * 1000) return false;
      }
      return true;
    }).toList();
  }

  static String formatDistance(double? meters) {
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  void openProfile(UserModel user) =>
      Get.toNamed('/profile/view', arguments: user);

  void openLocationSettings() => Geolocator.openLocationSettings();

  // ─── STORIES ────────────────────────────────────────────────────

  Future<void> loadStories() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('stories')
          .select('*, profiles(name, photo_url, latitude, longitude)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false);

      final Set<String> chattedUserIds = await _fetchChattedUserIds(uid);
      final stories = <StoryModel>[];

      for (final row in (data as List)) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        final authorId = row['user_id'] as String? ?? '';

        if (authorId == uid) {
          stories.add(_rowToStory(row, profile));
          continue;
        }

        final bool hasChatted = chattedUserIds.contains(authorId);
        final bool isNearby = _isNearby(profile);
        if (hasChatted && isNearby) {
          stories.add(_rowToStory(row, profile, hasChatted: true));
        }
      }

      _allStories.value = stories;
    } catch (e) {
      debugPrint('loadStories error: $e');
    }
  }

  Future<Set<String>> _fetchChattedUserIds(String uid) async {
    try {
      final data = await Supabase.instance.client
          .from('conversations')
          .select('user1_id, user2_id')
          .or('user1_id.eq.$uid,user2_id.eq.$uid');
      final Set<String> ids = {};
      for (final row in (data as List)) {
        final u1 = row['user1_id'] as String? ?? '';
        final u2 = row['user2_id'] as String? ?? '';
        if (u1 != uid) ids.add(u1);
        if (u2 != uid) ids.add(u2);
      }
      return ids;
    } catch (e) {
      debugPrint('_fetchChattedUserIds error: $e');
      return {};
    }
  }

  bool _isNearby(Map<String, dynamic>? profile) {
    if (_myLat == null || _myLng == null) return true;
    final lat = profile?['latitude']?.toDouble();
    final lng = profile?['longitude']?.toDouble();
    if (lat == null || lng == null) return false;
    return _distanceKm(_myLat!, _myLng!, lat, lng) <= _storyRadiusKm;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = (dLat / 2) * (dLat / 2) +
        _deg2rad(lat1) * _deg2rad(lat2) * (dLon / 2) * (dLon / 2);
    return r * 2 * (a < 1 ? a : 1);
  }

  double _deg2rad(double deg) => deg * 3.141592653589793 / 180;

  StoryModel _rowToStory(
      Map<String, dynamic> row, Map<String, dynamic>? profile,
      {bool hasChatted = false}) {
    final viewedBy = List<String>.from(row['viewed_by'] ?? []);
    final uid = _myUid ?? '';
    double? distanceKm;
    if (_myLat != null && _myLng != null) {
      final lat = profile?['latitude']?.toDouble();
      final lng = profile?['longitude']?.toDouble();
      if (lat != null && lng != null) {
        distanceKm = _distanceKm(_myLat!, _myLng!, lat, lng);
      }
    }
    return StoryModel(
      id: row['id'] ?? '',
      userId: row['user_id'] ?? '',
      userName: profile?['name'] ?? 'Utilisateur',
      userPhotoUrl: profile?['photo_url'],
      mediaUrl: row['media_url'] ?? '',
      caption: row['caption'],
      isVideo: row['is_video'] ?? false,
      isSeen: viewedBy.contains(uid) || _viewedStoryIds.contains(row['id']),
      createdAt: DateTime.parse(row['created_at']),
      expiresAt: DateTime.parse(row['expires_at']),
      viewedBy: viewedBy,
      distanceKm: distanceKm,
      hasChatted: hasChatted,
    );
  }

  void markStoryAsSeen(String storyId) {
    _viewedStoryIds.add(storyId);
    final idx = _allStories.indexWhere((s) => s.id == storyId);
    if (idx >= 0) _allStories[idx] = _allStories[idx].copyWith(isSeen: true);
    _markStorySeenInDb(storyId);
  }

  Future<void> _markStorySeenInDb(String storyId) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('stories')
          .select('viewed_by')
          .eq('id', storyId)
          .maybeSingle();
      if (row == null) return;
      final List<String> viewedBy = List<String>.from(row['viewed_by'] ?? []);
      if (!viewedBy.contains(uid)) {
        viewedBy.add(uid);
        await Supabase.instance.client
            .from('stories')
            .update({'viewed_by': viewedBy}).eq('id', storyId);
      }
    } catch (e) {
      debugPrint('_markStorySeenInDb error: $e');
    }
  }

  bool userHasActiveStory(String userId) =>
      _allStories.any((s) => s.userId == userId && s.isActive);

  bool userStoryIsSeen(String userId) {
    final userStories =
        _allStories.where((s) => s.userId == userId && s.isActive);
    if (userStories.isEmpty) return true;
    return userStories.every((s) => s.isSeen || _viewedStoryIds.contains(s.id));
  }

  List<StoryModel> storiesForUser(String userId) =>
      _allStories.where((s) => s.userId == userId && s.isActive).toList();

  Future<void> setOnline(bool online) async => await _service.setOnline(online);

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _onlineChannel?.unsubscribe();
    super.onClose();
  }
}
