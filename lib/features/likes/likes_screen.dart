import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/discover_feed_viewer.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';

// ══════════════════════════════════════════════════════════════════
//  ONGLET "STORY" — ✅ RÉÉCRIT : plus de grille "Découvrir". Dès
//  l'arrivée sur cet onglet, on tombe directement dans le flux
//  plein écran (façon TikTok), avec swipe vertical pour passer
//  d'une story à l'autre. Les stories d'un même profil se suivent
//  (regroupement conservé), puis on enchaîne sur le profil suivant.
// ══════════════════════════════════════════════════════════════════

class LikesScreen extends StatelessWidget {
  const LikesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeController>()) {
      Get.put(HomeController(), permanent: true);
    }
    final controller = Get.find<HomeController>();

    return Obx(() {
      final discoverStories = controller.discoverStories;
      final discoverCards = buildDiscoverCards(discoverStories);
      final flat = flattenDiscoverCards(discoverCards);

      // ✅ NOUVEAU — sait si l'onglet "Story" est réellement affiché
      // (vs monté en arrière-plan via IndexedStack), pour couper le
      // son/la vidéo dès qu'on change d'onglet.
      final isActiveTab = Get.isRegistered<NavigationController>()
          ? Get.find<NavigationController>().currentIndex.value == 3
          : true;

      return DiscoverFeedViewerScreen(
        items: flat,
        initialIndex: 0,
        // ✅ Pas de bouton fermer : on est sur un onglet persistant,
        // il n'y a rien "au-dessus" vers quoi revenir.
        showCloseButton: false,
        // ✅ Bouton actualiser flottant, puisque le geste vertical
        // est déjà pris par le changement de story (pas de place
        // pour un RefreshIndicator classique).
        onRefresh: controller.loadStories,
        isActiveTab: isActiveTab,
      );
    });
  }
}
