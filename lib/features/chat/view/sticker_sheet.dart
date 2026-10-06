import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rencontre/core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════
//  STICKERS & GIF (GIPHY)
//  Clé gratuite : developers.giphy.com → Create an App → API → copier
//  la clé ici. Sans clé, le panneau affiche « bientôt disponible ».
// ══════════════════════════════════════════════════════════════════

const String cleGiphy = 'rIOkfXwfIZ5ilh0g9tNLu4agvo0eBn6a';

/// Un sticker ou un GIF choisi : [url] = image animée envoyée.
class ChoixGiphy {
  final String url;
  final bool estGif;
  final String? emoji; // onglet Emoji (stories) : l'emoji choisi
  const ChoixGiphy(this.url, this.estGif) : emoji = null;
  const ChoixGiphy.emoji(String e)
      : url = '',
        estGif = false,
        emoji = e;
}

class _ResultatGiphy {
  final String apercu; // petite image pour la grille
  final String url; // image envoyée
  const _ResultatGiphy(this.apercu, this.url);
}

/// Ouvre le panneau et renvoie le sticker / GIF choisi (ou null).
/// [emojis] : liste d'emoji proposée dans un premier onglet « Emoji ».
Future<ChoixGiphy?> choisirSticker(BuildContext context,
    {List<String>? emojis}) {
  return showModalBottomSheet<ChoixGiphy>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _StickerSheet(emojis: emojis),
  );
}

class _StickerSheet extends StatefulWidget {
  final List<String>? emojis;
  const _StickerSheet({this.emojis});

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  final _recherche = TextEditingController();
  Timer? _attente;
  bool _gif = false; // false = stickers, true = GIF
  late bool _emoji = widget.emojis != null; // onglet Emoji actif
  bool _chargement = false;
  bool _erreur = false;
  List<_ResultatGiphy> _resultats = [];
  int _requete = 0;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _attente?.cancel();
    _recherche.dispose();
    super.dispose();
  }

  void _surSaisie(String _) {
    _attente?.cancel();
    _attente = Timer(const Duration(milliseconds: 400), _charger);
  }

  Future<void> _charger() async {
    if (cleGiphy.isEmpty) return;
    final numero = ++_requete;
    setState(() {
      _chargement = true;
      _erreur = false;
    });
    final q = _recherche.text.trim();
    final type = _gif ? 'gifs' : 'stickers';
    final uri = Uri.https('api.giphy.com', '/v1/$type/${q.isEmpty ? 'trending' : 'search'}', {
      'api_key': cleGiphy,
      'limit': '36',
      'rating': 'pg-13',
      if (q.isNotEmpty) 'q': q,
      if (q.isNotEmpty) 'lang': 'fr',
    });
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (numero != _requete || !mounted) return;
      if (res.statusCode != 200) throw Exception('GIPHY ${res.statusCode}');
      final data = (jsonDecode(res.body)['data'] as List?) ?? [];
      final liste = <_ResultatGiphy>[];
      for (final g in data) {
        final images = g['images'] as Map<String, dynamic>? ?? {};
        final apercu = (images['fixed_width_small']?['url'] ??
            images['fixed_width']?['url']) as String?;
        final url = (images['fixed_width']?['url']) as String?;
        if (apercu != null && url != null) liste.add(_ResultatGiphy(apercu, url));
      }
      setState(() {
        _resultats = liste;
        _chargement = false;
      });
    } catch (_) {
      if (numero != _requete || !mounted) return;
      setState(() {
        _chargement = false;
        _erreur = true;
      });
    }
  }

  void _changerOnglet(bool gif) {
    if (gif == _gif && !_emoji) return;
    setState(() {
      _emoji = false;
      _gif = gif;
      _resultats = [];
    });
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final hauteur = MediaQuery.of(context).size.height * 0.6;
    final clavier = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: clavier),
      child: Container(
        height: hauteur,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              if (widget.emojis != null) ...[
                _Onglet(
                    label: 'Emoji',
                    actif: _emoji,
                    onTap: () => setState(() => _emoji = true)),
                const SizedBox(width: 8),
              ],
              _Onglet(
                  label: 'Stickers',
                  actif: !_gif && !_emoji,
                  onTap: () => _changerOnglet(false)),
              const SizedBox(width: 8),
              _Onglet(
                  label: 'GIF',
                  actif: _gif && !_emoji,
                  onTap: () => _changerOnglet(true)),
            ]),
          ),
          const SizedBox(height: 10),
          if (!_emoji)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _recherche,
              onChanged: _surSaisie,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: _gif
                    ? 'Rechercher un GIF (bisou, lol, bonjour…)'
                    : 'Rechercher un sticker (cœur, merci, bonne nuit…)',
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                prefixIcon:
                    Icon(Icons.search_rounded, color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _contenu()),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text('Propulsé par GIPHY',
                style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ),
        ]),
      ),
    );
  }

  Widget _contenu() {
    if (_emoji) {
      final liste = widget.emojis!;
      return GridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: liste.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => Navigator.of(context).pop(ChoixGiphy.emoji(liste[i])),
          child: Center(
              child: Text(liste[i], style: const TextStyle(fontSize: 30))),
        ),
      );
    }
    if (cleGiphy.isEmpty) {
      return _Message('Les stickers arrivent très bientôt 🎨');
    }
    if (_chargement && _resultats.isEmpty) {
      return Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2));
    }
    if (_erreur) {
      return _Message('Impossible de charger. Vérifie ta connexion.');
    }
    if (_resultats.isEmpty) {
      return _Message('Aucun résultat');
    }
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gif ? 3 : 4,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _resultats.length,
      itemBuilder: (_, i) {
        final r = _resultats[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(ChoixGiphy(r.url, _gif)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: r.apercu,
              fit: _gif ? BoxFit.cover : BoxFit.contain,
              placeholder: (_, __) => Container(color: AppColors.surface2),
              errorWidget: (_, __, ___) => Container(color: AppColors.surface2),
            ),
          ),
        );
      },
    );
  }
}

class _Onglet extends StatelessWidget {
  final String label;
  final bool actif;
  final VoidCallback onTap;
  const _Onglet({required this.label, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          gradient: actif ? AppColors.gradientPink : null,
          color: actif ? null : AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: actif ? AppColors.surAccent : AppColors.textPrimary)),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String texte;
  const _Message(this.texte);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(texte,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
      ),
    );
  }
}
