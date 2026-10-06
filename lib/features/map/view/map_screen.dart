import 'dart:ui' as ui;
import 'package:flutter/material.dart' hide Path;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/theme/app_palette.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/map/controller/map_controller.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with AutomaticKeepAliveClientMixin {
  late MapController _ctrl;
  final fm.MapController _mapController = fm.MapController();
  final _searchFocus = FocusNode();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (Get.isRegistered<MapController>()) {
      _ctrl = Get.find<MapController>();
    } else {
      _ctrl = Get.put(MapController());
    }
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Obx(() {
        final myPos = _ctrl.myPosition.value;
        final center = myPos ?? const LatLng(5.3599517, -4.0082563);
        final invisible = _ctrl.estInvisible;
        final fantome = _ctrl.estFantome;
        final showList = _ctrl.showList.value;

        return Stack(
          children: [
            // ── Fond sombre permanent ──────────────────────
            // ✅ Fix vue liste noire — fond toujours présent
            Container(color: AppColors.bg),

            // ── Carte ──────────────────────────────────────
            AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: showList ? 0.0 : 1.0,
              child: IgnorePointer(
                ignoring: showList,
                child: fm.FlutterMap(
                  mapController: _mapController,
                  options: fm.MapOptions(
                    initialCenter: center,
                    initialZoom: 13,
                    maxZoom: 18,
                    minZoom: 3,
                  ),
                  children: [
                    // ✅ Tuiles sombres CartoDB Dark Matter
                    fm.TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.snapmeet.app',
                      retinaMode: true,
                    ),

                    // ✅ Cercle de rayon
                    if (myPos != null && _ctrl.peutVoirLaCarte)
                      fm.CircleLayer(
                        circles: [
                          fm.CircleMarker(
                            point: myPos,
                            radius: _ctrl.filterDistance.value * 1000,
                            useRadiusInMeter: true,
                            color: AppColors.accent.withOpacity(0.06),
                            borderColor: AppColors.accent.withOpacity(0.3),
                            borderStrokeWidth: 1.5,
                          ),
                        ],
                      ),

                    // ✅ Marqueurs avec clustering
                    if (_ctrl.peutVoirLaCarte)
                      Obx(() => MarkerClusterLayerWidget(
                            options: MarkerClusterLayerOptions(
                              maxClusterRadius: 60,
                              size: const Size(48, 48),
                              alignment: Alignment.center,
                              padding: const EdgeInsets.all(50),
                              markers: [
                                if (myPos != null)
                                  fm.Marker(
                                    point: myPos,
                                    width: 56,
                                    height: 56,
                                    child: _MonMarqueur(
                                        isGhost: fantome,
                                        isInvisible: invisible),
                                  ),
                                ..._ctrl.filteredProfiles
                                    .where((u) =>
                                        u.latitude != null &&
                                        u.longitude != null)
                                    .map((u) => fm.Marker(
                                          point:
                                              LatLng(u.latitude!, u.longitude!),
                                          width: 56,
                                          height: 68,
                                          child: GestureDetector(
                                            onTap: () => _showProfilCard(u),
                                            child: _MarqueurProfil(user: u),
                                          ),
                                        )),
                              ],
                              // ✅ Cluster personnalisé
                              builder: (context, markers) {
                                return Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.gradientPink,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                          color:
                                              AppColors.accent.withOpacity(0.5),
                                          blurRadius: 12,
                                          spreadRadius: 1)
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${markers.length}',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )),
                  ],
                ),
              ),
            ),

            // ── Overlay flou si invisible ──────────────────
            if (invisible && !fantome && !showList)
              Positioned.fill(
                child: Container(
                  color: AppColors.bg.withOpacity(0.7),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),

            // ✅ Vue Liste — correctement positionnée
            if (showList)
              Positioned.fill(
                child: _VueListe(ctrl: _ctrl),
              ),

            // ── Header ─────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _Header(
                  ctrl: _ctrl,
                  mapCtrl: _mapController,
                  onSearch: _rechercherVille),
            ),

            // ── Barre de recherche ─────────────────────────
            Obx(() => _ctrl.showSearch.value
                ? Positioned(
                    top: MediaQuery.of(context).padding.top + 66,
                    left: 16,
                    right: 16,
                    child: _BarreRecherche(
                        ctrl: _ctrl,
                        mapCtrl: _mapController,
                        focusNode: _searchFocus),
                  )
                : const SizedBox.shrink()),

            // ── Filtres ────────────────────────────────────
            if (_ctrl.peutVoirLaCarte && !showList)
              Obx(() => _ctrl.showSearch.value
                  ? const SizedBox.shrink()
                  : Positioned(
                      top: MediaQuery.of(context).padding.top + 70,
                      left: 16,
                      right: 16,
                      child: _FiltresBar(ctrl: _ctrl),
                    )),

            // ── Bannière invisible ─────────────────────────
            if (invisible && !fantome)
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                left: 16,
                right: 16,
                child: _BanniereInvisible(ctrl: _ctrl),
              ),

            // ── Bannière fantôme ───────────────────────────
            if (fantome)
              Positioned(
                top: MediaQuery.of(context).padding.top + 70,
                left: 16,
                right: 16,
                child: _BanniereFantome(ctrl: _ctrl),
              ),

            // ── Compteur profils ───────────────────────────
            if (_ctrl.peutVoirLaCarte && !showList)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Obx(() => Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface.withOpacity(0.95),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 12)
                          ],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration:  BoxDecoration(
                                color: AppColors.online,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${_ctrl.filteredProfiles.length} personne${_ctrl.filteredProfiles.length > 1 ? 's' : ''} à proximité',
                            style:  TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary),
                          ),
                        ]),
                      ),
                    )),
              ),

            // ── Loading ────────────────────────────────────
            Obx(() => _ctrl.isLoading.value
                ? Container(
                    color: AppColors.bg.withOpacity(0.85),
                    child:  Center(
                        child:
                            CircularProgressIndicator(color: AppColors.accent)),
                  )
                : const SizedBox.shrink()),

            // ── Erreur localisation ────────────────────────
            Obx(() => _ctrl.locationError.value
                ? Positioned(
                    bottom: 80,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: AppColors.error.withOpacity(0.4)),
                      ),
                      child: Row(children: [
                         Icon(Icons.location_off_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                         Expanded(
                          child: Text('Localisation non disponible',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.error)),
                        ),
                        GestureDetector(
                          onTap: () => Geolocator.openLocationSettings(),
                          child:  Text('Activer',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                        ),
                      ]),
                    ),
                  )
                : const SizedBox.shrink()),
          ],
        );
      }),
    );
  }

  Future<void> _rechercherVille(String query) async {
    if (query.trim().isEmpty) return;
    _ctrl.isSearching.value = true;
    try {
      final response = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=5&accept-language=fr'),
        headers: {'User-Agent': 'SnapMeet/1.0'},
      );
      if (response.statusCode == 200) {
        final results = json.decode(response.body) as List;
        _ctrl.searchResults.value = results
            .map((r) => {
                  'name': r['display_name'] as String,
                  'lat': double.parse(r['lat'] as String),
                  'lon': double.parse(r['lon'] as String),
                })
            .toList();
      }
    } catch (e) {
      debugPrint('_rechercherVille error: $e');
    } finally {
      _ctrl.isSearching.value = false;
    }
  }

  void _showProfilCard(UserModel user) {
    Get.bottomSheet(
      _ProfilCard(user: user),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}

// ─── HEADER ──────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final MapController ctrl;
  final fm.MapController mapCtrl;
  final Future<void> Function(String) onSearch;
  const _Header(
      {required this.ctrl, required this.mapCtrl, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.bg,
            AppColors.bg.withOpacity(0.95),
            AppColors.bg.withOpacity(0),
          ],
        ),
      ),
      child: Row(children: [
        const Text('Carte',
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        const Spacer(),

        // ✅ Bouton Vue liste/carte avec tooltip
        Obx(() => Tooltip(
              message: ctrl.showList.value ? 'Voir la carte' : 'Voir la liste',
              child: GestureDetector(
                onTap: ctrl.toggleView,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: ctrl.showList.value
                          ? AppColors.accent.withOpacity(0.15)
                          : AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ctrl.showList.value
                              ? AppColors.accent
                              : AppColors.border)),
                  child: Icon(
                    ctrl.showList.value
                        ? Icons.map_rounded
                        : Icons.view_list_rounded,
                    size: 18,
                    color: ctrl.showList.value
                        ? AppColors.accent
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            )),
        const SizedBox(width: 8),

        // Bouton recherche
        Obx(() => Tooltip(
              message: 'Rechercher une ville',
              child: GestureDetector(
                onTap: ctrl.toggleSearch,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: ctrl.showSearch.value
                          ? AppColors.accent.withOpacity(0.15)
                          : AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ctrl.showSearch.value
                              ? AppColors.accent
                              : AppColors.border)),
                  child: Icon(Icons.search_rounded,
                      size: 18,
                      color: ctrl.showSearch.value
                          ? AppColors.accent
                          : AppColors.textPrimary),
                ),
              ),
            )),
        const SizedBox(width: 8),

        // Paramètres
        GestureDetector(
          onTap: () => _showParametresCarte(context),
          child: Obx(() => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: ctrl.estInvisible
                        ? Colors.orange.withOpacity(0.2)
                        : ctrl.estFantome
                            ? Colors.purple.withOpacity(0.2)
                            : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: ctrl.estInvisible
                            ? Colors.orange.withOpacity(0.6)
                            : ctrl.estFantome
                                ? Colors.purple.withOpacity(0.6)
                                : AppColors.border)),
                child: Icon(
                  ctrl.estInvisible
                      ? Icons.visibility_off_rounded
                      : ctrl.estFantome
                          ? Icons.auto_awesome_rounded
                          : Icons.tune_rounded,
                  size: 18,
                  color: ctrl.estInvisible
                      ? Colors.orange
                      : ctrl.estFantome
                          ? Colors.purple
                          : AppColors.textPrimary,
                ),
              )),
        ),
        const SizedBox(width: 8),

        // Refresh
        GestureDetector(
          onTap: ctrl.refresh,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border)),
            child:  Icon(Icons.refresh_rounded,
                size: 18, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(width: 8),

        // Centrer
        Obx(() => GestureDetector(
              onTap: () {
                final pos = ctrl.myPosition.value;
                if (pos != null) mapCtrl.move(pos, 14);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: ctrl.myPosition.value != null
                        ? AppColors.accent.withOpacity(0.15)
                        : AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: ctrl.myPosition.value != null
                            ? AppColors.accent
                            : AppColors.border)),
                child: Icon(Icons.my_location_rounded,
                    size: 18,
                    color: ctrl.myPosition.value != null
                        ? AppColors.accent
                        : AppColors.textMuted),
              ),
            )),
      ]),
    );
  }

  void _showParametresCarte(BuildContext context) {
    Get.bottomSheet(
      _PanelParametresCarte(ctrl: ctrl),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }
}

