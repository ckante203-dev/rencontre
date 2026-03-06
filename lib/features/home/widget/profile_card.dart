import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/shared/models/user_model.dart';

class ProfileCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;

  const ProfileCard({
    super.key,
    required this.user,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: AppColors.surface2,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo ou avatar
            _buildMedia(),

            // Gradient overlay bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 70,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${user.name}, ${user.age}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (user.distanceLabel.isNotEmpty)
                      Text(
                        user.distanceLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.65),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Online dot
            if (user.isOnline)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppColors.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.online.withOpacity(0.5),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),

            // "New" badge
            if (_isNew())
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'NEW',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (user.photoUrl != null) {
      return CachedNetworkImage(
        imageUrl: user.photoUrl!,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: AppColors.surface2),
        errorWidget: (_, __, ___) => _buildFallback(),
      );
    }
    return _buildFallback();
  }

  Widget _buildFallback() {
    // Color based on name hash
    final colors = [
      [const Color(0xFFFF6B6B), const Color(0xFFFECA57)],
      [const Color(0xFF48DBFB), const Color(0xFFFF9FF3)],
      [const Color(0xFFFF9F43), const Color(0xFFEE5A24)],
      [const Color(0xFFA29BFE), const Color(0xFF6C5CE7)],
      [const Color(0xFFFD79A8), const Color(0xFFE84393)],
      [const Color(0xFF55EFC4), const Color(0xFF00B894)],
    ];
    final idx = user.name.hashCode.abs() % colors.length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors[idx],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          user.name[0].toUpperCase(),
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  bool _isNew() {
    // Consider "new" if joined in last 48h (you'd store this in the model)
    return false; // TODO: implement with user.createdAt
  }
}
