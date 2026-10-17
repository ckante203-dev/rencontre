import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_palette.dart';

/// Apparence choisie : suit le téléphone, toujours sombre ou toujours
/// claire. EN PRÉPARATION : le réglage n'est proposé qu'en développement
/// (voir EcranThemes) tant que tous les écrans ne sont pas prêts pour le
/// fond blanc ; par défaut tout le monde reste en sombre.
enum Apparence { systeme, sombre, clair }

class ThemeController extends GetxController with WidgetsBindingObserver {
  static ThemeController get to => Get.find();

  static const _storageKey = 'app_theme_id';
  static const _cleApparence = 'app_apparence';
  final _box = GetStorage();

  /// Couleur choisie par l'utilisateur (Zamu, Lagune…), enregistrée aussi
  /// dans profiles.theme
  final Rx<AppPalette> choix = AppPalettes.defaut.obs;

  final Rx<Apparence> apparence = Apparence.sombre.obs;

  /// Palette réellement affichée : [choix] en sombre, la palette claire
  /// quand l'apparence est claire (ou « système » avec un téléphone en
  /// mode clair). Tous les écrans lisent celle-ci (via AppColors).
  final Rx<AppPalette> palette = AppPalettes.defaut.obs;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  void loadInitial() {
    final savedId = _box.read<String>(_storageKey);
    final p = AppPalettes.resoudre(savedId);
    if (p != null) {
      choix.value = p;
      // Ancien thème néon : on enregistre le thème pro qui le remplace
      if (p.id != savedId) _box.write(_storageKey, p.id);
    }
    final a = _box.read<String>(_cleApparence);
    apparence.value = Apparence.values.firstWhereOrNull((x) => x.name == a) ??
        Apparence.sombre;
    palette.value = _effective();
  }

  /// Fond clair à afficher maintenant ?
  bool get clairEffectif => switch (apparence.value) {
        Apparence.clair => true,
        Apparence.sombre => false,
        Apparence.systeme =>
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.light,
      };

  AppPalette _effective() {
    // La palette « Blanc » choisie directement (ancien essai) reste claire
    if (choix.value.clair) return choix.value;
    return clairEffectif ? AppPalettes.blanc : choix.value;
  }

  void _recalculer() {
    final p = _effective();
    if (p.id == palette.value.id) return;
    palette.value = p;
    _appliquerPartout();
  }

  Future<void> setTheme(String id) async {
    final selected = AppPalettes.resoudre(id);
    if (selected == null || selected.id == choix.value.id) return;

    choix.value = selected;
    id = selected.id;
    _recalculer();
    await _box.write(_storageKey, id);

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != null) {
      try {
        await Supabase.instance.client
            .from('profiles')
            .update({'theme': id}).eq('id', uid);
      } catch (_) {
        // pas bloquant
      }
    }
  }

  void setApparence(Apparence a) {
    if (a == apparence.value) return;
    apparence.value = a;
    _box.write(_cleApparence, a.name);
    _recalculer();
  }

  void applyRemote(String id) {
    final selected = AppPalettes.resoudre(id);
    if (selected == null || selected.id == choix.value.id) return;
    choix.value = selected;
    _box.write(_storageKey, selected.id);
    _recalculer();
  }

  /// Le téléphone passe en clair / sombre : suivi en mode « Système »
  @override
  void didChangePlatformBrightness() {
    if (apparence.value == Apparence.systeme) _recalculer();
  }

  /// Les écrans lisent leurs couleurs dans `AppColors` (pas dans le thème
  /// Flutter) : on reconstruit toute l'app, y compris les pages déjà
  /// ouvertes, pour que le nouveau thème s'applique sans redémarrer.
  void _appliquerPartout() {
    SystemChrome.setSystemUIOverlayStyle(palette.value.barreSysteme);
    Get.forceAppUpdate();
  }
}
