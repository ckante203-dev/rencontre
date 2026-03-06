import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/annonces/view/annonces_screen.dart';
import 'package:rencontre/features/annonces/view/annonces_screen.dart';
import 'package:rencontre/features/annonces/view/annonces_screen.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/widget/stories_row.dart';
import 'package:rencontre/shared/models/user_model.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      statusBarColor: Colors.transparent,
    ));
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            const _TopBar(),
            const StoriesRow(),
            const _FilterChips(),
            const SizedBox(height: 4),
            const Expanded(child: _UsersGrid()),
          ],
        ),
      ),
    );
  }
}

// ─── TOP BAR ───────────────────────────────────────────────────

class _TopBar extends GetView<HomeController> {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Text('SnapMeet',
              style: TextStyle(fontFamily: 'Syne', fontSize: 24,
                fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
          ),
          const Spacer(),
          // Icône localisation
          Obx(() => controller.locationError.value
            ? GestureDetector(
                onTap: controller.openLocationSettings,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_off_rounded,
                    size: 18, color: AppColors.accent),
                ),
              )
            : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          _IconBtn(icon: Icons.search_rounded, onTap: () {}),
          const SizedBox(width: 8),
          const BoostProfilWidget(),
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool gradient;
  const _IconBtn({required this.icon, required this.onTap, this.gradient = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient ? AppColors.gradientPink : null,
          color: gradient ? null : AppColors.surface2,
          border: gradient ? null : Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 20,
          color: gradient ? Colors.white : AppColors.textPrimary),
      ),
    );
  }
}

// ─── FILTRES ───────────────────────────────────────────────────

