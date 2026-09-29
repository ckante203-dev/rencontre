import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_palette.dart';

class ThemeController extends GetxController {
  static ThemeController get to => Get.find();

  static const _storageKey = 'app_theme_id';
  final _box = GetStorage();

  final Rx<AppPalette> palette = AppPalettes.dark.obs;

  void loadInitial() {
    final savedId = _box.read<String>(_storageKey);
    if (savedId != null && AppPalettes.all.containsKey(savedId)) {
      palette.value = AppPalettes.all[savedId]!;
    }
  }

  Future<void> setTheme(String id) async {
    final selected = AppPalettes.all[id];
    if (selected == null || selected.id == palette.value.id) return;

    palette.value = selected;
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
    final selected = AppPalettes.all[id];
    if (selected == null || selected.id == palette.value.id) return;
    palette.value = selected;
    _box.write(_storageKey, id);
  }
}
