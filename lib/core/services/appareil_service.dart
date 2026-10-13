import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Identifiant Android du téléphone enregistré sur le profil : la base
/// bannit automatiquement un compte qui utilise un appareil banni
/// (SQL 057). Sans effet si la colonne n'existe pas encore.
class AppareilService {
  AppareilService._();

  static Future<void> enregistrer() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || !Platform.isAndroid) return;
    try {
      final id = await const MethodChannel('zamu/appareil')
          .invokeMethod<String>('id');
      if (id == null || id.isEmpty) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'appareil': id}).eq('id', uid);
    } catch (e) {
      debugPrint('Appareil non enregistré : $e');
    }
  }
}
