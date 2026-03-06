import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/home/view/story_screen.dart';

class HomeController extends GetxController {
  final _service = SupabaseService();

  final RxList<UserModel> nearbyUsers = <UserModel>[].obs;
  final RxList<StoryModel> stories = <StoryModel>[].obs;
  List<StoryModel> _allStories = [];
  final Rx<Position?> currentPosition = Rx<Position?>(null);
  final RxBool isLoadingUsers = false.obs;
  final RxBool isLoadingStories = false.obs;
  final RxBool locationError = false.obs;
  final RxDouble radiusKm = 50.0.obs;
  final RxString filterMode = 'all'.obs;
  // Filtres avancés
  final RxString filterGender = 'tous'.obs;   // tous / homme / femme
  final RxInt filterMinAge = 18.obs;
  final RxInt filterMaxAge = 50.obs;
  final RxDouble filterDistance = 50.0.obs;   // en km

  @override
  void onInit() {
    super.onInit();
    _service.setOnline(true);
    // Charge les profils et stories au démarrage
    loadProfiles();
    loadStories();
    // Tente la géolocalisation en parallèle
    _getLocation();
  }

  @override
  void onClose() {
    _service.setOnline(false);
    super.onClose();
  }

  // ─── PROFILS ─────────────────────────────────────────────────

  Future<void> loadProfiles() async {
    isLoadingUsers.value = true;
    try {
      final profiles = await _service.fetchProfiles();
      nearbyUsers.value = profiles;
      // Calcule les distances si on a la position
      if (currentPosition.value != null) {
        _updateDistances(currentPosition.value!);
      }
    } catch (_) {} finally {
      isLoadingUsers.value = false;
      isLoadingStories.value = false;
    }
  }

  Future<void> refresh() => loadProfiles();
  Future<void> loadNearbyUsers() => loadProfiles();
  Future<void> refreshProfiles() => loadProfiles();

  // ─── ACTIONS PROFIL ──────────────────────────────────────────

  void openProfile(UserModel user) {
    Get.toNamed('/profile/view', arguments: user);
  }

  void openAddStory() async {
    final result = await Get.to(() => const AddStoryScreen(),
      transition: Transition.downToUp);
    if (result == true) loadStories();
  }

  void openStory(StoryModel story) {
    // Récupère toutes les stories de cet utilisateur triées par date
    final userStories = _allStories
      .where((s) => s.userId == story.userId)
      .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    Get.to(() => StoryViewerScreen(
      stories: userStories.isEmpty ? [story] : userStories,
      initialIndex: 0,
    ), transition: Transition.fadeIn);
  }

  // Supprime une story
  Future<void> deleteStory(String storyId) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      // Supprime de la BDD
      await Supabase.instance.client.from('stories')
        .delete().eq('id', storyId).eq('user_id', uid!);
      // Recharge
      await loadStories();
      Get.snackbar('Story supprimee', '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1A2E),
        colorText: Colors.white,
        duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('deleteStory error: \$e');
    }
  }

  // ─── FILTRES ─────────────────────────────────────────────────

  // ─── STORIES ─────────────────────────────────────────────────

  Future<void> loadStories() async {
    try {
      isLoadingStories.value = true;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final data = await Supabase.instance.client
        .from('stories')
        .select('*, profiles(name, photo_url)')
        .gt('expires_at', DateTime.now().toIso8601String())
        .order('created_at', ascending: false);

      // Parse toutes les stories
      final allStories = (data as List).map((row) {
        final profile = row['profiles'] as Map<String, dynamic>?;
        final viewedBy = (row['viewed_by'] as List?)
          ?.map((e) => e.toString()).toList() ?? [];
        return StoryModel(
          id: row['id'],
          userId: row['user_id'],
          userName: profile?['name'] ?? 'Utilisateur',
          userPhotoUrl: profile?['photo_url'],
          mediaUrl: row['media_url'],
          isVideo: row['is_video'] ?? false,
          caption: row['caption'],
          createdAt: DateTime.parse(row['created_at']),
          expiresAt: DateTime.parse(row['expires_at']),
          viewedBy: viewedBy,
          isSeen: uid != null && viewedBy.contains(uid),
        );
      }).toList();

      // Garde toutes les stories mais trie par user (plus récentes en premier)
      // La bulle affiche la plus récente, le viewer montre toutes les stories du user
      final Map<String, StoryModel> latestByUser = {};
      for (final s in allStories) {
        if (!latestByUser.containsKey(s.userId) ||
            s.createdAt.isAfter(latestByUser[s.userId]!.createdAt)) {
          latestByUser[s.userId] = s;
        }
      }
      // Stocke toutes les stories pour le viewer
      _allStories = allStories;
      stories.value = latestByUser.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      debugPrint('loadStories error: \$e');
    } finally {
      isLoadingStories.value = false;
    }
  }

  void setFilter(String mode) => filterMode.value = mode;
  void setRadius(double km) { radiusKm.value = km; loadProfiles(); }

  List<UserModel> get filteredUsers {
    List<UserModel> result = nearbyUsers.toList();

    // Filtre mode de base
    if (filterMode.value == 'online') {
      result = result.where((u) => u.isOnline).toList();
    } else if (filterMode.value == 'nearby') {
      result = result.where((u) =>
        u.distanceMeters != null && u.distanceMeters! < 500).toList();
    }

    // Filtre sexe
    if (filterGender.value != 'tous') {
      result = result.where((u) =>
        u.gender?.toLowerCase() == filterGender.value).toList();
    }

    // Filtre âge
    result = result.where((u) =>
      u.age >= filterMinAge.value && u.age <= filterMaxAge.value).toList();

    // Filtre distance
    result = result.where((u) =>
      u.distanceMeters == null ||
      u.distanceMeters! <= filterDistance.value * 1000).toList();

    return result;
  }

  void applyFilters({
    String? gender,
    int? minAge,
    int? maxAge,
    double? distance,
  }) {
    if (gender != null) filterGender.value = gender;
    if (minAge != null) filterMinAge.value = minAge;
    if (maxAge != null) filterMaxAge.value = maxAge;
    if (distance != null) filterDistance.value = distance;
  }

  // ─── GÉOLOCALISATION ─────────────────────────────────────────

  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        locationError.value = true;
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        locationError.value = true;
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      currentPosition.value = position;
      locationError.value = false;
      await _service.updateLocation(position.latitude, position.longitude);
      _updateDistances(position);
    } catch (_) {
      // Localisation échouée mais on affiche quand même les profils
      locationError.value = false;
    }
  }

  void _updateDistances(Position position) {
    nearbyUsers.value = nearbyUsers.map((user) {
      if (user.latitude == null || user.longitude == null) return user;
      final dist = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        user.latitude!, user.longitude!,
      );
      return user.copyWith(distanceMeters: dist);
    }).toList();
    nearbyUsers.sort((a, b) =>
      (a.distanceMeters ?? 99999).compareTo(b.distanceMeters ?? 99999));
  }

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}