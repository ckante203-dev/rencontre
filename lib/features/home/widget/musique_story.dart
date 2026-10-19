import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// 🎵 Musique des stories (façon Snapchat / TikTok).
///
/// Morceaux libres de droits (Creative Commons BY 4.0, Free Music Archive),
/// raccourcis à 90 s et allégés (96 kbit/s) puis hébergés dans le bucket
/// public Supabase « musiques ». La licence impose de citer l'artiste :
/// étiquette dans le lecteur + écran « Crédits musique ».
class MusiqueStory {
  final String id;
  final String titre;
  final String artiste;
  final String categorie; // afro, romantique, chill, hiphop
  final int dureeS;
  final String page; // page d'origine (crédits)

  const MusiqueStory(this.id, this.titre, this.artiste, this.categorie,
      this.dureeS, this.page);

  String get url =>
      'https://flixcyjefjcyjwvjdiny.supabase.co/storage/v1/object/public/musiques/$id.mp3';

  /// Durée d'un extrait (story photo bouclée, aperçu dans l'éditeur)
  static const extraitS = 15;

  static const _fma = 'https://freemusicarchive.org/music/';
  static const _am = 'Alex Morgan';

  static const tous = <MusiqueStory>[
    // 🔥 Afro / fête
    MusiqueStory('amapiano', 'Hot Amapiano Beats', _am, 'afro', 90,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/hot-amapiano-beats/'),
    MusiqueStory('afrobeat', 'Afrobeat', _am, 'afro', 75,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/afrobeat-1/'),
    MusiqueStory('afro_house', 'Afro House', _am, 'afro', 90,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/afro-house/'),
    MusiqueStory('party', 'Party Music', _am, 'afro', 90,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/party-music/'),
    MusiqueStory('dj', 'DJ Music', _am, 'afro', 90,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/dj-music/'),
    MusiqueStory('traditionnel', 'Traditional Music', _am, 'afro', 90,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/traditional-music/'),
    MusiqueStory('reggae', 'Reggae Island Vibes', _am, 'afro', 90,
        '${_fma}alex-morgan/world-celebration-vol-1/reggae-island-vibes-with-bright-offbeat-skank/'),
    // 💘 Romantique
    MusiqueStory('love_songs', 'Love Songs', _am, 'romantique', 90,
        '${_fma}alex-morgan/love-family-romance/love-songs/'),
    MusiqueStory('romantic', 'Romantic Music', _am, 'romantique', 90,
        '${_fma}alex-morgan/love-family-romance/romantic-music-1/'),
    MusiqueStory('love_music', 'Love Music', _am, 'romantique', 90,
        '${_fma}alex-morgan/love-family-romance/love-music/'),
    MusiqueStory('sexy', 'Sexy Music', _am, 'romantique', 90,
        '${_fma}alex-morgan/love-family-romance/sexy-music/'),
    MusiqueStory('engagement', 'Engagement Songs', _am, 'romantique', 90,
        '${_fma}alex-morgan/love-family-romance/engagement-songs/'),
    MusiqueStory('love_bgm', 'Love BGM', _am, 'romantique', 90,
        '${_fma}alex-morgan/love-family-romance/love-bgm/'),
    MusiqueStory('rnb', 'R&B Slow Jam', _am, 'romantique', 90,
        '${_fma}alex-morgan/world-celebration-vol-1/rb-slow-jam-with-wide-dynamic-groove/'),
    // 😌 Chill
    MusiqueStory('coffee_jelly', 'Coffee Jelly', 'Purrple Cat', 'chill', 90,
        '${_fma}purrple-cat/a-good-book/coffee-jelly/'),
    MusiqueStory('velvet', 'Velvet Horizon', _am, 'chill', 90,
        '${_fma}alex-morgan/chill-lifestyle-vol-1/velvet-horizon-with-dark-smooth-drift/'),
    MusiqueStory('tokyo', 'Tokyo Night Walk', _am, 'chill', 90,
        '${_fma}alex-morgan/chill-lifestyle-vol-1/tokyo-night-walk-with-bright-minor-city-pulse/'),
    MusiqueStory('rainy', 'Rainy Day Coffee', _am, 'chill', 90,
        '${_fma}alex-morgan/world-celebration-vol-1/rainy-day-coffee-with-dark-busy-warmth/'),
    MusiqueStory('soulful', 'Soulful Music', _am, 'chill', 79,
        '${_fma}alex-morgan/pop-afro-party-instrumentals/soulful-music/'),
    // 🎤 Hip-hop
    MusiqueStory('hiphop', 'Hip Hop Beats', _am, 'hiphop', 90,
        '${_fma}alex-morgan/hip-hop-phonk-trap-beats/hip-hop-beats/'),
    MusiqueStory('trap', 'Trap Beat', _am, 'hiphop', 90,
        '${_fma}alex-morgan/hip-hop-phonk-trap-beats/trap-beat/'),
    MusiqueStory('drill', 'Drill Beat', _am, 'hiphop', 90,
        '${_fma}alex-morgan/hip-hop-phonk-trap-beats/drill-beat-1/'),
  ];

  /// « À la une » : la sélection mise en avant
  static const _alaune = [
    'amapiano', 'afro_house', 'sexy', 'rnb', 'afrobeat', 'love_songs',
    'coffee_jelly', 'party', 'velvet', 'hiphop',
  ];

  static MusiqueStory? parId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final m in tous) {
      if (m.id == id) return m;
    }
    return null;
  }

  String get emoji => switch (categorie) {
        'afro' => '🔥',
        'romantique' => '💘',
        'chill' => '😌',
        _ => '🎤',
      };

  List<Color> get couleurs => switch (categorie) {
        'afro' => const [Color(0xFFFF8A00), Color(0xFFFF3CAC)],
        'romantique' => const [Color(0xFFFF3CAC), Color(0xFF7B2FFF)],
        'chill' => const [Color(0xFF00C6FF), Color(0xFF7B2FFF)],
        _ => const [Color(0xFF434343), Color(0xFF7B2FFF)],
      };
}

/// Musique posée sur une story : morceau + début de l'extrait.
class MusiqueChoisie {
  final String id;
  final int debutMs;
  const MusiqueChoisie(this.id, this.debutMs);
  MusiqueStory? get musique => MusiqueStory.parId(id);
}

String _mmss(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

/// Lecteur discret de la musique d'une story. Ne prend PAS le focus audio :
/// le son d'une vidéo continue en même temps (sinon Android la coupe).
class LecteurMusique {
  final AudioPlayer _p = AudioPlayer();
  StreamSubscription<Duration>? _position;
  StreamSubscription<void>? _fin;
  String? _id;
  int _debutMs = 0;
  int _jeton = 0;
  bool _pause = false;

  /// Durée de la boucle (null = le morceau joue jusqu'au bout puis reprend
  /// au début de l'extrait).
  final int? boucleMs;

  LecteurMusique({this.boucleMs}) {
    _p.setAudioContext(AudioContext(
      android: const AudioContextAndroid(audioFocus: AndroidAudioFocus.none),
      iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers}),
    ));
    _p.setReleaseMode(ReleaseMode.stop);
    _position = _p.onPositionChanged.listen((pos) {
      final b = boucleMs;
      if (b != null && pos.inMilliseconds >= _debutMs + b) {
        _p.seek(Duration(milliseconds: _debutMs));
      }
    });
    _fin = _p.onPlayerComplete.listen((_) async {
      if (_id == null || _pause) return;
      await _p.seek(Duration(milliseconds: _debutMs));
      await _p.resume();
    });
  }

  String? get enCours => _id;

  /// Joue [id] à partir de [debutMs] (null = arrête).
  Future<void> jouer(String? id, {int debutMs = 0}) async {
    final jeton = ++_jeton;
    final m = MusiqueStory.parId(id);
    if (m == null) {
      _id = null;
      await _p.stop();
      return;
    }
    _pause = false;
    _debutMs = debutMs;
    try {
      if (_id != m.id) {
        _id = m.id;
        await _p.stop();
        await _p.setSourceUrl(m.url);
      }
      if (jeton != _jeton) return;
      await _p.seek(Duration(milliseconds: debutMs));
      if (jeton != _jeton || _pause) return;
      await _p.resume();
    } catch (e) {
      debugPrint('Musique impossible : $e');
    }
  }

  Future<void> pause() async {
    _pause = true;
    if (_id != null) await _p.pause();
  }

  Future<void> reprendre() async {
    if (_id == null) return;
    _pause = false;
    await _p.resume();
  }

  Future<void> arreter() async {
    _jeton++;
    _id = null;
    await _p.stop();
  }

  void dispose() {
    _jeton++;
    _position?.cancel();
    _fin?.cancel();
    _p.dispose();
  }
}

/// Pastille « 🎵 Titre · Artiste » (lecteur et éditeur). Citer l'artiste
/// fait partie de la licence CC BY.
class EtiquetteMusique extends StatelessWidget {
  final MusiqueStory musique;
  final VoidCallback? onTap;
  final VoidCallback? onRetirer;
  const EtiquetteMusique(
      {super.key, required this.musique, this.onTap, this.onRetirer});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: EdgeInsets.fromLTRB(6, 5, onRetirer == null ? 12 : 4, 5),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: musique.couleurs),
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 15),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text('${musique.titre} · ${musique.artiste}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
          ),
          if (onRetirer != null)
            GestureDetector(
              onTap: onRetirer,
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.close_rounded, color: Colors.white70, size: 18),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Ouvre le choix de musique. Renvoie le morceau + extrait choisis,
/// `MusiqueChoisie('', 0)` pour retirer la musique, null si annulé.
Future<MusiqueChoisie?> ouvrirChoixMusique({MusiqueChoisie? actuelle}) {
  return Get.bottomSheet<MusiqueChoisie>(
    _ChoixMusique(actuelle: actuelle),
    isScrollControlled: true,
    ignoreSafeArea: false,
  );
}

class _ChoixMusique extends StatefulWidget {
  final MusiqueChoisie? actuelle;
  const _ChoixMusique({this.actuelle});
  @override
  State<_ChoixMusique> createState() => _ChoixMusiqueState();
}

class _ChoixMusiqueState extends State<_ChoixMusique> {
  final _lecteur = LecteurMusique(boucleMs: MusiqueStory.extraitS * 1000);
  final _recherche = TextEditingController();
  String _onglet = 'une';
  MusiqueStory? _choisie;
  int _debutS = 0;
  bool _joue = false;

  static const _onglets = [
    ('une', 'À la une'),
    ('afro', '🔥 Afro'),
    ('romantique', '💘 Romantique'),
    ('chill', '😌 Chill'),
    ('hiphop', '🎤 Hip-hop'),
  ];

  @override
  void initState() {
    super.initState();
    final a = widget.actuelle;
    if (a != null && a.musique != null) {
      _choisie = a.musique;
      _debutS = a.debutMs ~/ 1000;
    }
  }

  @override
  void dispose() {
    _lecteur.dispose();
    _recherche.dispose();
    super.dispose();
  }

  List<MusiqueStory> get _liste {
    final q = _recherche.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      return MusiqueStory.tous
          .where((m) =>
              m.titre.toLowerCase().contains(q) ||
              m.artiste.toLowerCase().contains(q) ||
              m.categorie.contains(q))
          .toList();
    }
    if (_onglet == 'une') {
      return [for (final id in MusiqueStory._alaune) MusiqueStory.parId(id)!];
    }
    return MusiqueStory.tous.where((m) => m.categorie == _onglet).toList();
  }

  int get _maxDebut =>
      (_choisie!.dureeS - MusiqueStory.extraitS).clamp(0, 9999);

  void _toucher(MusiqueStory m) {
    HapticFeedback.selectionClick();
    if (_choisie?.id == m.id) {
      // même morceau : lecture / pause
      if (_joue) {
        _lecteur.pause();
      } else {
        _lecteur.jouer(m.id, debutMs: _debutS * 1000);
      }
      setState(() => _joue = !_joue);
      return;
    }
    setState(() {
      _choisie = m;
      _debutS = 0;
      _joue = true;
    });
    _lecteur.jouer(m.id);
  }

  @override
  Widget build(BuildContext context) {
    final liste = _liste;
    return Container(
      height: Get.height * 0.86,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(children: [
              Expanded(
                child: Text('🎵 ${'Musique'.tr}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900)),
              ),
              IconButton(
                tooltip: 'Crédits musique'.tr,
                onPressed: () => Get.to(() => const EcranCreditsMusique()),
                icon: const Icon(Icons.info_outline_rounded,
                    color: Colors.white54),
              ),
            ]),
          ),
          // Recherche
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _recherche,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Rechercher un son'.tr,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
          // Onglets
          if (_recherche.text.trim().isEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                children: [
                  for (final (id, nom) in _onglets)
                    GestureDetector(
                      onTap: () => setState(() => _onglet = id),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _onglet == id ? Colors.white : Colors.white10,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(nom.tr,
                            style: TextStyle(
                                color:
                                    _onglet == id ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ),
                    ),
                ],
              ),
            )
          else
            const SizedBox(height: 10),
          // Morceaux
          Expanded(
            child: liste.isEmpty
                ? Center(
                    child: Text('Aucun son trouvé'.tr,
                        style: const TextStyle(color: Colors.white54)))
                : ListView.builder(
                    itemCount: liste.length,
                    itemBuilder: (_, i) => _ligne(liste[i]),
                  ),
          ),
          if (_choisie != null) _panneauExtrait(),
          if (_choisie == null && widget.actuelle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: TextButton.icon(
                onPressed: () => Get.back(result: const MusiqueChoisie('', 0)),
                icon: const Icon(Icons.music_off_rounded, color: Colors.white70),
                label: Text('Retirer la musique'.tr,
                    style: const TextStyle(color: Colors.white70)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _ligne(MusiqueStory m) {
    final choisie = _choisie?.id == m.id;
    return InkWell(
      onTap: () => _toucher(m),
      child: Container(
        color: choisie ? Colors.white.withValues(alpha: 0.07) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                  colors: m.couleurs,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: choisie && _joue
                ? const Icon(Icons.graphic_eq_rounded,
                    color: Colors.white, size: 28)
                : Text(m.emoji, style: const TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${m.artiste} · ${_mmss(m.dureeS)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
            ]),
          ),
          Icon(
              choisie && _joue
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: choisie ? const Color(0xFFFF3CAC) : Colors.white38,
              size: 32),
        ]),
      ),
    );
  }

  /// Bas de l'écran : caler l'extrait de 15 s puis valider.
  Widget _panneauExtrait() {
    final m = _choisie!;
    final max = _maxDebut;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Color(0xFF2C2C2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(
            child: Text('${m.emoji}  ${m.titre}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          Text(
              '${_mmss(_debutS)} – ${_mmss((_debutS + MusiqueStory.extraitS).clamp(0, m.dureeS))}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        ]),
        if (max > 0) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Glisse pour caler ton extrait de 15 s'.tr,
                style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 22,
              activeTrackColor: const Color(0xFFFF3CAC),
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              trackShape: const RoundedRectSliderTrackShape(),
            ),
            child: Slider(
              value: _debutS.clamp(0, max).toDouble(),
              min: 0,
              max: max.toDouble(),
              onChanged: (v) => setState(() => _debutS = v.round()),
              onChangeEnd: (v) {
                setState(() => _joue = true);
                _lecteur.jouer(m.id, debutMs: v.round() * 1000);
              },
            ),
          ),
        ],
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => Get.back(result: MusiqueChoisie(m.id, _debutS * 1000)),
          child: Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]),
              borderRadius: BorderRadius.circular(25),
            ),
            child: Text('Ajouter à ma story ✓'.tr,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900)),
          ),
        ),
        if (widget.actuelle != null)
          TextButton(
            onPressed: () => Get.back(result: const MusiqueChoisie('', 0)),
            child: Text('Retirer la musique'.tr,
                style: const TextStyle(color: Colors.white54)),
          ),
      ]),
    );
  }
}

/// Crédits exigés par la licence Creative Commons BY 4.0.
class EcranCreditsMusique extends StatelessWidget {
  const EcranCreditsMusique({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1C1C1E),
        foregroundColor: Colors.white,
        title: Text('Crédits musique'.tr),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
              'Musiques sous licence Creative Commons Attribution 4.0 (CC BY 4.0), '
                      'issues de Free Music Archive (freemusicarchive.org). '
                      'Modifications : extraits raccourcis à 90 s et réencodés.'
                  .tr,
              style: const TextStyle(color: Colors.white70, height: 1.4)),
          const SizedBox(height: 4),
          const SelectableText(
              'https://creativecommons.org/licenses/by/4.0/',
              style: TextStyle(color: Color(0xFFFF3CAC), fontSize: 12.5)),
          const SizedBox(height: 14),
          for (final m in MusiqueStory.tous)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m.emoji} « ${m.titre} » — ${m.artiste}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                SelectableText(m.page,
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 11.5)),
              ]),
            ),
        ],
      ),
    );
  }
}
