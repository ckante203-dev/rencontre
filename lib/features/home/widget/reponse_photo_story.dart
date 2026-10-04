import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ══════════════════════════════════════════════════════════════════
//  RÉPONDRE À UNE STORY EN PHOTO (façon Snap)
//  📷 → appareil photo → snap éphémère (10 s) envoyé dans la discussion,
//  avec la miniature de la story au-dessus (comme les réponses texte).
// ══════════════════════════════════════════════════════════════════

class BoutonReponsePhoto extends StatefulWidget {
  final StoryModel story;

  /// Appelé avec true à l'ouverture de l'appareil photo, false au retour :
  /// le viewer met la story en pause pendant ce temps.
  final ValueChanged<bool>? onActif;

  const BoutonReponsePhoto({super.key, required this.story, this.onActif});

  @override
  State<BoutonReponsePhoto> createState() => _BoutonReponsePhotoState();
}

class _BoutonReponsePhotoState extends State<BoutonReponsePhoto> {
  bool _envoi = false;

  void _snack(String titre, [String message = '']) => Get.snackbar(
        titre,
        message,
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );

  Future<void> _repondre() async {
    final story = widget.story;
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null || _envoi) return;
    if (uid == story.userId) {
      _snack('Oups', 'Tu ne peux pas répondre à ta propre story');
      return;
    }

    widget.onActif?.call(true);
    XFile? photo;
    try {
      photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          maxWidth: 1080,
          maxHeight: 1920,
          imageQuality: 80);
    } catch (_) {
      photo = null;
    }
    widget.onActif?.call(false);
    if (photo == null) return;

    if (mounted) setState(() => _envoi = true);
    try {
      final convId = await SupabaseService().getOrCreateConversation(story.userId);
      final chemin =
          'snaps/$uid/reponse_story_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await sb.storage.from('snaps').upload(chemin, File(photo.path),
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url = sb.storage.from('snaps').getPublicUrl(chemin);

      final storyData = StoryReplyData(
        storyId: story.id,
        storyPreviewUrl: story.mediaUrl,
        storyIsVideo: story.isVideo,
        storyOwnerName: story.userName,
        storyText: story.isTextStory ? story.textContent : null,
        storyBgColor: story.isTextStory ? story.bgColor : null,
      );
      final base = {
        'conversation_id': convId,
        'sender_id': uid,
        'type': 'snap',
        'content': '📸 Photo éphémère',
        'media_url': url,
        'status': 'sent',
        'snap_duration': 10,
      };
      final db = sb.from('messages');
      // Comme les réponses texte : avec le texte de la story, puis sans
      // (migration pas appliquée), puis en simple snap.
      try {
        await db.insert({
          ...base,
          ...storyData.toColumns(withText: storyData.storyText != null)
        });
      } catch (e) {
        if (_refusServeur(e)) rethrow;
        try {
          await db.insert({...base, ...storyData.toColumns(withText: false)});
        } catch (e2) {
          if (_refusServeur(e2)) rethrow;
          await db.insert(base);
        }
      }
      await sb.from('conversations').update({
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', convId);
      await SupabaseService().maybePromoteMessageRequest(convId);
      _snack('Photo envoyée ✓', 'Elle disparaît après avoir été vue');
    } catch (e) {
      final t = e.toString();
      if (t.contains('limite_sans_reponse')) {
        _snack('Message non envoyé',
            'Attends sa réponse pour envoyer d\'autres messages');
      } else if (t.contains('bloque')) {
        _snack('Message non envoyé', 'Tu ne peux plus écrire à cette personne');
      } else {
        debugPrint('Réponse photo à la story : $e');
        _snack('Erreur', "Impossible d'envoyer la photo");
      }
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  /// Refus volontaire du serveur (limite, blocage) : inutile de réessayer.
  bool _refusServeur(Object e) {
    final t = e.toString();
    return t.contains('limite_sans_reponse') || t.contains('bloque');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _repondre,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24),
        ),
        child: _envoi
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.photo_camera_rounded,
                color: Colors.white, size: 21),
      ),
    );
  }
}
