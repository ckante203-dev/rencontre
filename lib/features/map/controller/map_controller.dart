import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class MapController extends GetxController {
  final _service = SupabaseService();

  // ── Position ─────────────────────────────────────────────────
  final Rx<LatLng?> myPosition = Rx<LatLng?>(null);
  final RxList<UserModel> profiles = <UserModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool locationError = false.obs;

  // ── Filtres ──────────────────────────────────────────────────
  final RxDouble filterDistance = 10.0.obs;
  // ✅ Rayon maximal du slider de distance (map_screen : max 50 km),
  // utilisé pour la zone de recherche en base.
  static const double _rayonRechercheMaxKm = 50.0;
  final RxString filterStatus = 'tous'.obs;

  // ── Vue : carte ou liste ─────────────────────────────────────
  final RxBool showList = false.obs;

  // ── Recherche ville ──────────────────────────────────────────
  final RxBool showSearch = false.obs;
  final searchController = TextEditingController();
  final RxList<Map<String, dynamic>> searchResults =
      <Map<String, dynamic>>[].obs;
  final RxBool isSearching = false.obs;

  // ── Préférences carte ────────────────────────────────────────
  final RxBool mapVisible = true.obs;
  final RxBool isGhost = false.obs;
  final RxBool isPremium = false.obs;
  final RxString positionPrecision = 'flouted'.obs;
  final Rx<DateTime?> mapInvisibleUntil = Rx<DateTime?>(null);
  final Rx<DateTime?> ghostUntil = Rx<DateTime?>(null);
  final RxBool isSavingPrefs = false.obs;

  // ── Computed ─────────────────────────────────────────────────

  bool get estInvisible {
    if (!mapVisible.value) return true;
    final until = mapInvisibleUntil.value;
    if (until != null && DateTime.now().isBefore(until)) return true;
    return false;
  }

  bool get estFantome {
    if (!isPremium.value) return false;
    if (!isGhost.value) return false;
    final until = ghostUntil.value;
    if (until != null && DateTime.now().isAfter(until)) return false;
    return true;
  }

  bool get peutVoirLaCarte => !estInvisible || estFantome;

  List<UserModel> get filteredProfiles {
    if (!peutVoirLaCarte) return [];
    return profiles.where((u) {
      if (filterStatus.value == 'online' && !u.isOnline) return false;
      if (u.distanceMeters != null &&
          u.distanceMeters! > filterDistance.value * 1000) return false;
      return true;
    }).toList();
  }

  String get invisibleDepuis {
    final until = mapInvisibleUntil.value;
    if (until == null) return '';
    final diff = until.difference(DateTime.now());
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    return '${diff.inHours}h';
  }

  @override
  void onInit() {
    super.onInit();
    _init();
  }

  @override
  void onClose() {
    searchController.dispose();
    super.onClose();
  }

  Future<void> _init() async {
    await _chargerPreferences();
    await _getLocation();
    await loadProfiles();
  }

  Future<void> refresh() async {
    await _chargerPreferences();
    await _getLocation();
    await loadProfiles();
  }

  void toggleView() => showList.value = !showList.value;
  void toggleSearch() {
    showSearch.value = !showSearch.value;
    if (!showSearch.value) {
      searchController.clear();
      searchResults.clear();
    }
  }

  // ─── RECHERCHE VILLE ─────────────────────────────────────────

  Future<LatLng?> rechercherVille(String query) async {
    if (query.trim().isEmpty) return null;
    isSearching.value = true;
    try {
      final url =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&countrycodes=ci,sn,ml,bf,bj,tg,cm,gn';
      // ✅ Nominatim (OpenStreetMap) directement : la fonction serveur
      // « geocode » appelée avant n'existe pas, la recherche ne trouvait
      // jamais rien. Nominatim exige un User-Agent identifiant l'app.
      final res = await http.get(Uri.parse(url),
          headers: {'User-Agent': 'Zamu/1.0 (support.snapmeet@gmail.com)'});
      if (res.statusCode != 200) return null;
      final results = jsonDecode(res.body) as List;
      if (results.isEmpty) return null;
      final first = results.first as Map<String, dynamic>;
      final lat = double.tryParse('${first['lat']}');
      final lon = double.tryParse('${first['lon']}');
      if (lat == null || lon == null) return null;
      return LatLng(lat, lon);
    } catch (e) {
      debugPrint('rechercherVille error: $e');
      return null;
    } finally {
      isSearching.value = false;
    }
  }

  // ─── PRÉFÉRENCES CARTE ───────────────────────────────────────

  Future<void> _chargerPreferences() async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select(
              'map_visible, is_ghost, is_premium, position_precision, map_invisible_until, ghost_until')
          .eq('id', uid)
          .maybeSingle();
      if (data == null) return;
      mapVisible.value = data['map_visible'] ?? true;
      isGhost.value = data['is_ghost'] ?? false;
      isPremium.value = data['is_premium'] ?? false;
      positionPrecision.value = data['position_precision'] ?? 'flouted';
      mapInvisibleUntil.value = data['map_invisible_until'] != null
          ? _parseDbDate(data['map_invisible_until'])
          : null;
      ghostUntil.value = data['ghost_until'] != null
          ? _parseDbDate(data['ghost_until'])
          : null;
    } catch (e) {
      debugPrint('_chargerPreferences error: $e');
    }
  }

  Future<void> setInvisible(Duration? duree) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    isSavingPrefs.value = true;
    try {
      DateTime? until;
      bool visible = true;
      if (duree == null) {
        visible = false;
        until = null;
      } else {
        visible = true;
        until = DateTime.now().add(duree);
      }
      await Supabase.instance.client.from('profiles').update({
        'map_visible': visible,
        // ✅ UTC explicite : un horodatage local "naïf" est interprété
        // comme UTC par Postgres (décalage du fuseau).
        'map_invisible_until': until?.toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
      mapVisible.value = visible;
      mapInvisibleUntil.value = until;
      _snackSuccess(duree == null
          ? 'Tu es invisible sur la carte'
          : 'Invisible pendant ${_formatDuree(duree)}');
    } catch (e) {
      debugPrint('setInvisible error: $e');
      _snackError('Impossible de modifier la visibilité');
    } finally {
      isSavingPrefs.value = false;
    }
  }

  Future<void> setVisible() async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    isSavingPrefs.value = true;
    try {
      await Supabase.instance.client.from('profiles').update({
        'map_visible': true,
        'map_invisible_until': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(), // ✅ UTC
      }).eq('id', uid);
      mapVisible.value = true;
      mapInvisibleUntil.value = null;
      _snackSuccess('Tu es visible sur la carte');
    } catch (e) {
      debugPrint('setVisible error: $e');
      _snackError('Impossible de modifier la visibilité');
    } finally {
      isSavingPrefs.value = false;
    }
  }

  Future<void> toggleGhost() async {
    if (!isPremium.value) {
      _showPremiumDialog();
      return;
    }
    final uid = _service.currentUserId;
    if (uid == null) return;
    isSavingPrefs.value = true;
    try {
      final newGhost = !isGhost.value;
      final until =
          newGhost ? DateTime.now().add(const Duration(days: 30)) : null;
      await Supabase.instance.client.from('profiles').update({
        'is_ghost': newGhost,
        'ghost_until': until?.toUtc().toIso8601String(), // ✅ UTC
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', uid);
      isGhost.value = newGhost;
      ghostUntil.value = until;
      _snackSuccess(
          newGhost ? '👻 Mode fantôme activé' : '👻 Mode fantôme désactivé');
    } catch (e) {
      debugPrint('toggleGhost error: $e');
      _snackError('Impossible de modifier le mode fantôme');
    } finally {
      isSavingPrefs.value = false;
    }
  }

  Future<void> setPrecision(String precision) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    isSavingPrefs.value = true;
    try {
      await Supabase.instance.client.from('profiles').update({
        'position_precision': precision,
        'updated_at': DateTime.now().toUtc().toIso8601String(), // ✅ UTC
      }).eq('id', uid);
      positionPrecision.value = precision;
      _snackSuccess('Précision mise à jour');
    } catch (e) {
      debugPrint('setPrecision error: $e');
      _snackError('Impossible de modifier la précision');
    } finally {
      isSavingPrefs.value = false;
    }
  }

  void _showPremiumDialog() {
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Mode Fantôme 👻',
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontSize: 18)),
      content: Text(
          'Le mode fantôme est une fonctionnalité Premium.\n\nTu peux voir tous les profils sur la carte sans que personne ne te voit.',
          style:
              TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Fermer',
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            Get.back();
            Get.snackbar('👑 Premium', 'Bientôt disponible !',
                snackPosition: SnackPosition.TOP,
                backgroundColor: AppColors.surface,
                colorText: Colors.white);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Passer Premium 👑',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  // ─── LOCALISATION ────────────────────────────────────────────

  Future<void> _getLocation() async {
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
      myPosition.value = LatLng(pos.latitude, pos.longitude);
      locationError.value = false;
      if (!estInvisible || estFantome) {
        await _service.updateLocation(pos.latitude, pos.longitude);
      }
    } catch (e) {
      locationError.value = true;
      debugPrint('MapController _getLocation error: $e');
    }
  }

  // ─── PROFILS ─────────────────────────────────────────────────

  Future<void> loadProfiles() async {
    if (!peutVoirLaCarte) {
      profiles.clear();
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    try {
      final uid = _service.currentUserId;
      if (uid == null) return;

      final myData = await Supabase.instance.client
          .from('profiles')
          .select('blocked_users')
          .eq('id', uid)
          .maybeSingle();
      final myBlockedIds = List<String>.from(myData?['blocked_users'] ?? []);

      final blockedMeData = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .contains('blocked_users', [uid]);
      final blockedMeIds =
          (blockedMeData as List).map((r) => r['id'] as String).toList();

      final allExcluded = <String>{uid, ...myBlockedIds, ...blockedMeIds};

      final myLat = myPosition.value?.latitude;
      final myLng = myPosition.value?.longitude;

      var query = Supabase.instance.client
          .from('profiles')
          .select(
              'id, name, bio, photo_url, photo_urls, latitude, longitude, is_online, gender, looking_for, birthdate, interests, taille, poids, morphologie, lieu_rencontre, followers_count, following_count, matches_count, is_suspended, map_visible, is_ghost, is_premium, map_invisible_until, ghost_until, position_precision, show_distance')
          .eq('is_suspended', false)
          .not('latitude', 'is', null)
          .not('longitude', 'is', null);

      // ✅ Les 100 profils étaient pris au hasard (aucun filtre ni tri) :
      // les utilisateurs proches manquaient souvent. On restreint à une
      // zone englobant le rayon de recherche maximal de la carte (le
      // filtre de distance reste appliqué côté client) et on privilégie
      // les profils actifs récemment.
      if (myLat != null && myLng != null) {
        const dLat = _rayonRechercheMaxKm / 111.32;
        final cosLat = cos(_deg2rad(myLat)).abs().clamp(0.01, 1.0);
        final dLng = _rayonRechercheMaxKm / (111.32 * cosLat);
        query = query.gte('latitude', myLat - dLat).lte('latitude', myLat + dLat);
        if (myLng - dLng >= -180 && myLng + dLng <= 180) {
          query =
              query.gte('longitude', myLng - dLng).lte('longitude', myLng + dLng);
        }
      }

      final data = await query
          .order('last_seen', ascending: false, nullsFirst: false)
          .limit(100);
      final now = DateTime.now();

      final list = (data as List).where((row) {
        if (allExcluded.contains(row['id'] as String)) return false;
        final rowMapVisible = row['map_visible'] ?? true;
        final rowGhost = row['is_ghost'] ?? false;
        final rowPremium = row['is_premium'] ?? false;
        final rowInvisibleUntil = row['map_invisible_until'] != null
            ? _parseDbDate(row['map_invisible_until'])
            : null;
        if (rowGhost && rowPremium) {
          final ghostUntilRow = row['ghost_until'] != null
              ? _parseDbDate(row['ghost_until'])
              : null;
          if (ghostUntilRow == null || now.isBefore(ghostUntilRow)) {
            return false;
          }
        }
        if (!rowMapVisible && rowInvisibleUntil == null) return false;
        if (rowInvisibleUntil != null && now.isBefore(rowInvisibleUntil)) {
          return false;
        }
        return true;
      }).map((row) {
        double? distanceMeters;
        if (myLat != null && myLng != null) {
          final lat = _flouterPosition(
            (row['latitude'] as num).toDouble(),
            row['position_precision'] ?? 'flouted',
          );
          final lng = _flouterPosition(
            (row['longitude'] as num).toDouble(),
            row['position_precision'] ?? 'flouted',
          );
          distanceMeters = _distanceMeters(myLat, myLng, lat, lng);
          row = Map<String, dynamic>.from(row);
          row['latitude'] = lat;
          row['longitude'] = lng;
        }
        return _rowToUser(row, distanceMeters);
      }).toList();

      if (myLat != null && myLng != null) {
        list.sort((a, b) => (a.distanceMeters ?? double.infinity)
            .compareTo(b.distanceMeters ?? double.infinity));
      }

      profiles.value = list;
    } catch (e) {
      debugPrint('MapController loadProfiles error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  double _flouterPosition(double coord, String precision) {
    final random = Random();
    switch (precision) {
      case 'exact':
        return coord;
      case 'very_flouted':
        return coord + (random.nextDouble() - 0.5) * 0.018;
      case 'flouted':
      default:
        return coord + (random.nextDouble() - 0.5) * 0.006;
    }
  }

  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    // ✅ Haversine complète (sin/cos/atan2 manquaient : distances ~100x
    // trop petites).
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * 3.141592653589793 / 180;

  // ✅ Horodatage Supabase → DateTime. Sans indicateur de fuseau (colonne
  // `timestamp` sans tz), la valeur est en UTC : on l'indique à Dart au
  // lieu de la lire comme heure locale (les dates sont écrites en UTC).
  static DateTime? _parseDbDate(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    final hasTime = s.contains('T') || s.contains(' ');
    if (hasTime && !RegExp(r'(Z|z|[+-]\d{2}(:?\d{2})?)$').hasMatch(s)) {
      return DateTime.tryParse('${s}Z');
    }
    return DateTime.tryParse(s);
  }

  int _calcAge(dynamic birthdate) {
    if (birthdate == null) return 18;
    try {
      DateTime birth;
      if (birthdate is String) {
        if (birthdate.contains('/')) {
          final parts = birthdate.split('/');
          birth = DateTime(
              int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        } else {
          birth = DateTime.parse(birthdate);
        }
      } else {
        return 18;
      }
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) age--;
      return age < 0 ? 18 : age;
    } catch (_) {
      return 18;
    }
  }

  UserModel _rowToUser(Map<String, dynamic> row, double? distanceMeters) {
    return UserModel(
      id: row['id'] ?? '',
      name: row['name'] ?? 'Utilisateur',
      age: _calcAge(row['birthdate']),
      bio: row['bio'],
      photoUrl: row['photo_url'],
      photoUrls: List<String>.from(row['photo_urls'] ?? []),
      interests: List<String>.from(row['interests'] ?? []),
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
      gender: row['gender'],
      lookingFor: row['looking_for'],
      isOnline: row['is_online'] ?? false,
      distanceMeters: distanceMeters,
      followersCount: row['followers_count'] ?? 0,
      followingCount: row['following_count'] ?? 0,
      matchesCount: row['matches_count'] ?? 0,
      taille: row['taille'] as int?,
      poids: row['poids'] as int?,
      morphologie: row['morphologie'] as String?,
      lieuRencontre: row['lieu_rencontre'] as String?,
      showDistance: row['show_distance'] ?? true,
    );
  }

  void setFilterDistance(double km) => filterDistance.value = km;
  void setFilterStatus(String status) => filterStatus.value = status;

  String _formatDuree(Duration d) {
    if (d.inHours >= 24) return '${d.inDays} jour${d.inDays > 1 ? 's' : ''}';
    if (d.inMinutes >= 60) return '${d.inHours}h';
    return '${d.inMinutes} min';
  }

  void _snackSuccess(String msg) => Get.snackbar('✅ $msg', '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.online.withOpacity(0.15),
      colorText: Colors.white,
      duration: const Duration(seconds: 2));

  void _snackError(String msg) => Get.snackbar('Erreur', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white,
      duration: const Duration(seconds: 4));
}
