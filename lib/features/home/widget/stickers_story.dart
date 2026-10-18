import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// ─── STICKERS, EMOJI ET GIF SUR LES STORIES ───────────────────────
// Posés par l'auteur dans l'éditeur (glisser, pincer pour agrandir et
// tourner, glisser sur la corbeille pour supprimer), enregistrés dans
// stories.stickers (jsonb) et affichés par-dessus la photo / vidéo :
// les GIF restent animés, même sur une vidéo.

/// Stickers de rencontre (SQL 086), interactifs dans le lecteur :
/// 'lieu' (ma ville), 'dispo' (« Dispo ce soir ? »), 'crush' (crush
/// anonyme), 'sondage' (Vibe check, 2 choix dans [options]).
const typesStickersRencontre = {'lieu', 'dispo', 'crush', 'sondage'};

class StickerStory {
  /// 'emoji' (valeur = l'emoji), 'giphy' (valeur = URL GIPHY),
  /// 'texte' (valeur = le texte, avec gras / couleur / fond) ou un
  /// sticker de rencontre ([typesStickersRencontre]).
  final String type;
  final String valeur;
  final double x, y; // centre, en fraction de l'écran (0–1)
  final double echelle;
  final double rotation; // radians
  // Textes uniquement
  final bool gras;
  final int couleur; // ARGB
  final int fond; // 0 = aucun, 1 = bulle noire, 2 = bulle de la couleur
  // Sondage : les 2 réponses possibles
  final List<String> options;

  const StickerStory({
    required this.type,
    required this.valeur,
    this.x = 0.5,
    this.y = 0.4,
    this.echelle = 1,
    this.rotation = 0,
    this.gras = true,
    this.couleur = 0xFFFFFFFF,
    this.fond = 1,
    this.options = const [],
  });

  bool get estEmoji => type == 'emoji';
  bool get estRencontre => typesStickersRencontre.contains(type);
  bool get estTexte => type == 'texte';

  StickerStory copyWith({
    String? valeur,
    double? x,
    double? y,
    double? echelle,
    double? rotation,
    bool? gras,
    int? couleur,
    int? fond,
  }) =>
      StickerStory(
        type: type,
        options: options,
        valeur: valeur ?? this.valeur,
        x: x ?? this.x,
        y: y ?? this.y,
        echelle: echelle ?? this.echelle,
        rotation: rotation ?? this.rotation,
        gras: gras ?? this.gras,
        couleur: couleur ?? this.couleur,
        fond: fond ?? this.fond,
      );

  Map<String, dynamic> toJson() => {
        't': type,
        'v': valeur,
        'x': double.parse(x.toStringAsFixed(4)),
        'y': double.parse(y.toStringAsFixed(4)),
        'e': double.parse(echelle.toStringAsFixed(3)),
        'r': double.parse(rotation.toStringAsFixed(3)),
        if (estTexte) ...{'g': gras, 'c': couleur, 'f': fond},
        if (options.isNotEmpty) 'o': options,
      };

  static StickerStory? fromJson(dynamic j) {
    if (j is! Map) return null;
    final t = j['t'], v = j['v'];
    if (t is! String || v is! String || v.trim().isEmpty) return null;
    if (t != 'emoji' && t != 'giphy' && t != 'texte' &&
        !typesStickersRencontre.contains(t)) {
      return null;
    }
    // Sondage : exactement 2 réponses courtes
    final o = j['o'];
    final options = o is List
        ? o.whereType<String>()
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .map((x) => x.length > 25 ? x.substring(0, 25) : x)
            .take(2)
            .toList()
        : <String>[];
    if (t == 'sondage' && options.length != 2) return null;
    // Les GIF ne viennent que de GIPHY (pas d'image arbitraire)
    if (t == 'giphy' && !estUrlGiphy(v)) return null;
    double n(Object? o, double d) => (o is num) ? o.toDouble() : d;
    final c = j['c'], f = j['f'];
    return StickerStory(
      type: t,
      valeur: (t == 'texte' && v.length > 200)
          ? v.substring(0, 200)
          : (typesStickersRencontre.contains(t) && v.length > 80)
              ? v.substring(0, 80)
              : v,
      options: options,
      x: n(j['x'], 0.5).clamp(0.0, 1.0),
      y: n(j['y'], 0.5).clamp(0.0, 1.0),
      echelle: n(j['e'], 1).clamp(0.3, 4.0),
      rotation: n(j['r'], 0),
      gras: j['g'] != false,
      couleur: c is int ? c : 0xFFFFFFFF,
      fond: f is int ? f.clamp(0, 2) : 1,
    );
  }

