import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/shared/models/user_model.dart';

class EcranProfil extends StatelessWidget {
  const EcranProfil({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(ControleurProfil());
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(child: CircularProgressIndicator(
            color: AppColors.accent));
        }
        final profil = ctrl.monProfil.value;
        return CustomScrollView(
          slivers: [
            _SliverHeader(ctrl: ctrl, profil: profil),
            SliverToBoxAdapter(child: _Corps(ctrl: ctrl, profil: profil)),
          ],
        );
      }),
    );
  }
}

// ─── HEADER AVEC PHOTO ─────────────────────────────────────────

class _SliverHeader extends StatelessWidget {
  final ControleurProfil ctrl;
  final UserModel? profil;
  const _SliverHeader({required this.ctrl, required this.profil});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 280,
      pinned: true,
      backgroundColor: AppColors.bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Photo de fond
            Obx(() {
              final url = ctrl.monProfil.value?.photoUrl;
              return url != null && url.isNotEmpty
                ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _DefaultBg(
                      name: ctrl.monProfil.value?.name ?? '?'))
                : _DefaultBg(name: ctrl.monProfil.value?.name ?? '?');
            }),
            // Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent,
                    AppColors.bg.withOpacity(0.3), AppColors.bg],
                ),
              ),
            ),
            // Bouton changer photo
            Positioned(
              bottom: 16, right: 16,
              child: Obx(() => GestureDetector(
                onTap: ctrl.changerPhoto,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ctrl.isUploadingPhoto.value
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2,
                          color: Colors.white))
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Changer', style: TextStyle(fontSize: 12,
                            fontWeight: FontWeight.w600, color: Colors.white)),
                        ],
                      ),
                ),
              )),
            ),
          ],
        ),
      ),
      // Top bar
      title: const Text('Mon profil',
        style: TextStyle(fontFamily: 'Syne', fontSize: 16,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      actions: [
        GestureDetector(
          onTap: ctrl.deconnexion,
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.logout_rounded, size: 15, color: AppColors.accent),
                SizedBox(width: 5),
                Text('Sortir', style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w700, color: AppColors.accent)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DefaultBg extends StatelessWidget {
  final String name;
  const _DefaultBg({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1a0a2e), Color(0xFF2d0a1e)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w900,
            color: Colors.white24)),
      ),
    );
  }
}

// ─── CORPS DU PROFIL ───────────────────────────────────────────

class _Corps extends StatelessWidget {
  final ControleurProfil ctrl;
  final UserModel? profil;
  const _Corps({required this.ctrl, required this.profil});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Nom + âge ────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(profil?.name ?? 'Utilisateur',
                          style: const TextStyle(fontFamily: 'Syne', fontSize: 26,
                            fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _showEditNameDialog(context, ctrl, profil?.name ?? ''),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(Icons.edit_rounded,
                              size: 14, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    Text('${profil?.age ?? 18} ans',
                      style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
                  ],
                ),
              ),
              // Badge online
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.online.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.online.withOpacity(0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: AppColors.online),
                    SizedBox(width: 5),
                    Text('En ligne', style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w700, color: AppColors.online)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Stats ─────────────────────────────────────────────
          _StatsRow(profil: profil),
          const SizedBox(height: 24),

          // ── Bio ───────────────────────────────────────────────
          _Section(
            title: 'Ma bio',
            icon: '✍️',
            child: TextField(
              controller: ctrl.bioController,
              maxLines: 3,
              maxLength: 150,
              style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Dis quelque chose sur toi...',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true, fillColor: AppColors.surface2,
                counterStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.accent)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Intérêts ──────────────────────────────────────────
          if (profil?.interests != null && profil!.interests.isNotEmpty)
            _Section(
              title: 'Mes intérêts',
              icon: '🎯',
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: profil!.interests.map((i) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(i, style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w600, color: Colors.white)),
                )).toList(),
              ),
            ),
          const SizedBox(height: 24),

          // ── Bouton sauvegarder ────────────────────────────────
          GestureDetector(
            onTap: ctrl.sauvegarderBio,
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: AppColors.accent.withOpacity(0.3),
                    blurRadius: 20, offset: const Offset(0, 6)),
                ],
              ),
              child: const Center(
                child: Text('Sauvegarder les modifications',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                    color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Bouton déconnexion ────────────────────────────────
          GestureDetector(
            onTap: ctrl.deconnexion,
            child: Container(
              width: double.infinity, height: 52,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error.withOpacity(0.4)),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: AppColors.error),
                    SizedBox(width: 8),
                    Text('Se déconnecter',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: AppColors.error)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditNameDialog(BuildContext context, dynamic ctrl, String currentName) {
    final nameCtrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Changer ton prénom',
          style: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800,
            color: AppColors.textPrimary)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nouveau prénom',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true, fillColor: AppColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accent, width: 2)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler',
              style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty) {
                await Supabase.instance.client
                  .from('profiles')
                  .update({'name': newName})
                  .eq('id', Supabase.instance.client.auth.currentUser!.id);
                ctrl.chargerMonProfil();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Sauvegarder',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ─── STATS ─────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final UserModel? profil;
  const _StatsRow({required this.profil});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(value: '${profil?.matchesCount ?? 0}', label: 'Matchs',
            color: AppColors.accent),
          Container(width: 1, height: 32, color: AppColors.border),
          _StatItem(value: '${profil?.followersCount ?? 0}', label: 'Abonnés',
            color: AppColors.accent2),
          Container(width: 1, height: 32, color: AppColors.border),
          _StatItem(value: '${profil?.followingCount ?? 0}', label: 'Abonnements',
            color: AppColors.accent3),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatItem({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (b) => LinearGradient(
            colors: [color, color.withOpacity(0.7)]).createShader(b),
          child: Text(value, style: const TextStyle(fontFamily: 'Syne',
            fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}

// ─── SECTION ───────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title, icon;
  final Widget child;
  const _Section({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(title.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.textMuted, letterSpacing: 0.8)),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}