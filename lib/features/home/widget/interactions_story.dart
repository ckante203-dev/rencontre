import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/widget/stickers_story.dart';
import 'package:rencontre/shared/models/story_model.dart';

// ─── STICKERS DE RENCONTRE : ACTIONS DANS LE LECTEUR (SQL 086) ─────
//   🙋 Dispo ce soir : « Je suis dispo ! » envoyé en réponse à la story
//   💘 Crush anonyme : envoyer_crush_story (révélé si like réciproque)
//   🔥 Vibe check    : voter_story / resultats_story / votants_story
//   ❓ Question      : la question arrive en message privé
//   💯 Note mon look : noter_curseur_story / resultat_curseur_story (SQL 088)
//   ⏰ Rendez-vous   : « Je viens » envoyé en message privé
//   📍 Ma ville      : décoratif

SupabaseClient get _sb => Supabase.instance.client;

void _info(String titre, String texte) => Get.snackbar(titre, texte,
    snackPosition: SnackPosition.TOP,
    backgroundColor: const Color(0xFF1C1C1E),
    colorText: Colors.white,
    duration: const Duration(seconds: 3));

/// Réponse privée à une story (même chemin que la barre de réponse).
Future<bool> repondreAStory(StoryModel story, String texte) async {
  final uid = _sb.auth.currentUser?.id;
  if (uid == null || uid == story.userId) return false;
  try {
    final convId = await SupabaseService().getOrCreateConversation(story.userId);
    final storyData = StoryReplyData(
      storyId: story.id,
      storyPreviewUrl: story.mediaUrl,
      storyIsVideo: story.isVideo,
      storyOwnerName: story.userName,
      storyText: story.isTextStory ? story.textContent : null,
      storyBgColor: story.isTextStory ? story.bgColor : null,
    );
    if (Get.isRegistered<ConversationController>(tag: convId)) {
      await Get.find<ConversationController>(tag: convId).sendStoryReply(
          conversationId: convId, text: texte, storyData: storyData);
    } else {
      await ConversationController.insertStoryReplyRow(
          conversationId: convId,
          senderId: uid,
          text: texte,
          storyData: storyData);
      await _sb.from('conversations').update({
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', convId);
      await SupabaseService().maybePromoteMessageRequest(convId);
    }
    return true;
  } catch (e) {
    debugPrint('repondreAStory : $e');
    return false;
  }
}

/// Sticker de rencontre dans le lecteur de story.
class StickerInteractif extends StatefulWidget {
  final StickerStory sticker;
  final StoryModel story;
  const StickerInteractif(
      {super.key, required this.sticker, required this.story});

  @override
  State<StickerInteractif> createState() => _StickerInteractifState();
}

class _StickerInteractifState extends State<StickerInteractif> {
  bool _occupe = false;
  bool _envoye = false;
  // Sondage
  int? _monChoix;
  int _votes0 = 0, _votes1 = 0;
  bool _resultatsCharges = false;
  // Note mon look
  double _curseur = 0.5;
  int? _moyenne, _nombre;
  bool _aNote = false; // j'ai déjà noté

  StickerStory get s => widget.sticker;
  bool get _auteur => _sb.auth.currentUser?.id == widget.story.userId;

  @override
  void initState() {
    super.initState();
    if (s.type == 'sondage') _chargerResultats();
    if (s.type == 'curseur') _chargerCurseur();
  }

  Future<void> _chargerResultats() async {
    try {
      final r = await _sb
          .rpc('resultats_story', params: {'p_story': widget.story.id}) as List;
      if (r.isNotEmpty && mounted) _appliquer(r.first as Map);
    } catch (_) {}
    if (mounted) setState(() => _resultatsCharges = true);
  }

  void _appliquer(Map r) => setState(() {
        _votes0 = (r['votes_0'] as num?)?.toInt() ?? 0;
        _votes1 = (r['votes_1'] as num?)?.toInt() ?? 0;
        _monChoix = (r['mon_choix'] as num?)?.toInt();
      });

  Future<void> _chargerCurseur() async {
    try {
      final r = await _sb.rpc('resultat_curseur_story',
          params: {'p_story': widget.story.id}) as List;
      if (r.isNotEmpty && mounted) _appliquerCurseur(r.first as Map);
    } catch (_) {}
  }

  void _appliquerCurseur(Map r) => setState(() {
        _moyenne = (r['moyenne'] as num?)?.toInt();
        _nombre = (r['nombre'] as num?)?.toInt();
        final m = (r['ma_note'] as num?)?.toInt();
        if (m != null) {
          _aNote = true;
          _curseur = m / 100;
        }
      });

  Future<void> _noter(double v) async {
    if (_auteur || _occupe) return;
    setState(() => _occupe = true);
    HapticFeedback.mediumImpact();
    try {
      final r = await _sb.rpc('noter_curseur_story', params: {
        'p_story': widget.story.id,
        'p_valeur': (v * 100).round(),
      }) as List;
      if (r.isNotEmpty && mounted) _appliquerCurseur(r.first as Map);
    } catch (_) {
      _info('Oups'.tr, 'Envoi impossible, réessaie'.tr);
    }
    if (mounted) setState(() => _occupe = false);
  }

  /// ❓ Pose-moi une question : la question part en message privé.
  Future<void> _question() async {
    if (_auteur || _occupe) return;
    final champ = TextEditingController();
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: const Color(0xFF1C1C1E),
      title: Text('❓ ${s.valeur}',
          style: const TextStyle(color: Colors.white, fontSize: 17)),
      content: TextField(
        controller: champ,
        autofocus: true,
        maxLength: 300,
        maxLines: 3,
        minLines: 1,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Écris ta question…'.tr,
          hintStyle: const TextStyle(color: Colors.white38),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr)),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Envoyer'.tr)),
      ],
    ));
    final texte = champ.text.trim();
    champ.dispose();
    if (ok != true || texte.isEmpty || !mounted) return;
    setState(() => _occupe = true);
    final envoye = await repondreAStory(
        widget.story, '❓ « ${s.valeur} »\n$texte');
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _envoye = envoye;
    });
    _info(envoye ? '❓' : 'Oups'.tr,
        envoye
            ? 'Envoyé à @prenom ✓'.trParams({'prenom': widget.story.userName})
            : 'Impossible d\'envoyer le message'.tr);
  }

  /// ⏰ Rendez-vous : « Je viens » en message privé.
  Future<void> _rdv() async {
    if (_occupe || _envoye || _auteur) return;
    setState(() => _occupe = true);
    HapticFeedback.mediumImpact();
    final quand = s.options.isNotEmpty ? ' (${s.options.first})' : '';
    final ok = await repondreAStory(
        widget.story, '🙋 ${'Je viens !'.tr} « ${s.valeur}$quand »');
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _envoye = ok;
    });
    _info(ok ? '⏰' : 'Oups'.tr,
        ok
            ? 'Envoyé à @prenom ✓'.trParams({'prenom': widget.story.userName})
            : 'Impossible d\'envoyer le message'.tr);
  }

  Future<void> _voter(int choix) async {
    if (_occupe || _auteur) return;
    setState(() => _occupe = true);
    HapticFeedback.selectionClick();
    try {
      final r = await _sb.rpc('voter_story',
          params: {'p_story': widget.story.id, 'p_choix': choix}) as List;
      if (r.isNotEmpty && mounted) _appliquer(r.first as Map);
    } catch (e) {
      _info('Oups'.tr, 'Vote impossible, réessaie'.tr);
    }
    if (mounted) setState(() => _occupe = false);
  }

  Future<void> _dispo() async {
    if (_occupe || _envoye || _auteur) return;
    setState(() => _occupe = true);
    HapticFeedback.mediumImpact();
    final ok = await repondreAStory(
        widget.story, '🙋 ${'Je suis dispo !'.tr} « ${s.valeur} »');
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _envoye = ok;
    });
    _info(ok ? '🙋' : 'Oups'.tr,
        ok
            ? 'Envoyé à @prenom ✓'.trParams({'prenom': widget.story.userName})
            : 'Impossible d\'envoyer le message'.tr);
  }

  Future<void> _crush() async {
    if (_occupe || _envoye || _auteur) return;
    setState(() => _occupe = true);
    HapticFeedback.mediumImpact();
    String? res;
    String? erreur;
    try {
      res = await _sb.rpc('envoyer_crush_story',
          params: {'p_story': widget.story.id}) as String?;
    } on PostgrestException catch (e) {
      erreur = e.message;
    } catch (_) {
      erreur = '';
    }
    if (!mounted) return;
    setState(() {
      _occupe = false;
      _envoye = res != null;
    });
    if (res == 'reciproque') {
      _info('💘 C\'est réciproque !'.tr,
          'Vous vous plaisez tous les deux : c\'est un match 🎉'.tr);
    } else if (res == 'deja') {
      _info('💘', 'Tu lui as déjà envoyé un crush 🤫'.tr);
    } else if (res != null) {
      _info('💘 Crush envoyé en secret'.tr,
          'Si un jour il y a un like réciproque, vous le saurez tous les deux 😉'
              .tr);
    } else {
      _info('Oups'.tr,
          (erreur ?? '').contains('trop_de_crushs')
              ? 'Tu as envoyé assez de crushs aujourd\'hui 😅'.tr
              : 'Envoi impossible, réessaie'.tr);
    }
  }

  Future<void> _voirVotants() async {
    try {
      final r = await _sb
          .rpc('votants_story', params: {'p_story': widget.story.id}) as List;
      if (!mounted) return;
      Get.bottomSheet(
        Container(
          constraints: BoxConstraints(maxHeight: Get.height * 0.6),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🔥 ${s.valeur}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (r.isEmpty)
              Text('Personne n\'a encore voté'.tr,
                  style: const TextStyle(color: Colors.white70)),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final v in r.cast<Map>())
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white12,
                      backgroundImage: (v['photo_url'] as String?)?.isNotEmpty == true
                          ? NetworkImage(v['photo_url'] as String)
                          : null,
                    ),
                    title: Text('${v['name'] ?? ''}',
                        style: const TextStyle(color: Colors.white)),
                    trailing: Text(
                        s.options.length == 2
                            ? s.options[(v['choix'] as num).toInt().clamp(0, 1)]
                            : '',
                        style: const TextStyle(
                            color: Color(0xFFFF3CAC),
                            fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ]),
        ),
        isScrollControlled: true,
      );
    } catch (_) {}
  }

  Widget _barre(String texte, int votes, int total, bool moi) {
    final part = total == 0 ? 0.0 : votes / total;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      height: 38,
      decoration: BoxDecoration(
          color: const Color(0xFFF1EDFF),
          borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FractionallySizedBox(
          widthFactor: part,
          child: Container(
              color: moi ? const Color(0xFFFFB3E0) : const Color(0xFFD9CCFF)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: Text('${moi ? '✓ ' : ''}$texte',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Color(0xFF3A1A7A),
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ),
            Text('${(part * 100).round()} %',
                style: const TextStyle(
                    color: Color(0xFF3A1A7A), fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }

  Widget? _bas() {
    switch (s.type) {
      case 'dispo':
        if (_auteur) return _note('Les réponses arrivent en message 💬'.tr);
        if (_envoye) return _note('✓ Envoyé'.tr);
        return null; // bouton par défaut
      case 'crush':
        if (_auteur) return _note('Les crushs arrivent en secret 🤫'.tr);
        if (_envoye) return _note('💘 Envoyé en secret'.tr);
        return null;
      case 'question':
        if (_auteur) return _note('Les questions arrivent en message 💬'.tr);
        if (_envoye) return _note('✓ Question envoyée'.tr);
        return null;
      case 'rdv':
        if (_auteur) return _note('Les réponses arrivent en message 💬'.tr);
        if (_envoye) return _note('✓ Envoyé'.tr);
        return null;
      case 'curseur':
        final emoji = s.options.isNotEmpty ? s.options.first : '😍';
        final resultat = (_moyenne != null && (_nombre ?? 0) > 0)
            ? _note('Moyenne : @m % @e · @n note@s'.trParams({
                'm': '$_moyenne',
                'e': emoji,
                'n': '$_nombre',
                's': (_nombre ?? 0) > 1 ? 's' : '',
              }))
            : null;
        if (_auteur) {
          return resultat ?? _note('Personne n\'a encore noté'.tr);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 8,
              activeTrackColor: const Color(0xFFFF3CAC),
              inactiveTrackColor: const Color(0xFFFFD1EC),
              thumbShape: _PouceEmoji(emoji),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: _curseur,
              onChanged: (v) => setState(() => _curseur = v),
              onChangeEnd: _noter,
            ),
          ),
          if (_aNote && resultat != null) resultat,
        ]);
      case 'sondage':
        if (s.options.length != 2) return null;
        final total = _votes0 + _votes1;
        if (_auteur || _monChoix != null) {
          return Column(children: [
            _barre(s.options[0], _votes0, total, _monChoix == 0),
            _barre(s.options[1], _votes1, total, _monChoix == 1),
            if (_auteur)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '@n vote@s · touche pour voir qui'.trParams({
                      'n': '$total',
                      's': total > 1 ? 's' : '',
                    }),
                    style: const TextStyle(color: Colors.black54, fontSize: 11)),
              ),
          ]);
        }
        if (!_resultatsCharges) return null;
        return Column(children: [
          for (var i = 0; i < 2; i++)
            GestureDetector(
              onTap: () => _voter(i),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                    color: const Color(0xFFF1EDFF),
                    borderRadius: BorderRadius.circular(12)),
                child: Text(s.options[i],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF7B2FFF),
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ),
            ),
        ]);
    }
    return null;
  }

  Widget _note(String texte) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: StyleRencontre.de(s.style).texteDoux,
                fontSize: 13,
                fontWeight: FontWeight.w700)),
      );

  @override
  Widget build(BuildContext context) {
    final visuel = Transform.rotate(
      angle: s.rotation,
      child: Transform.scale(
          scale: s.echelle, child: VisuelRencontre(s, bas: _bas())),
    );
    VoidCallback? action;
    switch (s.type) {
      case 'dispo':
        action = _dispo;
      case 'crush':
        action = _crush;
      case 'sondage':
        action = _auteur ? _voirVotants : null; // le vote se fait par bouton
      case 'question':
        action = _question;
      case 'rdv':
        action = _rdv;
    }
    if (action == null) return visuel;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: action,
      child: AnimatedOpacity(
        opacity: _occupe ? 0.6 : 1,
        duration: const Duration(milliseconds: 150),
        child: visuel,
      ),
    );
  }
}

/// Pouce du curseur « Note mon look » : l'émoji choisi par l'auteur.
class _PouceEmoji extends SliderComponentShape {
  final String emoji;
  const _PouceEmoji(this.emoji);

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(36, 36);

  @override
  void paint(PaintingContext context, Offset center,
      {required Animation<double> activationAnimation,
      required Animation<double> enableAnimation,
      required bool isDiscrete,
      required TextPainter labelPainter,
      required RenderBox parentBox,
      required SliderThemeData sliderTheme,
      required TextDirection textDirection,
      required double value,
      required double textScaleFactor,
      required Size sizeWithOverflow}) {
    final taille = 30 + 10 * value; // grossit vers la droite
    final tp = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: taille)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(context.canvas, center - Offset(tp.width / 2, tp.height / 2));
  }
}