  static List<StickerStory> listeDepuis(dynamic brut) {
    if (brut is! List) return const [];
    return brut.map(fromJson).whereType<StickerStory>().take(20).toList();
  }
}

bool estUrlGiphy(String url) =>
    RegExp(r'^https://media\d*\.giphy\.com/').hasMatch(url);

/// Couleurs proposées pour les textes.
const couleursTexteStory = [
  0xFFFFFFFF, 0xFF000000, 0xFFFFD60A, 0xFFFF3B30, 0xFFFF3CAC,
  0xFF7B2FFF, 0xFF0A84FF, 0xFF30D158, 0xFFFF9F0A,
];

/// Texte de story (même rendu dans l'éditeur et le lecteur).
class VisuelTexte extends StatelessWidget {
  final String texte;
  final bool gras;
  final int couleur;
  final int fond;
  const VisuelTexte(
      {super.key,
      required this.texte,
      required this.gras,
      required this.couleur,
      required this.fond});

  @override
  Widget build(BuildContext context) {
    final c = Color(couleur);
    // Bulle colorée : texte noir ou blanc selon la clarté de la couleur
    final clair = c.computeLuminance() > 0.5;
    final couleurTexte = fond == 2 ? (clair ? Colors.black : Colors.white) : c;
    final Color? couleurFond = switch (fond) {
      1 => Colors.black.withValues(alpha: 0.6),
      2 => c,
      _ => null,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: couleurFond == null
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: couleurFond == null
            ? null
            : BoxDecoration(
                color: couleurFond, borderRadius: BorderRadius.circular(10)),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: couleurTexte,
            fontSize: 24,
            height: 1.2,
            fontWeight: gras ? FontWeight.w900 : FontWeight.w500,
            shadows: couleurFond == null
                ? const [Shadow(blurRadius: 6, color: Colors.black54)]
                : null,
          ),
        ),
      ),
    );
  }
}

/// Le sticker lui-même (taille de base 110 px × échelle).
class VisuelSticker extends StatelessWidget {
  final StickerStory s;
  const VisuelSticker(this.s, {super.key});

  @override
  Widget build(BuildContext context) {
    if (s.estTexte) {
      // Le texte garde sa mise en page et est agrandi d'un bloc
      return Transform.rotate(
        angle: s.rotation,
        child: Transform.scale(
          scale: s.echelle,
          child: VisuelTexte(
              texte: s.valeur,
              gras: s.gras,
              couleur: s.couleur,
              fond: s.fond),
        ),
      );
    }
    if (s.estRencontre) {
      return Transform.rotate(
        angle: s.rotation,
        child: Transform.scale(scale: s.echelle, child: VisuelRencontre(s)),
      );
    }
    final taille = 110 * s.echelle;
    return Transform.rotate(
      angle: s.rotation,
      child: s.estEmoji
          ? Text(s.valeur,
              style: TextStyle(fontSize: taille * 0.72, height: 1.1))
          : SizedBox(
              width: taille,
              height: taille,
              child: CachedNetworkImage(
                imageUrl: s.valeur,
                fit: BoxFit.contain,
                placeholder: (_, __) => const SizedBox(),
                errorWidget: (_, __, ___) => const SizedBox(),
                memCacheWidth: 1080,
              ),
            ),
    );
  }
}

/// Lecteur : tous les stickers d'une story, à mettre dans un Stack plein
/// écran (même repère que LegendePlacee).
class CoucheStickers extends StatelessWidget {
  final List<StickerStory> stickers;

  /// Lecteur : stickers de rencontre touchables (dispo, crush, sondage).
  /// Sans lui, tout est décoratif.
  final Widget Function(StickerStory s)? interactif;
  const CoucheStickers(this.stickers, {super.key, this.interactif});