// ─── BARRE RECHERCHE ─────────────────────────────────────────────

class _BarreRecherche extends StatelessWidget {
  final MapController ctrl;
  final fm.MapController mapCtrl;
  final FocusNode focusNode;
  const _BarreRecherche(
      {required this.ctrl, required this.mapCtrl, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withOpacity(0.97),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.accent.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 16)
          ],
        ),
        child: Row(children: [
          const SizedBox(width: 14),
           Icon(Icons.search_rounded, color: AppColors.accent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: ctrl.searchController,
              focusNode: focusNode,
              autofocus: true,
              style:
                   TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration:  InputDecoration(
                hintText: 'Rechercher une ville...',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (v) {
                if (v.length >= 3) _rechercher(v, ctrl, mapCtrl);
              },
            ),
          ),
          Obx(() => ctrl.isSearching.value
              ?  Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.accent)),
                )
              : GestureDetector(
                  onTap: () {
                    ctrl.searchController.clear();
                    ctrl.searchResults.clear();
                  },
                  child:  Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.close_rounded,
                        color: AppColors.textMuted, size: 18),
                  ),
                )),
        ]),
      ),
      Obx(() => ctrl.searchResults.isNotEmpty
          ? Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.97),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.2), blurRadius: 12)
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: ctrl.searchResults
                    .take(4)
                    .map((r) => GestureDetector(
                          onTap: () {
                            final lat = r['lat'] as double;
                            final lon = r['lon'] as double;
                            mapCtrl.move(LatLng(lat, lon), 13);
                            ctrl.toggleSearch();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color:
                                          AppColors.border.withOpacity(0.5))),
                            ),
                            child: Row(children: [
                               Icon(Icons.location_on_rounded,
                                  color: AppColors.accent, size: 16),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  r['name'] as String,
                                  style:  TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textPrimary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            )
          : const SizedBox.shrink()),
    ]);
  }

  Future<void> _rechercher(
      String query, MapController ctrl, fm.MapController mapCtrl) async {
    if (query.trim().length < 3) return;
    ctrl.isSearching.value = true;
    try {
      final response = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&limit=4&accept-language=fr'),
        headers: {'User-Agent': 'SnapMeet/1.0'},
      );
      if (response.statusCode == 200) {
        final results = json.decode(response.body) as List;
        ctrl.searchResults.value = results
            .map((r) => {
                  'name': r['display_name'] as String,
                  'lat': double.parse(r['lat'] as String),
                  'lon': double.parse(r['lon'] as String),
                })
            .toList();
      }
    } catch (e) {
      debugPrint('_rechercher error: $e');
    } finally {
      ctrl.isSearching.value = false;
    }
  }
}

