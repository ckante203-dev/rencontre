import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_palette.dart';

class ThemeController extends GetxController {
  static ThemeController get to => Get.find();

  static const _storageKey = 'app_theme_id';
  final _box = GetStorage();

  final Rx<AppPalette> palette = AppPalettes.defaut.obs;

  void loadInitial() {
    final savedId = _box.read<String>(_storageKey);
    final p = AppPalettes.resoudre(savedId);
    if (p != null) {
      palette.value = p;
      // Ancien thème néon : on enregistre le thème pro qui le remplace
      if (p.id != savedId) _box.write(_storageKey, p.id);
    }
  }

  Future<void> setTheme(String id) async {
    final selected = AppPalettes.resoudre(id);
    if (selected == null || selected.id == palette.value.id) return;

    palette.value = selected;
    id = selected.id;
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

  void applyRemote(String id) {
    final selected = AppPalettes.resoudre(id);
    if (selected == null || selected.id == palette.value.id) return;
    palette.value = selected;
    _box.write(_storageKey, selected.id);
  }
}
