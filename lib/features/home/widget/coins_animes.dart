import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// « Coins animés » : zones (≈ 1 km) où il y a le plus de membres actifs
/// aujourd'hui autour de moi (fonction lieux_populaires, SQL 059).
/// Aucune personne n'est identifiable : 3 membres au moins par zone.
Future<void> afficherCoinsAnimes(double? lat, double? lng) async {
  if (lat == null || lng == null) {
    Get.snackbar('🔥', 'Active la localisation pour voir les coins animés'.tr,
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: AppColors.textPrimary);
    return;
  }
  List zones = const [];
  try {
    zones = await Supabase.instance.client.rpc('lieux_populaires',
        params: {'p_lat': lat, 'p_lng': lng}) as List;
  } catch (e) {
    debugPrint('Coins animés : $e');
  }
  // Nom du quartier (OpenStreetMap), au mieux
  Future<String> nom(double la, double lo) async {
    try {
      final r = await http.get(
          Uri.parse(
              'https://nominatim.openstreetmap.org/reverse?lat=$la&lon=$lo&format=json&zoom=15&accept-language=fr'),
          headers: {'User-Agent': 'Zamu/1.0'}).timeout(const Duration(seconds: 6));
      final a = (jsonDecode(r.body) as Map)['address'] as Map? ?? {};
      return (a['suburb'] ?? a['neighbourhood'] ?? a['quarter'] ??
              a['city_district'] ?? a['town'] ?? a['city'] ?? '')
          .toString();
    } catch (_) {
      return '';
    }
  }

  final noms = await Future.wait([
    for (final z in zones)
      nom((z['lat'] as num).toDouble(), (z['lng'] as num).toDouble())
  ]);
  Get.bottomSheet(
    Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("🔥 Coins animés aujourd'hui".tr,
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          if (zones.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Text(
                  'Pas encore assez de monde autour de toi. Reviens ce soir !'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textMuted)),
            ),
          for (var i = 0; i < zones.length; i++)
            ListTile(
              leading: Text(['🥇', '🥈', '🥉', '4️⃣', '5️⃣'][i.clamp(0, 4)],
                  style: const TextStyle(fontSize: 22)),
              title: Text(
                  noms[i].isEmpty ? 'Zone @n'.trParams({'n': '${i + 1}'}) : noms[i],
                  style: TextStyle(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  "@n membres actifs aujourd'hui".trParams({'n': '${zones[i]['nb']}'}),
                  style: TextStyle(color: AppColors.textMuted)),
              trailing: Icon(Icons.map_rounded, color: AppColors.textMuted),
              // Ouvre la zone dans l'appli de cartes du téléphone
              onTap: () => launchUrl(
                  Uri.parse(
                      'https://www.google.com/maps/search/?api=1&query=${zones[i]['lat']},${zones[i]['lng']}'),
                  mode: LaunchMode.externalApplication),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    ),
  );
}