class _FilterChips extends GetView<HomeController> {
  const _FilterChips();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Obx(() => _Chip(label: 'Tous', icon: '⚡', mode: 'all',
            isActive: controller.filterMode.value == 'all',
            onTap: () => controller.setFilter('all'))),
          const SizedBox(width: 8),
          Obx(() => _Chip(label: 'En ligne', icon: '🟢', mode: 'online',
            isActive: controller.filterMode.value == 'online',
            onTap: () => controller.setFilter('online'))),
          const SizedBox(width: 8),
          Obx(() => _Chip(label: '< 500m', icon: '📍', mode: 'nearby',
            isActive: controller.filterMode.value == 'nearby',
            onTap: () => controller.setFilter('nearby'))),
          const SizedBox(width: 8),
          // Bouton filtres avancés
          Obx(() {
            final hasFilter = controller.filterGender.value != 'tous' ||
              controller.filterMinAge.value != 18 ||
              controller.filterMaxAge.value != 50 ||
              controller.filterDistance.value != 50.0;
            return GestureDetector(
              onTap: () => _showFilterPanel(context, controller),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  gradient: hasFilter ? AppColors.gradientPink : null,
                  color: hasFilter ? null : AppColors.surface2,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hasFilter ? Colors.transparent : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 14,
                      color: hasFilter ? Colors.white : AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text('Filtres', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: hasFilter ? Colors.white : AppColors.textMuted)),
                    if (hasFilter) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 6, height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─── FILTER PANEL ────────────────────────────────────────────────

void _showFilterPanel(BuildContext context, HomeController controller) {
  // Variables locales temporaires
  String tempGender = controller.filterGender.value;
  double tempMinAge = controller.filterMinAge.value.toDouble();
  double tempMaxAge = controller.filterMaxAge.value.toDouble();
  double tempDistance = controller.filterDistance.value;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setState) => Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24,
          MediaQuery.of(ctx).viewInsets.bottom + 32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),

            // Titre
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Text('Filtres', style: TextStyle(
                    fontFamily: 'Syne', fontSize: 22,
                    fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                // Reset
                GestureDetector(
                  onTap: () {
                    setState(() {
                      tempGender = 'tous';
                      tempMinAge = 18;
                      tempMaxAge = 50;
                      tempDistance = 50;
                    });
                  },
                  child: const Text('Réinitialiser',
                    style: TextStyle(fontSize: 13,
                      color: AppColors.accent, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── SEXE ──
            const Text('Je cherche', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: AppColors.textMuted, letterSpacing: 0.5)),
            const SizedBox(height: 10),
            Row(
              children: ['tous', 'femme', 'homme'].map((g) {
                final labels = {'tous': '👥 Tout le monde',
                  'femme': '👩 Femmes', 'homme': '👨 Hommes'};
                final isSelected = tempGender == g;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => tempGender = g),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        gradient: isSelected ? AppColors.gradientPink : null,
                        color: isSelected ? null : AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                            ? Colors.transparent : AppColors.border),
                      ),
                      child: Text(labels[g]!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: isSelected
                            ? Colors.white : AppColors.textMuted)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ── ÂGE ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Tranche d'age", style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textMuted, letterSpacing: 0.5)),
                Text('${tempMinAge.toInt()} - ${tempMaxAge.toInt()} ans',
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 8),
            RangeSlider(
              values: RangeValues(tempMinAge, tempMaxAge),
              min: 18, max: 60,
              divisions: 42,
              activeColor: AppColors.accent,
              inactiveColor: AppColors.border,
              onChanged: (v) => setState(() {
                tempMinAge = v.start;
                tempMaxAge = v.end;
              }),
            ),
            const SizedBox(height: 16),

            // ── DISTANCE ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Distance max', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: AppColors.textMuted, letterSpacing: 0.5)),
                Text(tempDistance >= 100
                  ? '100+ km' : '${tempDistance.toInt()} km',
                  style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: tempDistance,
              min: 1, max: 100,
              divisions: 99,
              activeColor: AppColors.accent2,
              inactiveColor: AppColors.border,
              onChanged: (v) => setState(() => tempDistance = v),
            ),
            const SizedBox(height: 24),

            // Bouton Appliquer
            GestureDetector(
              onTap: () {
                controller.applyFilters(
                  gender: tempGender,
                  minAge: tempMinAge.toInt(),
                  maxAge: tempMaxAge.toInt(),
                  distance: tempDistance,
                );
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPink,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.4),
                    blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: const Text('Appliquer les filtres',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16,
                    fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── CHIP ─────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label, icon, mode;
  final bool isActive;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.icon, required this.mode,
    required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive ? AppColors.gradientPink : null,
          color: isActive ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: isActive ? null : Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: isActive ? Colors.white : AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

// ─── GRILLE UTILISATEURS ───────────────────────────────────────

class _UsersGrid extends GetView<HomeController> {
  const _UsersGrid();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.isLoadingUsers.value) return _buildShimmer();
      final users = controller.filteredUsers;
      if (users.isEmpty) return _buildEmpty();
      return RefreshIndicator(
        onRefresh: controller.loadProfiles,
        color: AppColors.accent,
        backgroundColor: AppColors.surface,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
            childAspectRatio: 0.72,
          ),
          itemCount: users.length,
          itemBuilder: (_, i) => _UserCard(
            user: users[i],
            onTap: () => controller.openProfile(users[i]),
          ),
        ),
      );
    });
  }

  Widget _buildShimmer() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3,
        childAspectRatio: 0.72,
      ),
      itemCount: 12,
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.border,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return RefreshIndicator(
      onRefresh: controller.loadProfiles,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListView(
        children: [
          SizedBox(height: MediaQuery.of(Get.context!).size.height * 0.2),
          Center(
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (b) => AppColors.gradientPink.createShader(b),
                  child: const Icon(Icons.people_outline_rounded,
                    size: 64, color: Colors.white),
                ),
                const SizedBox(height: 16),
                const Text('Aucun profil pour l\'instant',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                const Text('Tire vers le bas pour actualiser',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── CARTE UTILISATEUR (style Grindr) ──────────────────────────

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;
  final bool hasNewMessage;
  const _UserCard({required this.user, required this.onTap, this.hasNewMessage = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: hasNewMessage ? const LinearGradient(
            colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ) : null,
        ),
        padding: hasNewMessage ? const EdgeInsets.all(2.5) : EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(hasNewMessage ? 10 : 12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Photo ou gradient
              user.photoUrl != null && user.photoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: user.photoUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _GradientAvatar(name: user.name),
                    errorWidget: (_, __, ___) => _GradientAvatar(name: user.name),
                  )
                : _GradientAvatar(name: user.name),

              // Gradient bas
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                    ),
                  ),
                ),
              ),

              // Infos bas
              Positioned(
                bottom: 6, left: 7, right: 7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.name}, ${user.age}',
                      style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user.distanceMeters != null)
                      Text(user.distanceLabel,
                        style: const TextStyle(fontSize: 10, color: Colors.white70)),
                  ],
                ),
              ),

              // Badge online
              if (user.isOnline)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GradientAvatar extends StatelessWidget {
  final String name;
  const _GradientAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final colors = [
      [const Color(0xFFFF3CAC), const Color(0xFF7B2FFF)],
      [const Color(0xFF7B2FFF), const Color(0xFF00F5D4)],
      [const Color(0xFFFF6B6B), const Color(0xFFFF3CAC)],
      [const Color(0xFF00F5D4), const Color(0xFF7B2FFF)],
    ];
    final idx = name.codeUnitAt(0) % colors.length;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors[idx],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
            color: Colors.white)),
      ),
    );
  }
}