// ─── VUE LISTE ───────────────────────────────────────────────────

class _VueListe extends StatelessWidget {
  final MapController ctrl;
  const _VueListe({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top + 80;

    return Container(
      // ✅ Fix fond noir — couleur de fond explicite
      color: AppColors.bg,
      child: Obx(() {
        final profiles = ctrl.filteredProfiles;

        if (ctrl.isLoading.value) {
          return Padding(
            padding: EdgeInsets.only(top: topPad),
            child:  Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }

        if (profiles.isEmpty) {
          return Padding(
            padding: EdgeInsets.only(top: topPad),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(Icons.person_search_rounded,
                        size: 36, color: AppColors.textMuted.withOpacity(0.5)),
                  ),
                  const SizedBox(height: 16),
                   Text('Personne à proximité',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                   Text('Augmente la distance\npour voir plus de profils',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          height: 1.5)),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, topPad, 16, 24),
          itemCount: profiles.length,
          itemBuilder: (_, i) {
            final user = profiles[i];
            return _CarteProfilListe(
              user: user,
              onTap: () => Get.bottomSheet(
                _ProfilCard(user: user),
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
              ),
            );
          },
        );
      }),
    );
  }
}

// ✅ Carte profil dans la liste — améliorée
class _CarteProfilListe extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  const _CarteProfilListe({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: user.isOnline
                  ? AppColors.online.withOpacity(0.3)
                  : AppColors.border),
          boxShadow: [
            BoxShadow(
                color: user.isOnline
                    ? AppColors.online.withOpacity(0.08)
                    : Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          // ✅ Avatar amélioré
          _AvatarProfil(user: user, size: 58),
          const SizedBox(width: 14),

          // Infos
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(user.showBirthdate ? '${user.name}, ${user.age}' : user.name,
                      style:  TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                if (user.isOnline)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.online.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.online.withOpacity(0.3)),
                    ),
                    child:  Text('En ligne',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.online)),
                  ),
              ]),
              const SizedBox(height: 4),
              // Distance + genre
              Row(children: [
                 Icon(Icons.location_on_rounded,
                    size: 12, color: AppColors.textMuted),
                const SizedBox(width: 3),
                Text(
                  user.distanceMeters != null && user.showDistance
                      ? user.distanceLabel
                      : 'Distance inconnue',
                  style:
                       TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                if (user.gender != null) ...[
                   Text(' · ',
                      style: TextStyle(color: AppColors.textMuted)),
                  Text(user.gender!.capitalize!,
                      style:  TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                ],
              ]),
              // Bio courte
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(user.bio!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontStyle: FontStyle.italic)),
              ],
              // Intérêts
              if (user.interests.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: user.interests
                      .take(3)
                      .map((interest) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.accent.withOpacity(0.2)),
                            ),
                            child: Text(interest,
                                style:  TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                ),
              ],
            ]),
          ),

          // Bouton message rapide
          GestureDetector(
            onTap: () async {
              try {
                final service = SupabaseService();
                final convId = await service.getOrCreateConversation(user.id);
                Get.toNamed('/chat/conversation',
                    arguments: ConversationModel(
                      id: convId,
                      userId: user.id,
                      userName: user.name,
                      userPhotoUrl: user.photoUrl,
                      isOnline: user.isOnline,
                      unreadCount: 0,
                    ));
              } catch (_) {}
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: AppColors.accent.withOpacity(0.3), blurRadius: 8)
                ],
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── AVATAR AMÉLIORÉ ─────────────────────────────────────────────

