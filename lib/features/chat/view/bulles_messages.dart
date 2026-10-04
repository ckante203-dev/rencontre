import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';

// ─── BULLES DE MESSAGES (Accueil) ─────────────────────────────────
// Quand de NOUVEAUX messages non lus arrivent, la photo des personnes qui
// ont écrit monte depuis l'icône Messages, comme les cœurs d'un live
// (5 maximum, ~3 s). Toucher une bulle ouvre la conversation.
// Jamais deux fois pour les mêmes messages ; seulement sur l'Accueil.

class BullesMessages extends StatefulWidget {
  const BullesMessages({super.key});

  @override
  State<BullesMessages> createState() => _BullesMessagesState();
}

class _BullesMessagesState extends State<BullesMessages>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _cle = 'bulles_messages_vues';
  static const _dureeBulle = 3200; // ms
  static const _decalage = 280; // ms entre deux bulles

  late final AnimationController _anim = AnimationController(vsync: this);
  final _box = GetStorage();
  final _alea = Random();
  List<ConversationModel> _bulles = [];
  List<double> _balancement = [];
  final List<Worker> _ecouteurs = [];
  Timer? _attente;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _bulles = []);
      }
    });
    if (Get.isRegistered<ChatListController>()) {
      final chat = Get.find<ChatListController>();
      _ecouteurs.add(ever(chat.conversations, (_) => _bientot()));
      _ecouteurs.add(ever(chat.isLoading, (_) => _bientot()));
    }
    if (Get.isRegistered<NavigationController>()) {
      _ecouteurs.add(ever(Get.find<NavigationController>().currentIndex,
          (_) => _bientot(const Duration(milliseconds: 500))));
    }
    _bientot(const Duration(seconds: 2));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final w in _ecouteurs) {
      w.dispose();
    }
    _attente?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Retour dans l'app : les conversations se rafraîchissent d'abord
    if (state == AppLifecycleState.resumed) {
      _bientot(const Duration(milliseconds: 1800));
    }
  }

  void _bientot([Duration d = const Duration(milliseconds: 900)]) {
    _attente?.cancel();
    _attente = Timer(d, _verifier);
  }

  void _verifier() {
    if (!mounted || _anim.isAnimating) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations == true) return;
    if (!Get.isRegistered<ChatListController>()) return;
    final chat = Get.find<ChatListController>();
    if (chat.isLoading.value) return;
    if (Get.isRegistered<NavigationController>() &&
        Get.find<NavigationController>().currentIndex.value !=
            NavigationController.accueilIndex) {
      return;
    }
    // Un écran ouvert par-dessus (profil, conversation…) : plus tard
    if (Get.currentRoute != '/main' && Get.currentRoute != '/') return;

    final vues = List<String>.from(_box.read<List>(_cle) ?? const []);
    String cle(ConversationModel c) =>
        '${c.id}@${c.lastActivity?.millisecondsSinceEpoch ?? 0}';
    final nouvelles = chat.conversations
        .where((c) =>
            c.unreadCount > 0 &&
            !chat.sourdineIds.contains(c.id) &&
            !vues.contains(cle(c)))
        .toList()
      ..sort((a, b) => (b.lastActivity ?? DateTime(0))
          .compareTo(a.lastActivity ?? DateTime(0)));
    if (nouvelles.isEmpty) return;

    final choix = nouvelles.take(5).toList();
    // Mémorisées tout de suite : jamais deux fois pour les mêmes messages
    vues.addAll(nouvelles.map(cle));
    _box.write(_cle, vues.length > 200 ? vues.sublist(vues.length - 200) : vues);

    setState(() {
      _bulles = choix;
      _balancement = [for (final _ in choix) _alea.nextDouble() * pi * 2];
    });
    _anim.duration =
        Duration(milliseconds: _dureeBulle + _decalage * (choix.length - 1));
    _anim.forward(from: 0);
  }

  void _ouvrir(ConversationModel c) {
    _anim.stop();
    setState(() => _bulles = []);
    Get.toNamed('/chat/conversation', arguments: c);
  }

  @override
  Widget build(BuildContext context) {
    if (_bulles.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (_, box) {
      // Départ : l'icône Messages (2e des 5 onglets), en bas de l'écran
      final departX = box.maxWidth * 1.5 / 5;
      final departY = box.maxHeight - 8;
      final montee = box.maxHeight * 0.55;
      final total = _anim.duration?.inMilliseconds ?? _dureeBulle;
      return AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Stack(children: [
          for (var i = 0; i < _bulles.length; i++)
            _bulle(i, _anim.value * total, departX, departY, montee),
        ]),
      );
    });
  }

  Widget _bulle(int i, double ms, double x0, double y0, double montee) {
    final t = ((ms - i * _decalage) / _dureeBulle).clamp(0.0, 1.0);
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final c = _bulles[i];
    // Montée qui ralentit, léger balancement, écartement progressif
    final monteeT = Curves.easeOutCubic.transform(t);
    final ecart = (i - (_bulles.length - 1) / 2) * 34 * monteeT;
    final x = x0 + ecart + sin(t * pi * 2.4 + _balancement[i]) * 22 * t;
    final y = y0 - monteeT * montee;
    final opacite = t < 0.08
        ? t / 0.08
        : t > 0.72
            ? (1 - t) / 0.28
            : 1.0;
    final echelle = t < 0.15 ? 0.4 + 0.6 * Curves.easeOutBack.transform(t / 0.15) : 1.0;
    const taille = 56.0;
    return Positioned(
      left: x - taille / 2,
      top: y - taille,
      child: Opacity(
        opacity: opacite.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: echelle,
          child: GestureDetector(
            onTap: () => _ouvrir(c),
            child: _Avatar(conv: c, taille: taille),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final ConversationModel conv;
  final double taille;
  const _Avatar({required this.conv, required this.taille});

  @override
  Widget build(BuildContext context) {
    final photo = conv.userPhotoUrl ?? '';
    return SizedBox(
      width: taille + 10,
      height: taille + 10,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: taille,
          height: taille,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.gradientPink,
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
            ],
          ),
          child: CircleAvatar(
            backgroundColor: AppColors.surface2,
            backgroundImage:
                photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
            onBackgroundImageError: photo.isNotEmpty ? (_, __) {} : null,
            child: photo.isEmpty
                ? Text(
                    conv.userName.isEmpty
                        ? '?'
                        : conv.userName[0].toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800))
                : null,
          ),
        ),
        // Bulle 💬 avec le nombre de messages
        Positioned(
          right: 2,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.accent, width: 1.5),
            ),
            child: Text(
                '💬 ${conv.unreadCount > 9 ? '9+' : conv.unreadCount}',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent)),
          ),
        ),
      ]),
    );
  }
}