  @override
  Widget build(BuildContext context) {
    if (stickers.isEmpty) return const SizedBox.shrink();
    final inter = interactif;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (_, box) => Stack(children: [
          for (final s in stickers)
            Positioned(
              left: s.x * box.maxWidth,
              top: s.y * box.maxHeight,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                // Seuls les stickers de rencontre captent le toucher : le
                // reste laisse passer le balayage / l'avance du lecteur
                child: (inter != null && s.estRencontre)
                    ? inter(s)
                    : IgnorePointer(child: VisuelSticker(s)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Éditeur : un sticker qu'on déplace (1 doigt), agrandit et tourne
/// (2 doigts). [onBouge] signale le début / la fin du geste et la
/// position du doigt (pour la corbeille).
class StickerEditable extends StatefulWidget {
  final StickerStory sticker;
  final Size zone;
  final ValueChanged<StickerStory> onChange;
  final void Function(bool enCours, Offset? doigt) onBouge;
  final VoidCallback? onTap; // texte : le modifier

  const StickerEditable({
    super.key,
    required this.sticker,
    required this.zone,
    required this.onChange,
    required this.onBouge,
    this.onTap,
  });

  @override
  State<StickerEditable> createState() => _StickerEditableState();
}

class _StickerEditableState extends State<StickerEditable> {
  double _echelleDepart = 1, _rotationDepart = 0;
  bool _enGeste = false;

  @override
  void dispose() {
    // Widget retiré en plein geste : on prévient l'éditeur après la frame
    // (sinon la corbeille resterait affichée)
    if (_enGeste) {
      final fin = widget.onBouge;
      WidgetsBinding.instance.addPostFrameCallback((_) => fin(false, null));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sticker;
    final z = widget.zone;
    return Positioned(
      left: s.x * z.width,
      top: s.y * z.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onTap,
          onScaleStart: (d) {
            _enGeste = true;
            _echelleDepart = s.echelle;
            _rotationDepart = s.rotation;
            widget.onBouge(true, d.focalPoint);
          },
          onScaleUpdate: (d) {
            final cur = widget.sticker;
            widget.onChange(cur.copyWith(
              x: (cur.x + d.focalPointDelta.dx / z.width).clamp(0.0, 1.0),
              y: (cur.y + d.focalPointDelta.dy / z.height).clamp(0.0, 1.0),
              echelle: d.pointerCount >= 2
                  ? (_echelleDepart * d.scale).clamp(0.3, 4.0)
                  : cur.echelle,
              rotation: d.pointerCount >= 2
                  ? _rotationDepart + d.rotation
                  : cur.rotation,
            ));
            widget.onBouge(true, d.focalPoint);
          },
          onScaleEnd: (_) {
            _enGeste = false;
            widget.onBouge(false, null);
          },
          child: Padding(
            padding: const EdgeInsets.all(8), // zone de prise plus large
            child: VisuelSticker(s),
          ),
        ),
      ),
    );
  }
}

/// Corbeille affichée en bas pendant qu'on déplace un sticker.
class CorbeilleSticker extends StatelessWidget {
  final bool survolee;
  const CorbeilleSticker({super.key, required this.survolee});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: survolee ? 68 : 54,
      height: survolee ? 68 : 54,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: survolee ? Colors.red : Colors.black54,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Icon(Icons.delete_rounded,
          color: Colors.white, size: survolee ? 32 : 26),
    );
  }
}

/// Emoji proposés dans l'onglet « Emoji » du panneau.
/// Sticker « heure » ou « date » : texte du moment de la publication.
String? texteStickerMoment(String emoji) {
  final m = DateTime.now();
  String deux(int n) => n.toString().padLeft(2, '0');
  if (emoji == '⏰') return '⏰ ${deux(m.hour)}:${deux(m.minute)}';
  if (emoji == '📆') {
    const jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    const mois = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet',
      'août', 'septembre', 'octobre', 'novembre', 'décembre'];
    return '📆 ${jours[m.weekday - 1].tr} ${m.day} ${mois[m.month - 1].tr}';
  }
  return null;
}

/// ⏰ et 📆 en tête : ils posent l'heure / la date du jour en texte.
const emojiStory = [
  '⏰', '📆',
  '😂', '😍', '🥰', '😘', '😎', '🤩', '🥳', '😭', '😱', '🤔',
  '😏', '😴', '🙄', '😇', '🤪', '😅', '🔥', '❤️', '💔', '💯',
  '✨', '⭐', '🌙', '☀️', '🌈', '🎉', '🎂', '🎁', '🎶', '💃',
  '🕺', '🍻', '🥂', '☕', '🍕', '🍔', '🍟', '🍗', '🍫', '🍓',
  '👍', '👏', '🙏', '💪', '🤝', '✌️', '👀', '💋', '💦', '👑',
  '💎', '💸', '📍', '🏖️', '✈️', '🚗', '⚽', '🏀', '🎮', '📸',
  '🇨🇮', '🌴', '🐶', '🐱', '🦁', '🌹', '🌸', '🍀', '🤍', '🖤',
];

/// Saisie d'un texte de story façon Snap : gras, fond, couleur.
/// Toucher en dehors du texte ou « OK » valide.
class EditeurTexteStory extends StatefulWidget {
  final StickerStory? initial;
  final void Function(String texte, bool gras, int couleur, int fond)
      onValider;
  const EditeurTexteStory({super.key, this.initial, required this.onValider});

  @override
  State<EditeurTexteStory> createState() => _EditeurTexteStoryState();
}

class _EditeurTexteStoryState extends State<EditeurTexteStory> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial?.valeur ?? '');
  late bool _gras = widget.initial?.gras ?? true;
  late int _couleur = widget.initial?.couleur ?? 0xFFFFFFFF;
  late int _fond = widget.initial?.fond ?? 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _valider() =>
      widget.onValider(_ctrl.text.trim(), _gras, _couleur, _fond);