// ✅ Avatar avec dégradé coloré selon le nom — plus beau que les initiales plates
class _AvatarProfil extends StatelessWidget {
  final UserModel user;
  final double size;
  const _AvatarProfil({required this.user, this.size = 50});

  // ✅ Palettes de dégradés — chaque lettre a son dégradé unique
  static const _gradients = degradesAvatar;

  @override
  Widget build(BuildContext context) {
    final idx =
        user.name.isNotEmpty ? user.name.codeUnitAt(0) % _gradients.length : 0;
    final colors = _gradients[idx];
    final letter = user.name.isNotEmpty ? user.name[0].toUpperCase() : '?';

    return Stack(
      children: [
        // ✅ Anneau en ligne
        Container(
          width: size + 4,
          height: size + 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: user.isOnline
                ? LinearGradient(colors: [
                    AppColors.online,
                    AppColors.online.withOpacity(0.5)
                  ])
                : null,
            color: user.isOnline ? null : AppColors.border,
          ),
        ),
        // Photo ou avatar
        Positioned(
          top: 2,
          left: 2,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: ClipOval(
              child: user.photoUrl != null && user.photoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: user.photoUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Center(
                            child: Text(letter,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: size * 0.38)),
                          ))
                  : Center(
                      child: Text(letter,
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: size * 0.38)),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── PANEL PARAMÈTRES CARTE ───────────────────────────────────────

class _PanelParametresCarte extends StatelessWidget {
  final MapController ctrl;
  const _PanelParametresCarte({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(2))),
          ),
          const SizedBox(height: 16),
          const Text('Paramètres de la carte',
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          const SizedBox(height: 20),
          _SectionTitre('👁️ Visibilité sur la carte'),
          const SizedBox(height: 10),
          Obx(() => ctrl.estInvisible
              ? Column(children: [
                  _BoutonAction(
                    label: 'Redevenir visible',
                    icon: Icons.visibility_rounded,
                    color: AppColors.online,
                    onTap: () {
                      Get.back();
                      ctrl.setVisible();
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded,
                          color: Colors.orange, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          ctrl.mapInvisibleUntil.value != null
                              ? 'Invisible encore ${ctrl.invisibleDepuis}'
                              : 'Tu es invisible indéfiniment',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.orange),
                        ),
                      ),
                    ]),
                  ),
                ])
              : Column(children: [
                   Text('Se cacher pendant :',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: _BoutonDuree(
                            label: '1 heure',
                            onTap: () {
                              Get.back();
                              ctrl.setInvisible(const Duration(hours: 1));
                            })),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _BoutonDuree(
                            label: '24 heures',
                            onTap: () {
                              Get.back();
                              ctrl.setInvisible(const Duration(hours: 24));
                            })),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _BoutonDuree(
                            label: 'Toujours',
                            onTap: () {
                              Get.back();
                              ctrl.setInvisible(null);
                            })),
                  ]),
                ])),
          const SizedBox(height: 20),
          _SectionTitre('👻 Mode Fantôme'),
          const SizedBox(height: 10),
          Obx(() => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ctrl.estFantome
                      ? Colors.purple.withOpacity(0.1)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: ctrl.estFantome
                          ? Colors.purple.withOpacity(0.4)
                          : AppColors.border),
                ),
                child: Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ctrl.estFantome
                          ? Colors.purple.withOpacity(0.2)
                          : AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                        child: Text('👻', style: TextStyle(fontSize: 20))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                             Text('Mode Fantôme',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFFFFD700),
                                  Color(0xFFFFA500)
                                ]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('👑 Premium',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                            ),
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            ctrl.estFantome
                                ? 'Actif — tu vois sans apparaître'
                                : 'Vois les autres sans apparaître',
                            style:  TextStyle(
                                fontSize: 11, color: AppColors.textMuted),
                          ),
                        ]),
                  ),
                  Switch(
                    value: ctrl.estFantome,
                    onChanged: (_) {
                      Get.back();
                      ctrl.toggleGhost();
                    },
                    activeColor: Colors.purple,
                    activeTrackColor: Colors.purple.withOpacity(0.3),
                    inactiveThumbColor: AppColors.textMuted,
                    inactiveTrackColor: AppColors.surface2,
                  ),
                ]),
              )),
          const SizedBox(height: 20),
          _SectionTitre('📍 Précision de ma position'),
          const SizedBox(height: 10),
          Obx(() => Column(children: [
                _OptionPrecision(
                    label: 'Position exacte',
                    sublabel: 'Ta position réelle est affichée',
                    icon: '🎯',
                    value: 'exact',
                    selected: ctrl.positionPrecision.value,
                    onTap: () => ctrl.setPrecision('exact')),
                const SizedBox(height: 6),
                _OptionPrecision(
                    label: 'Floutée (±300m)',
                    sublabel: 'Recommandé — position approximative',
                    icon: '🔵',
                    value: 'flouted',
                    selected: ctrl.positionPrecision.value,
                    onTap: () => ctrl.setPrecision('flouted')),
                const SizedBox(height: 6),
                _OptionPrecision(
                    label: 'Très floutée (±1km)',
                    sublabel: 'Maximum de confidentialité',
                    icon: '🌫️',
                    value: 'very_flouted',
                    selected: ctrl.positionPrecision.value,
                    onTap: () => ctrl.setPrecision('very_flouted')),
              ])),
          SizedBox(height: MediaQuery.of(Get.context!).padding.bottom + 20),
        ]),
      ),
    );
  }
}

