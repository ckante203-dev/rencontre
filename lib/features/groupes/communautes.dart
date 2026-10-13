import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/groupes/ecran_groupe.dart';
import 'package:rencontre/features/groupes/groupes_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Communautés : groupes publics créés par l'équipe Zamu (SQL 060), que
/// chacun peut rejoindre librement (300 membres au maximum).
class EcranCommunautes extends StatefulWidget {
  const EcranCommunautes({super.key});

  @override
  State<EcranCommunautes> createState() => _EcranCommunautesState();
}

class _EcranCommunautesState extends State<EcranCommunautes> {
  List<Map<String, dynamic>>? _liste;
  String? _enCours;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await Supabase.instance.client.rpc('groupes_publics');
      if (mounted) setState(() => _liste = List<Map<String, dynamic>>.from(r as List));
    } catch (e) {
      debugPrint('Communautés : $e');
      if (mounted) setState(() => _liste = const []);
    }
  }

  Future<void> _rejoindre(Map<String, dynamic> g) async {
    final id = g['id'] as String;
    setState(() => _enCours = id);
    try {
      if (g['deja_membre'] != true) {
        await Supabase.instance.client
            .rpc('rejoindre_groupe_public', params: {'p_groupe': id});
      }
      final ctrl = GroupesController.to;
      await ctrl.charger();
      final groupe = ctrl.groupes.firstWhereOrNull((x) => x.id == id);
      if (groupe != null) Get.off(() => EcranGroupe(groupe: groupe));
    } on PostgrestException catch (e) {
      Get.snackbar(
          '🌍',
          e.message.contains('complet')
              ? 'Cette communauté est complète'.tr
              : 'Action impossible, réessaie'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    } catch (_) {
      Get.snackbar('🌍', 'Vérifie ta connexion et réessaie'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    } finally {
      if (mounted) setState(() => _enCours = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final liste = _liste;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('🌍 Communautés'.tr,
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: liste == null
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : liste.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                        'Les premières communautés arrivent bientôt 🌍'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _charger,
                  color: AppColors.accent,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: liste.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final g = liste[i];
                      final photo = (g['photo_url'] ?? '').toString();
                      final membre = g['deja_membre'] == true;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.surface2,
                            backgroundImage: photo.isNotEmpty
                                ? CachedNetworkImageProvider(photo, maxWidth: 200)
                                : null,
                            child: photo.isEmpty
                                ? const Text('🌍', style: TextStyle(fontSize: 22))
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${g['nom']}',
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary)),
                                  if ((g['description'] ?? '').toString().isNotEmpty)
                                    Text('${g['description']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted)),
                                  Text(
                                      '@n membres'.trParams(
                                          {'n': '${g['nb_membres'] ?? 0}'}),
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textMuted)),
                                ]),
                          ),
                          const SizedBox(width: 8),
                          _enCours == g['id']
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppColors.accent))
                              : TextButton(
                                  onPressed: () => _rejoindre(g),
                                  child: Text(
                                      membre ? 'Ouvrir'.tr : 'Rejoindre'.tr,
                                      style: TextStyle(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.w800)),
                                ),
                        ]),
                      );
                    },
                  ),
                ),
    );
  }
}
