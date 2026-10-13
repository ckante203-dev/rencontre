import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Partage de position « en direct » (rendez-vous) : un message de type
/// location dont le contenu « lat,lng|live:<fin en ms> » est mis à jour
/// chaque minute jusqu'à la fin (1 h), tant que l'app est ouverte.
/// Indépendant de l'écran de conversation : continue si on le quitte.
class PositionDirect {
  PositionDirect._();

  static Timer? _timer;
  static String? _messageId;
  static DateTime? _fin;
  static final RxnString messageEnCours = RxnString();

  /// « lat,lng|live:123 » → (lat, lng, fin) ; fin null si position simple
  static (double, double, DateTime?)? lire(String? contenu) {
    if (contenu == null) return null;
    final morceaux = contenu.split('|');
    final p = morceaux.first.split(',');
    if (p.length != 2) return null;
    final lat = double.tryParse(p[0].trim()), lng = double.tryParse(p[1].trim());
    if (lat == null || lng == null) return null;
    DateTime? fin;
    for (final m in morceaux.skip(1)) {
      if (m.startsWith('live:')) {
        final ms = int.tryParse(m.substring(5));
        if (ms != null) fin = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return (lat, lng, fin);
  }

  static String _contenu(Position p, DateTime fin) =>
      '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}'
      '|live:${fin.millisecondsSinceEpoch}';

  /// Démarre (un seul partage à la fois). Retourne false en cas d'échec.
  static Future<bool> demarrer(String conversationId) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return false;
    await arreter();
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final fin = DateTime.now().add(const Duration(hours: 1));
      final ligne = await Supabase.instance.client
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': uid,
            'type': 'location',
            'content': _contenu(pos, fin),
            'status': 'sent',
          })
          .select('id')
          .single();
      await Supabase.instance.client
          .from('conversations')
          .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', conversationId);
      _messageId = ligne['id'] as String;
      _fin = fin;
      messageEnCours.value = _messageId;
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _maj());
      return true;
    } catch (e) {
      debugPrint('Position en direct : $e');
      return false;
    }
  }

  static Future<void> _maj() async {
    final id = _messageId, fin = _fin;
    if (id == null || fin == null) return;
    if (DateTime.now().isAfter(fin)) {
      await arreter();
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 30));
      await Supabase.instance.client
          .from('messages')
          .update({'content': _contenu(pos, fin)}).eq('id', id);
    } catch (e) {
      debugPrint('Position en direct (mise à jour) : $e');
    }
  }

  /// Arrête : la fin est ramenée à maintenant (le message n'est plus « en direct »)
  static Future<void> arreter() async {
    _timer?.cancel();
    _timer = null;
    final id = _messageId;
    _messageId = null;
    _fin = null;
    messageEnCours.value = null;
    if (id == null) return;
    try {
      final r = await Supabase.instance.client
          .from('messages')
          .select('content')
          .eq('id', id)
          .maybeSingle();
      final l = lire(r?['content'] as String?);
      if (l == null) return;
      await Supabase.instance.client.from('messages').update({
        'content':
            '${l.$1.toStringAsFixed(6)},${l.$2.toStringAsFixed(6)}|live:${DateTime.now().millisecondsSinceEpoch}'
      }).eq('id', id);
    } catch (_) {}
  }
}
