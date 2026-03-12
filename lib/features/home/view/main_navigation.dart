import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/view/home_screen.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/chat/view/chat_list_screen.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/profil/vue/ecran_profil.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/annonces/view/annonces_screen.dart';
import 'package:rencontre/features/annonces/controller/annonces_controller.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<ChatListController>()) Get.put(ChatListController(), permanent: true);
    if (!Get.isRegistered<AnnoncesController>()) Get.put(AnnoncesController(), permanent: true);
    Get.lazyPut<ControleurProfil>(() => ControleurProfil(), fenix: true);
  }

  final List<Widget> _screens = const [
    HomeScreen(),
    _EcranCarte(),
    AnnoncesScreen(),
    ChatListScreen(),
    EcranProfil(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _currentIndex, children: _screens),
      bottomNavigationBar: _BarreNavigation(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

// ─── CARTE AVEC VRAIE MAP ────────────────────────────────────────

class _EcranCarte extends StatefulWidget {
  const _EcranCarte();
  @override
  State<_EcranCarte> createState() => _EcranCarteState();
}

class _EcranCarteState extends State<_EcranCarte> {
  LatLng? _myPosition;
  List<Map<String, dynamic>> _profiles = [];
  bool _loading = true;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _getLocation();
    await _loadProfiles();
  }

  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium);
      setState(() => _myPosition = LatLng(pos.latitude, pos.longitude));
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await Supabase.instance.client.from('profiles').update({
          'latitude': pos.latitude,
          'longitude': pos.longitude,
        }).eq('id', uid);
      }
    } catch (e) {
      debugPrint('Location error: $e');
    }
  }

  Future<void> _loadProfiles() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final res = await Supabase.instance.client
        .from('profiles')
        .select('id, name, photo_url, latitude, longitude, is_online')
        .neq('id', uid ?? '')
        .not('latitude', 'is', null)
        .limit(50);
      setState(() {
        _profiles = List<Map<String, dynamic>>.from(res);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = _myPosition ?? const LatLng(5.3599517, -4.0082563);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.rencontre',
              ),
              MarkerLayer(
                markers: [
                  if (_myPosition != null)
                    Marker(
                      point: _myPosition!,
                      width: 50, height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [BoxShadow(
                            color: AppColors.accent.withOpacity(0.5),
                            blurRadius: 12, spreadRadius: 2)],
                        ),
                        child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 24),
                      ),
                    ),
                  ..._profiles.where((p) =>
                    p['latitude'] != null && p['longitude'] != null
                  ).map((p) => Marker(
                    point: LatLng(
                      (p['latitude'] as num).toDouble(),
                      (p['longitude'] as num).toDouble()),
                    width: 52, height: 62,
                    child: GestureDetector(
                      onTap: () => _showProfileCard(p),
                      child: Column(
                        children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: p['is_online'] == true
                                  ? AppColors.online : Colors.white,
                                width: 2.5),
                              boxShadow: [BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 8)],
                            ),
                            child: ClipOval(
                              child: p['photo_url'] != null && p['photo_url'] != ''
                                ? CachedNetworkImage(
                                    imageUrl: p['photo_url'],
                                    fit: BoxFit.cover)
                                : Container(
                                    color: AppColors.accent2,
                                    child: Center(
                                      child: Text(
                                        (p['name'] ?? '?')[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 18)))),
                            ),
                          ),
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: p['is_online'] == true
                                ? AppColors.online : Colors.white,
                              shape: BoxShape.circle),
                          ),
                        ],
                      ),
                    ),
                  )).toList(),
                ],
              ),
            ],
          ),

          // Header
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 12, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [AppColors.bg, AppColors.bg.withOpacity(0)]),
              ),
              child: Row(
                children: [
                  ShaderMask(
                    shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                    child: const Text('Carte', style: TextStyle(
                      fontFamily: 'Syne', fontSize: 24,
                      fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  const Spacer(),
                  if (_profiles.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border)),
                      child: Text('${_profiles.length} personnes',
                        style: const TextStyle(fontSize: 12,
                          color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      if (_myPosition != null) {
                        _mapController.move(_myPosition!, 14);
                      }
                    },
                    child: Container(
                      width: 38, height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border)),
                      child: const Icon(Icons.my_location_rounded,
                        size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_loading)
            Container(
              color: AppColors.bg,
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.accent)),
            ),
        ],
      ),
    );
  }

  void _showProfileCard(Map<String, dynamic> profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border)),
        child: Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent, width: 2)),
              child: ClipOval(
                child: profile['photo_url'] != null && profile['photo_url'] != ''
                  ? CachedNetworkImage(imageUrl: profile['photo_url'], fit: BoxFit.cover)
                  : Container(color: AppColors.accent2,
                      child: Center(child: Text(
                        (profile['name'] ?? '?')[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white,
                          fontSize: 24, fontWeight: FontWeight.w800)))),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(profile['name'] ?? 'Utilisateur',
                    style: const TextStyle(fontFamily: 'Syne',
                      fontSize: 18, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: profile['is_online'] == true
                            ? AppColors.online : AppColors.textMuted),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        profile['is_online'] == true ? 'En ligne' : 'Hors ligne',
                        style: TextStyle(fontSize: 13,
                          color: profile['is_online'] == true
                            ? AppColors.online : AppColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: AppColors.accent.withOpacity(0.4),
                    blurRadius: 12)]),
                child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── BARRE DE NAVIGATION ─────────────────────────────────────────