// ─── BANNIÈRES ───────────────────────────────────────────────────

class _BanniereInvisible extends StatelessWidget {
  final MapController ctrl;
  const _BanniereInvisible({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12)
        ],
      ),
      child: Row(children: [
        const Text('🙈', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Tu es invisible sur la carte',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange)),
            const SizedBox(height: 2),
            Text(
              ctrl.mapInvisibleUntil.value != null
                  ? 'Encore ${ctrl.invisibleDepuis} — tu ne vois pas les autres'
                  : 'Tu ne vois pas les autres profils',
              style: const TextStyle(fontSize: 11, color: Colors.orange),
            ),
          ]),
        ),
        GestureDetector(
          onTap: ctrl.setVisible,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withOpacity(0.5)),
            ),
            child: const Text('Visible',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange)),
          ),
        ),
      ]),
    );
  }
}

class _BanniereFantome extends StatelessWidget {
  final MapController ctrl;
  const _BanniereFantome({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 12)
        ],
      ),
      child: const Row(children: [
        Text('👻', style: TextStyle(fontSize: 22)),
        SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mode Fantôme actif',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.purple)),
            SizedBox(height: 2),
            Text('Tu vois les autres — personne ne te voit 👑',
                style: TextStyle(fontSize: 11, color: Colors.purple)),
          ]),
        ),
      ]),
    );
  }
}

