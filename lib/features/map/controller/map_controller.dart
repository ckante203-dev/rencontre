import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/utils/app_routes.dart';
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
    if (diff.inMinutes < 60) return '@inMinutes min'.trParams({'inMinutes': diff.inMinutes.toString()});
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
          headers: {'User-Agent': 'Zamu/1.0 (support.zamuapp@gmail.com)'});
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
          ? 'Tu es invisible sur la carte'.tr
          : 'Invisible pendant @p'.trParams({'p': (_formatDuree(duree)).toString()}));
    } catch (e) {
      debugPrint('setInvisible error: $e');
      _snackError('Impossible de modifier la visibilité'.tr);
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
      _snackSuccess('Tu es visible sur la carte'.tr);
    } catch (e) {
      debugPrint('setVisible error: $e');
      _snackError('Impossible de modifier la visibilité'.tr);
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
          newGhost ? '👻 Mode fantôme activé'.tr : '👻 Mode fantôme désactivé'.tr);
    } catch (e) {
      debugPrint('toggleGhost error: $e');
      _snackError('Impossible de modifier le mode fantôme'.tr);
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
      _snackSuccess('Précision mise à jour'.tr);
    } catch (e) {
      debugPrint('setPrecision error: $e');
      _snackError('Impossible de modifier la précision'.tr);
    } finally {
      isSavingPrefs.value = false;
    }
  }

  void _showPremiumDialog() {
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Mode Fantôme 👻'.tr,
          style: TextStyle(
              fontFamily: 'Syne',
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              fontSize: 18)),
      content: Text(
          'Le mode fantôme est une fonctionnalité Premium.\n\nTu peux voir tous les profils sur la carte sans que personne ne te voit.'.tr,
          style:
              TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Fermer'.tr,
                style: TextStyle(color: AppColors.textMuted))),
        GestureDetector(
          onTap: () {
            Get.back();
            Get.toNamed(AppRoutes.paywall);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
              borderRadius: BorderRadius.circular(12),
            ),
            child:  Text('Passer Premium 👑'.tr,
                style: TextStyle(
                    color: AppColors.surAccent, fontWeight: FontWeight.w700)),
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

      final myLat = myPosition.value?.latitude;
      final myLng = myPosition.value?.longitude;

      // 🔒 Le serveur exclut bloqués, masqués et fantômes, et renvoie des
      // positions ARRONDIES sur une grille fixe (SQL 098). Avant, la
      // position exacte arrivait sur le téléphone et était floutée au
      // hasard à chaque chargement (moyenne = position exacte).
      List<Map<String, dynamic>> rows = [];
      if (myLat != null && myLng != null) {
        try {
          final r = await Supabase.instance.client.rpc('profils_carte',
              params: {
                'p_lat': myLat,
                'p_lng': myLng,
                'p_rayon_km': _rayonRechercheMaxKm,
              });
          if (r is List) {
            rows = r.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
        } catch (e) {
          debugPrint('profils_carte indisponible : $e');
        }
      }

      final list = rows.map((row) {
        double? distanceMeters;
        final lat = (row['latitude'] as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();
        if (myLat != null && myLng != null && lat != null && lng != null) {
          distanceMeters = _distanceMeters(myLat, myLng, lat, lng);
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
    if (birthdate == null) return 0; // âge inconnu
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
        return 0; // âge inconnu
      }
      final now = DateTime.now();
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) age--;
      return age < 0 ? 18 : age;
    } catch (_) {
      return 0; // âge inconnu
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
      showBirthdate: row['show_birthdate'] ?? true,
    );
  }

  void setFilterDistance(double km) => filterDistance.value = km;
  void setFilterStatus(String status) => filterStatus.value = status;

  String _formatDuree(Duration d) {
    if (d.inHours >= 24) return '@inDays jour@p'.trParams({'inDays': d.inDays.toString(), 'p': (d.inDays > 1 ? 's' : '').toString()});
    if (d.inMinutes >= 60) return '${d.inHours}h';
    return '@inMinutes min'.trParams({'inMinutes': d.inMinutes.toString()});
  }

  void _snackSuccess(String msg) => Get.snackbar('✅ $msg', '',
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.online.withOpacity(0.15),
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 2));

  void _snackError(String msg) => Get.snackbar('Erreur'.tr, msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary,
      duration: const Duration(seconds: 4));
}
