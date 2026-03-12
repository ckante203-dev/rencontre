import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _currentVersion = '1.0.0';

  static Future<void> checkForUpdate() async {
    try {
      final data = await Supabase.instance.client
          .from('app_config')
          .select('latest_version, download_url, release_notes, force_update')
          .eq('id', 'config')
          .single();

      final latestVersion = data['latest_version'] as String;
      final downloadUrl = data['download_url'] as String;
      final releaseNotes = data['release_notes'] as String? ?? '';
      final forceUpdate = data['force_update'] as bool? ?? false;

      if (_isNewerVersion(latestVersion, _currentVersion)) {
        _showUpdateDialog(
          latestVersion: latestVersion,
          downloadUrl: downloadUrl,
          releaseNotes: releaseNotes,
          forceUpdate: forceUpdate,
        );
      }
    } catch (e) {
      debugPrint('Update check error: $e');
    }
  }

  static bool _isNewerVersion(String latest, String current) {
    final l = latest.split('.').map(int.parse).toList();
    final c = current.split('.').map(int.parse).toList();
    for (int i = 0; i < 3; i++) {
      final lv = i < l.length ? l[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }

  static void _showUpdateDialog({
    required String latestVersion,
    required String downloadUrl,
    required String releaseNotes,
    required bool forceUpdate,
  }) {
    Get.dialog(
      WillPopScope(
        onWillPop: () async => !forceUpdate,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Text('🚀 ', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Text(
                'Mise à jour disponible',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version $latestVersion disponible',
                style: const TextStyle(
                    color: Color(0xFFFF3CAC), fontWeight: FontWeight.w600),
              ),
              if (releaseNotes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  releaseNotes,
                  style:
                      const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
                ),
              ],
              if (forceUpdate) ...[
                const SizedBox(height: 12),
                const Text(
                  '⚠️ Cette mise à jour est obligatoire.',
                  style: TextStyle(color: Color(0xFFFF5252), fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            if (!forceUpdate)
              TextButton(
                onPressed: () => Get.back(),
                child: const Text('Plus tard',
                    style: TextStyle(color: Color(0xFF666666))),
              ),
            ElevatedButton(
              onPressed: () => _downloadUpdate(downloadUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3CAC),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Télécharger',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      barrierDismissible: !forceUpdate,
    );
  }

  static Future<void> _downloadUpdate(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