  Widget _outil(Widget child, bool actif, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: actif ? Colors.white : Colors.black45,
            border: Border.all(color: Colors.white54),
          ),
          child: Center(child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      child: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _valider, // toucher à côté = terminé
          child: Column(children: [
            // ── Outils : gras, fond, OK ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                _outil(
                    Text('B',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: _gras ? Colors.black : Colors.white)),
                    _gras,
                    () => setState(() => _gras = !_gras)),
                const SizedBox(width: 10),
                _outil(
                    Icon(
                        _fond == 0
                            ? Icons.format_color_text_rounded
                            : Icons.format_color_fill_rounded,
                        size: 20,
                        color: _fond != 0 ? Colors.black : Colors.white),
                    _fond != 0,
                    () => setState(() => _fond = (_fond + 1) % 3)),
                const Spacer(),
                GestureDetector(
                  onTap: _valider,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Text('OK',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                            fontSize: 14)),
                  ),
                ),
              ]),
            ),
            // ── Le texte, au centre, avec son style ──
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: () {}, // toucher le texte ne valide pas
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(minWidth: 80, maxWidth: 300),
                    child: Stack(alignment: Alignment.center, children: [
                      // Rendu final, sous le champ de saisie transparent
                      IgnorePointer(
                        child: VisuelTexte(
                            texte: _ctrl.text.isEmpty ? ' ' : _ctrl.text,
                            gras: _gras,
                            couleur: _couleur,
                            fond: _fond),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: _fond == 0
                              ? EdgeInsets.zero
                              : const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                          child: TextField(
                            controller: _ctrl,
                            autofocus: true,
                            maxLines: null,
                            maxLength: 200,
                            textAlign: TextAlign.center,
                            cursorColor: Colors.white,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                                color: Colors.transparent,
                                fontSize: 24,
                                height: 1.2,
                                fontWeight: _gras
                                    ? FontWeight.w900
                                    : FontWeight.w500),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isCollapsed: true,
                              counterText: '',
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            // ── Couleurs ──
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  for (final c in couleursTexteStory)
                    GestureDetector(
                      onTap: () => setState(() => _couleur = c),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: _couleur == c ? 34 : 28,
                        height: _couleur == c ? 34 : 28,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white,
                              width: _couleur == c ? 3 : 1.5),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}


/// Apparence d'un sticker de rencontre. [enfant] remplace la partie basse
/// (boutons du sondage, résultats…) dans le lecteur.
class VisuelRencontre extends StatelessWidget {
  final StickerStory s;
  final Widget? bas;
  const VisuelRencontre(this.s, {super.key, this.bas});

  static const _degradeZamu =
      LinearGradient(colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]);

  Widget _carte({required Widget child, Gradient? degrade, Color? fond}) =>
      Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: degrade,
          color: fond,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black38)],
        ),
        child: child,
      );

  Widget _bouton(String texte, {Color fond = Colors.white, Color couleur = const Color(0xFF7B2FFF)}) =>
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
        decoration: BoxDecoration(
            color: fond, borderRadius: BorderRadius.circular(12)),
        child: Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: couleur, fontSize: 14, fontWeight: FontWeight.w800)),
      );

  @override
  Widget build(BuildContext context) {
    switch (s.type) {
      case 'lieu':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: _degradeZamu,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black38)],
          ),
          child: Text('📍 ${s.valeur}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.3)),
        );
      case 'dispo':
        return _carte(
          fond: Colors.white,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🙋 ${s.valeur}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            bas ??
                _bouton('Je suis dispo !'.tr,
                    fond: const Color(0xFF7B2FFF), couleur: Colors.white),
          ]),
        );
      case 'crush':
        return _carte(
          degrade: _degradeZamu,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('💘 ${s.valeur}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Personne ne saura que c\'est toi 🤫'.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
            bas ?? _bouton('J\'ai un crush 💘'.tr),
          ]),
        );
      case 'sondage':
        return _carte(
          fond: Colors.white,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('🔥 ${s.valeur}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 17,
                    fontWeight: FontWeight.w900)),
            bas ??
                Column(children: [
                  for (final o in s.options)
                    _bouton(o, fond: const Color(0xFFF1EDFF)),
                ]),
          ]),
        );
    }
    return const SizedBox.shrink();
  }
}
