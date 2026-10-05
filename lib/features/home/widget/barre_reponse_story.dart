import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/widget/reponse_photo_story.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ─── BARRE DE RÉPONSE À UNE STORY (façon Snapchat) ────────────────
// Sous la story, séparée d'elle : 📷 | « Répondre à Awa… » | ❤️ | 👍.
// ❤️ et 👍 = réponses rapides envoyées tout de suite ; dès qu'on écrit,
// les deux laissent place au bouton Envoyer. Utilisée par le lecteur de
// stories et par le fil de l'onglet Story.

class BarreReponseStory extends StatefulWidget {
  final StoryModel story;
  final bool aime;
  final VoidCallback onLike;
  final ValueChanged<bool> onFocusChanged;
  const BarreReponseStory(
      {super.key,
      required this.story,
      required this.aime,
      required this.onLike,
      required this.onFocusChanged});
  @override
  State<BarreReponseStory> createState() => _BarreReponseStoryState();
}

class _BarreReponseStoryState extends State<BarreReponseStory>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false, _hasText = false;
  String? _confirmation; // « Envoyé à Awa ✓ » (petit badge, pas de snackbar)
  late final AnimationController _coeur;

  String get _prenom {
    final n = widget.story.userName.trim();
    return n.isEmpty ? 'la story' : n.split(' ').first;
  }

  @override
  void initState() {
    super.initState();
    _coeur = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _focus.addListener(() {
      widget.onFocusChanged(_focus.hasFocus);
      if (mounted) setState(() {});
    });
    _ctrl.addListener(() {
      final h = _ctrl.text.trim().isNotEmpty;
      if (h != _hasText) setState(() => _hasText = h);
    });
  }

  void _confirmer(String texte) {
    setState(() => _confirmation = texte);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _confirmation = null);
    });
  }

  /// ❤️ = réponse rapide (message « ❤️ » envoyé avec l'aperçu de la
  /// story), comme 👍 — ce n'est plus un like.
  void _aimer() {
    if (_sending) return;
    _coeur.forward(from: 0);
    _send('❤️');
  }

  Future<void> _send([String? rapide]) async {
    final text = (rapide ?? _ctrl.text).trim();
    if (text.isEmpty || _sending) return;
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (uid == widget.story.userId) {
      Get.snackbar('Oups', 'Tu ne peux pas répondre à ta propre story',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
      return;
    }
    setState(() => _sending = true);
    try {
      // ✅ MODIFIÉ — passe par le point d'entrée centralisé au lieu
      // de dupliquer la recherche/création de conversation. Ça
      // applique automatiquement la règle "sans match, la
      // conversation démarre en demande de message (pending)".
      final convId = await SupabaseService().getOrCreateConversation(
        widget.story.userId,
      );
      final storyData = StoryReplyData(
        storyId: widget.story.id,
        storyPreviewUrl: widget.story.mediaUrl,
        storyIsVideo: widget.story.isVideo,
        storyOwnerName: widget.story.userName,
        storyText: widget.story.isTextStory ? widget.story.textContent : null,
        storyBgColor: widget.story.isTextStory ? widget.story.bgColor : null,
      );
      final safeContent = text.substring(0, text.length.clamp(0, 500));
      if (Get.isRegistered<ConversationController>(tag: convId)) {
        await Get.find<ConversationController>(tag: convId).sendStoryReply(
          conversationId: convId,
          text: safeContent,
          storyData: storyData,
        );
      } else {
        await ConversationController.insertStoryReplyRow(
          conversationId: convId,
          senderId: uid,
          text: safeContent,
          storyData: storyData,
        );
        await Supabase.instance.client.from('conversations').update(
            {'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', convId); // ✅ UTC
        // ✅ Si je réponds à la story de quelqu'un qui m'avait
        // lui-même écrit sans match, ma réponse fait passer la
        // conversation de "demande" à "acceptée".
        await SupabaseService().maybePromoteMessageRequest(convId);
      }
      if (rapide == null) _ctrl.clear();
      _focus.unfocus();
      widget.onFocusChanged(false);
      HapticFeedback.lightImpact();
      if (mounted) _confirmer('Envoyé à ${_prenom} ✓');
    } catch (e) {
      debugPrint('replyStory error: $e');
      if (mounted) {
        Get.snackbar('Erreur', "Impossible d'envoyer le message",
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _coeur.dispose();
    super.dispose();
  }

  /// Petite icône dans le champ (❤️ / 👍), zone de toucher confortable.
  Widget _icone({required Widget child, VoidCallback? onTap}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
            width: 38, height: 44, child: Center(child: child)),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(clipBehavior: Clip.none, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        // 📷 Répondre en photo (snap éphémère), façon Snap
        BoutonReponsePhoto(
            story: widget.story, onActif: widget.onFocusChanged),
        const SizedBox(width: 8),
        // Champ « Répondre à Awa… » avec ❤️ et 👍 DEDANS, à droite
        // (comme Snapchat) ; ils s'effacent quand on écrit.
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, maxHeight: 110),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: _focus.hasFocus
                    ? AppColors.accent.withValues(alpha: 0.7)
                    : Colors.white24,
                width: _focus.hasFocus ? 1.5 : 1,
              ),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  maxLines: 4,
                  minLines: 1,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  buildCounter: (_,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Répondre à $_prenom…',
                    hintStyle:
                        const TextStyle(color: Colors.white54, fontSize: 14),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 160),
                child: _hasText
                    ? const SizedBox(width: 10)
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        _icone(
                          onTap: _aimer,
                          child: ScaleTransition(
                            scale: TweenSequence([
                              TweenSequenceItem(
                                  tween: Tween(begin: 1.0, end: 1.4),
                                  weight: 50),
                              TweenSequenceItem(
                                  tween: Tween(begin: 1.4, end: 1.0),
                                  weight: 50),
                            ]).animate(CurvedAnimation(
                                parent: _coeur, curve: Curves.easeOut)),
                            child: const Text('❤️',
                                style: TextStyle(fontSize: 20)),
                          ),
                        ),
                        _icone(
                          onTap: _sending ? null : () => _send('👍'),
                          child:
                              const Text('👍', style: TextStyle(fontSize: 20)),
                        ),
                        const SizedBox(width: 6),
                      ]),
              ),
            ]),
          ),
        ),
        // Envoyer : seulement quand un message est écrit
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: !_hasText
              ? const SizedBox.shrink(key: ValueKey('rien'))
              : Padding(
                  key: const ValueKey('envoyer'),
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          gradient: AppColors.gradientPink,
                          shape: BoxShape.circle),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ),
        ),
      ]),
      // Confirmation discrète au-dessus de la barre
      if (_confirmation != null)
        Positioned(
          top: -40,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(_confirmation!,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ),
    ]);
  }
}