// ─── FILTRES ─────────────────────────────────────────────────────

class _FiltresBar extends StatelessWidget {
  final MapController ctrl;
  const _FiltresBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Row(children: [
          GestureDetector(
            onTap: () => ctrl.setFilterStatus(
                ctrl.filterStatus.value == 'tous' ? 'online' : 'tous'),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: ctrl.filterStatus.value == 'online'
                    ? AppColors.gradientPink
                    : null,
                color: ctrl.filterStatus.value != 'online'
                    ? AppColors.surface.withOpacity(0.95)
                    : null,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: ctrl.filterStatus.value == 'online'
                        ? Colors.transparent
                        : AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.15), blurRadius: 8)
                ],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: ctrl.filterStatus.value == 'online'
                        ? Colors.white
                        : AppColors.online,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('En ligne',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: ctrl.filterStatus.value == 'online'
                            ? Colors.white
                            : AppColors.textPrimary)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.15), blurRadius: 8)
                ],
              ),
              child: Row(children: [
                 Icon(Icons.social_distance_rounded,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text('${ctrl.filterDistance.value.toInt()} km',
                    style:  TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.border,
                      thumbColor: AppColors.accent,
                      overlayColor: AppColors.accent.withOpacity(0.2),
                    ),
                    child: Slider(
                      value: ctrl.filterDistance.value,
                      min: 1,
                      max: 50,
                      divisions: 49,
                      onChanged: ctrl.setFilterDistance,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]));
  }
}

