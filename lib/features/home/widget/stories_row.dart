import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';

class StoriesRow extends GetView<HomeController> {
  const StoriesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Obx(() {
        if (controller.isLoadingStories.value) {
          return _buildShimmer();
        }
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: controller.stories.length + 1, // +1 for "Add story"
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            if (index == 0) return const _AddStoryItem();
            final story = controller.stories[index - 1];
            return _StoryItem(story: story);
          },
        );
      }),
    );
  }

  Widget _buildShimmer() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.border,
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(
                color: AppColors.surface2,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 40,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddStoryItem extends GetView<HomeController> {
  const _AddStoryItem();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: controller.openAddStory,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent2, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.bg, width: 2),
            ),
            child: const Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ma story',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryItem extends GetView<HomeController> {
  final StoryModel story;
  const _StoryItem({required this.story});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => controller.openStory(story),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ring gradient (unseen) or grey (seen)
          Container(
            width: 62,
            height: 62,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: story.isSeen
                  ? null
                  : const LinearGradient(
                      colors: [AppColors.accent, AppColors.accent2, AppColors.accent3],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              color: story.isSeen ? AppColors.border : null,
              shape: BoxShape.circle,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.bg,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(2),
              child: Stack(
                children: [
                  // Avatar
                  ClipOval(
                    child: story.userPhotoUrl != null
                        ? CachedNetworkImage(
                            imageUrl: story.userPhotoUrl!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                              color: AppColors.surface2,
                            ),
                          )
                        : Container(
                            color: AppColors.surface2,
                            child: Center(
                              child: Text(
                                story.userName[0].toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                  ),
                  // Video indicator
                  if (story.isVideo)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 62,
            child: Text(
              story.userName.split(' ').first,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