class _BarreNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BarreNavigation({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(icon: Icons.grid_view_rounded, label: 'Accueil',
                index: 0, currentIndex: currentIndex, onTap: onTap),
              _NavItem(icon: Icons.location_on_rounded, label: 'Carte',
                index: 1, currentIndex: currentIndex, onTap: onTap),

              // ── Annonces avec badge ──
              _NavItemAnnonces(index: 2, currentIndex: currentIndex, onTap: onTap),

              // ── Messages avec badge ──
              _NavItemMessages(index: 3, currentIndex: currentIndex, onTap: onTap),

              _NavItem(icon: Icons.person_rounded, label: 'Profil',
                index: 4, currentIndex: currentIndex, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── NAV ITEM ANNONCES (badge jaune annonces non vues) ───────────

class _NavItemAnnonces extends StatelessWidget {
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItemAnnonces({required this.index, required this.currentIndex,
    required this.onTap});

  bool get isActive => currentIndex == index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isActive
                      ? AppColors.accent.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.campaign_rounded, size: 22,
                    color: isActive ? AppColors.accent : AppColors.textMuted),
                ),
                // Badge annonces non vues (jaune)
                Obx(() {
                  if (!Get.isRegistered<AnnoncesController>()) {
                    return const SizedBox.shrink();
                  }
                  final unseen = Get.find<AnnoncesController>().unseenCount.value;
                  if (unseen == 0) return const SizedBox.shrink();
                  return Positioned(
                    top: -2, right: -6,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.black, width: 1),
                        boxShadow: [BoxShadow(
                          color: const Color(0xFFFFD700).withOpacity(0.6),
                          blurRadius: 4)],
                      ),
                      child: Center(child: Text(
                        unseen > 9 ? '9+' : '$unseen',
                        style: const TextStyle(fontSize: 8,
                          fontWeight: FontWeight.w900, color: Colors.black))),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 2),
            Text('ANNONCES',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isActive ? AppColors.accent : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── NAV ITEM MESSAGES (badge rose messages non lus) ─────────────

class _NavItemMessages extends StatelessWidget {
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItemMessages({required this.index, required this.currentIndex,
    required this.onTap});

  bool get isActive => currentIndex == index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isActive
                      ? AppColors.accent.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.chat_bubble_rounded, size: 22,
                    color: isActive ? AppColors.accent : AppColors.textMuted),
                ),
                // Badge messages non lus (rose)
                GetBuilder<ChatListController>(
                  builder: (ctrl) {
                    final total = ctrl.conversations
                      .fold<int>(0, (sum, c) => sum + c.unreadCount);
                    if (total == 0) return const SizedBox.shrink();
                    return Positioned(
                      top: -2, right: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientPink,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: Center(child: Text(
                          total > 99 ? '99+' : '$total',
                          style: const TextStyle(fontSize: 8,
                            fontWeight: FontWeight.w900, color: Colors.white))),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text('MESSAGES',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isActive ? AppColors.accent : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── NAV ITEM STANDARD ───────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index, currentIndex;
  final ValueChanged<int> onTap;
  const _NavItem({required this.icon, required this.label, required this.index,
    required this.currentIndex, required this.onTap});

  bool get isActive => currentIndex == index;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isActive
                  ? AppColors.accent.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22,
                color: isActive ? AppColors.accent : AppColors.textMuted),
            ),
            const SizedBox(height: 2),
            Text(label.toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isActive ? AppColors.accent : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}