// ─── MON MARQUEUR ────────────────────────────────────────────────

class _MonMarqueur extends StatefulWidget {
  final bool isGhost;
  final bool isInvisible;
  const _MonMarqueur({this.isGhost = false, this.isInvisible = false});

  @override
  State<_MonMarqueur> createState() => _MonMarqueurState();
}

class _MonMarqueurState extends State<_MonMarqueur> {
  // ✅ Future créée une seule fois (et non à chaque build) : évite
  // une requête Supabase à chaque reconstruction de la carte.
  late final Future<Map<String, dynamic>?> _photoFuture;

  bool get isGhost => widget.isGhost;
  bool get isInvisible => widget.isInvisible;

  @override
  void initState() {
    super.initState();
    final uid = SupabaseService().currentUserId;
    _photoFuture = uid != null
        ? Supabase.instance.client
            .from('profiles')
            .select('photo_url')
            .eq('id', uid)
            .maybeSingle()
        : Future.value(null);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _photoFuture,
      builder: (_, snap) {
        final photo = snap.data?['photo_url'] as String?;
        return Stack(children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isGhost
                  ? const LinearGradient(
                      colors: [Colors.purple, Color(0xFF9C27B0)])
                  : AppColors.gradientPink,
              border: Border.all(
                  color: isGhost ? Colors.purple : Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                    color: (isGhost ? Colors.purple : AppColors.accent)
                        .withOpacity(0.6),
                    blurRadius: 14,
                    spreadRadius: 2)
              ],
            ),
            child: ClipOval(
              child: photo != null && photo.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photo,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 26))
                  : const Icon(Icons.person_rounded,
                      color: Colors.white, size: 26),
            ),
          ),
          if (isGhost)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                    color: Colors.purple, shape: BoxShape.circle),
                child: const Center(
                    child: Text('👻', style: TextStyle(fontSize: 10))),
              ),
            ),
        ]);
      },
    );
  }
}

// ─── MARQUEUR PROFIL ─────────────────────────────────────────────

class _MarqueurProfil extends StatelessWidget {
  final UserModel user;
  const _MarqueurProfil({required this.user});

  // ✅ Dégradés pour les avatars initiales sur la carte
  static const _gradients = degradesAvatar;

