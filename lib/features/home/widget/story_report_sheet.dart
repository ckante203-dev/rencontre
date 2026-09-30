import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ═══════════════════════════════════════════════════════════════
// Signalement d'une story (exigence Google Play pour tout contenu
// publié par les utilisateurs). Enregistré dans `reports` ; la story
// est ensuite masquée pour la personne qui l'a signalée.
// ═══════════════════════════════════════════════════════════════

const _raisons = [
  {'icon': '🔞', 'label': 'Contenu inapproprié'},
  {'icon': '💬', 'label': 'Harcèlement ou spam'},
  {'icon': '⚠️', 'label': 'Violence ou contenu dangereux'},
  {'icon': '🔗', 'label': 'Escroquerie / Arnaque'},
  {'icon': '🤖', 'label': 'Faux profil / Bot'},
  {'icon': '🚩', 'label': 'Autre raison'},
];

/// Ouvre le choix du motif puis envoie le signalement.
/// Renvoie true si la story a été signalée (et donc masquée).
Future<bool> showStoryReportSheet(StoryModel story) async {
  final raison = await choisirMotifSignalement('Pourquoi signaler cette story ?');
  if (raison == null) return false;
  return _envoyerSignalement(story, raison);
}

/// Choix du motif d'un signalement (story, message, personne).
/// Renvoie le motif choisi, ou null si l'utilisateur annule.
Future<String?> choisirMotifSignalement(String titre,
    {String sousTitre = "La personne ne saura pas que c'est toi."}) {
  return Get.bottomSheet<String>(
    Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
          child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(2))),
        ),
        const SizedBox(height: 16),
        Text(titre,
            style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(sousTitre,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        ..._raisons.map((r) => GestureDetector(
              onTap: () => Get.back(result: r['label']),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Text(r['icon']!, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Text(r['label']!,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 18),
                ]),
              ),
            )),
        SizedBox(height: MediaQuery.of(Get.context!).padding.bottom + 16),
      ]),
    ),
    isScrollControlled: true,
  );
}

Future<bool> _envoyerSignalement(StoryModel story, String raison) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null || uid == story.userId) return false;
  final db = Supabase.instance.client.from('reports');
  final base = {
    'reporter_id': uid,
    'reported_id': story.userId,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };
  bool dejaSignale = false;
  try {
    try {
      await db.insert({
        ...base,
        'reason': raison,
        'story_id': story.id,
        if (story.mediaUrl.isNotEmpty) 'story_media_url': story.mediaUrl,
        if (story.isTextStory) 'story_text': story.textContent,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') rethrow;
      // Colonnes story_* absentes (script 20260930000011 pas encore
      // appliqué) : signalement enregistré sur le profil.
      await db.insert({...base, 'reason': 'Story : $raison (${story.id})'});
    }
  } on PostgrestException catch (e) {
    if (e.code != '23505') {
      _snack("Impossible d'envoyer le signalement");
      return false;
    }
    dejaSignale = true;
  } catch (_) {
    _snack("Impossible d'envoyer le signalement");
    return false;
  }

  if (Get.isRegistered<HomeController>()) {
    Get.find<HomeController>().hideStory(story.id);
  }
  _snack(dejaSignale
      ? 'Déjà signalée. Elle ne te sera plus montrée.'
      : 'Signalement envoyé. Merci ! Cette story ne te sera plus montrée.');
  return true;
}

void _snack(String msg) {
  Get.snackbar('Signalement', msg,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white,
      duration: const Duration(seconds: 3));
}