  @override
  Widget build(BuildContext context) {
    final idx =
        user.name.isNotEmpty ? user.name.codeUnitAt(0) % _gradients.length : 0;
    final colors = _gradients[idx];

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // ✅ Bordure verte si en ligne, blanche sinon
          border: Border.all(
            color: user.isOnline ? AppColors.online : Colors.white,
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
                color: user.isOnline
                    ? AppColors.online.withOpacity(0.5)
                    : Colors.black.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 1)
          ],
        ),
        child: ClipOval(
          child: user.photoUrl != null && user.photoUrl!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: user.photoUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      // ✅ Avatar initiale avec dégradé
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: colors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            user.name.isNotEmpty
                                ? user.name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 20),
                          ),
                        ),
                      ))
              // ✅ Pas de photo → avatar dégradé
              : Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: colors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20),
                    ),
                  ),
                ),
        ),
      ),
      // ✅ Triangle pointeur coloré selon statut
      CustomPaint(
        size: const Size(12, 8),
        painter: _TrianglePainter(
            color: user.isOnline ? AppColors.online : Colors.white),
      ),
    ]);
  }
}

// ─── WIDGETS COMMUNS ─────────────────────────────────────────────

class _TrianglePainter extends CustomPainter {
  final Color color;
  const _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── FICHE PROFIL ─────────────────────────────────────────────────

class _ProfilCard extends StatelessWidget {
  final UserModel user;
  const _ProfilCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, -4))
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            // ✅ Avatar amélioré dans la fiche profil
            _AvatarProfil(user: user, size: 72),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(user.showBirthdate ? '${user.name}, ${user.age}' : user.name,
                            style:  TextStyle(
                                fontFamily: 'Syne',
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      if (user.isOnline)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.online.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.online.withOpacity(0.4)),
                          ),
                          child:  Text('En ligne',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.online)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    if (user.distanceMeters != null && user.showDistance)
                      Row(children: [
                         Icon(Icons.location_on_rounded,
                            size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(user.distanceLabel,
                            style:  TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                      ]),
                    const SizedBox(height: 4),
                    if (user.gender != null)
                      Text(
                        '${user.gender!.capitalize}${user.lookingFor != null ? ' · cherche ${user.lookingFor}' : ''}',
                        style:  TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ]),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (user.bio != null && user.bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(user.bio!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                      fontSize: 13, color: AppColors.textMuted, height: 1.5)),
            ),
          ),
        if (user.interests.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: user.interests.take(3).length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(user.interests[i],
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  Get.back();
                  ouvrirProfilParId(user.id); // fiche complète
                },
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.accent.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: const Center(
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_rounded,
                              color: Colors.white, size: 17),
                          SizedBox(width: 8),
                          Text('Voir le profil',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () async {
                Get.back();
                await _ouvrirChat(user);
              },
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child:  Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.accent, size: 20),
              ),
            ),
          ]),
        ),
        SizedBox(height: MediaQuery.of(Get.context!).padding.bottom + 12),
      ]),
    );
  }

  Future<void> _ouvrirChat(UserModel user) async {
    try {
      final service = SupabaseService();
      final convId = await service.getOrCreateConversation(user.id);
      Get.toNamed('/chat/conversation',
          arguments: ConversationModel(
            id: convId,
            userId: user.id,
            userName: user.name,
            userPhotoUrl: user.photoUrl,
            isOnline: user.isOnline,
            unreadCount: 0,
          ));
    } catch (e) {
      Get.snackbar('Erreur', "Impossible d'ouvrir la conversation",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }
}

// ─── WIDGETS UTILITAIRES ─────────────────────────────────────────

class _SectionTitre extends StatelessWidget {
  final String text;
  const _SectionTitre(this.text);
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style:  TextStyle(
                fontFamily: 'Syne',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                letterSpacing: 0.3)),
      );
}

class _BoutonAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _BoutonAction(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      );
}

class _BoutonDuree extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _BoutonDuree({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.orange)),
          ),
        ),
      );
}

class _OptionPrecision extends StatelessWidget {
  final String label, sublabel, icon, value, selected;
  final VoidCallback onTap;
  const _OptionPrecision(
      {required this.label,
      required this.sublabel,
      required this.icon,
      required this.value,
      required this.selected,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accent.withOpacity(0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border),
        ),
        child: Row(children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textPrimary)),
              Text(sublabel,
                  style:  TextStyle(
                      fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
          if (isSelected)
             Icon(Icons.check_circle_rounded,
                color: AppColors.accent, size: 20),
        ]),
      ),
    );
  }
}
