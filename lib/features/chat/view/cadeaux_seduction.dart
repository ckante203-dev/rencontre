import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';

// ══════════════════════════════════════════════════════════════════
//  🎁 CADEAUX (conversation)
//  • Cadeaux de séduction animés (Premium) : un message spécial qui
//    déclenche une animation plein écran chez l'autre (pluie de cœurs…).
//  • Offrir 72 h de Premium (abonnés payants, 1 fois / 30 jours, SQL 099).
//  Le texte du message sert de marqueur : les anciennes versions de l'app
//  l'affichent simplement comme un texte lisible.
// ══════════════════════════════════════════════════════════════════

class CadeauSeduction {
  final String id, emoji, nom, texte;
  final List<Color> couleurs;
  const CadeauSeduction(this.id, this.emoji, this.nom, this.texte, this.couleurs);

  static const tous = [
    CadeauSeduction('coeurs', '💖', 'Pluie de cœurs', '🎁 💖 Pluie de cœurs pour toi',
        [Color(0xFFFF3CAC), Color(0xFFFF7EB3)]),
    CadeauSeduction('rose', '🌹', 'Une rose', '🎁 🌹 Une rose pour toi',
        [Color(0xFFD7263D), Color(0xFFFF5E78)]),
    CadeauSeduction('plais', '🔥', 'Tu me plais', '🎁 🔥 Tu me plais',
        [Color(0xFFFF8A00), Color(0xFFFF3CAC)]),
    CadeauSeduction('bisou', '💋', 'Un bisou', '🎁 💋 Un bisou pour toi',
        [Color(0xFFB0124B), Color(0xFFFF3CAC)]),
    CadeauSeduction('champagne', '🍾', 'Champagne', '🎁 🍾 On trinque ?',
        [Color(0xFFFFC107), Color(0xFFFF8A00)]),
    CadeauSeduction('couronne', '👑', 'Ma reine / mon roi', '🎁 👑 Ma reine / mon roi',
        [Color(0xFF7B2FFF), Color(0xFFFFC107)]),
  ];

  static CadeauSeduction? depuisTexte(String? texte) {
    if (texte == null || !texte.startsWith('🎁 ')) return null;
    for (final c in tous) {
      if (c.texte == texte) return c;
    }
    return null;
  }
}

/// Message posté quand on offre du Premium (marqueur, lisible partout)
const texteCadeauPremium = "🎁 👑 Je t'ai offert 72 h de Premium";

bool estMessageCadeau(String? texte) =>
    texte == texteCadeauPremium || CadeauSeduction.depuisTexte(texte) != null;

// ─── Animation plein écran (emojis qui montent en tourbillonnant) ───

void jouerAnimationCadeau(String emoji) {
  final overlay = Get.key.currentState?.overlay;
  if (overlay == null) return;
  HapticFeedback.mediumImpact();
  late OverlayEntry entree;
  entree = OverlayEntry(
      builder: (_) => _PluieEmojis(emoji: emoji, fin: () => entree.remove()));
  overlay.insert(entree);
}

class _PluieEmojis extends StatefulWidget {
  final String emoji;
  final VoidCallback fin;
  const _PluieEmojis({required this.emoji, required this.fin});
  @override
  State<_PluieEmojis> createState() => _PluieEmojisState();
}

class _PluieEmojisState extends State<_PluieEmojis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800))
    ..forward().whenComplete(widget.fin);
  final _hasard = Random();
  late final List<(double x, double retard, double taille, double balance)>
      _emojis = [
    for (var i = 0; i < 26; i++)
      (
        _hasard.nextDouble(),
        _hasard.nextDouble() * 0.45,
        26 + _hasard.nextDouble() * 30,
        (_hasard.nextDouble() - 0.5) * 60,
      )
  ];

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final taille = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _a,
        builder: (_, __) {
          final t = _a.value;
          return Stack(children: [
            // Grand emoji au centre qui grossit puis s'efface
            Center(
              child: Opacity(
                opacity: (t < 0.15 ? t / 0.15 : (1 - (t - 0.15) / 0.5))
                    .clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + Curves.elasticOut.transform(t.clamp(0.0, 0.6) / 0.6) * 1.2,
                  child: Text(widget.emoji, style: const TextStyle(fontSize: 110)),
                ),
              ),
            ),
            for (final (x, retard, tailleEmoji, balance) in _emojis)
              if (t > retard)
                Builder(builder: (_) {
                  final p = ((t - retard) / (1 - retard)).clamp(0.0, 1.0);
                  return Positioned(
                    left: x * taille.width + sin(p * pi * 3) * balance,
                    top: taille.height * (1.05 - p * 1.2),
                    child: Opacity(
                      opacity: (1 - p).clamp(0.0, 1.0),
                      child: Text(widget.emoji,
                          style: TextStyle(fontSize: tailleEmoji)),
                    ),
                  );
                }),
          ]);
        },
      ),
    );
  }
}

// ─── Bulle d'un message cadeau ───

class BulleCadeau extends StatelessWidget {
  final String texte;
  final bool isMine;
  final String autreNom;
  const BulleCadeau(
      {super.key, required this.texte, required this.isMine, required this.autreNom});

  @override
  Widget build(BuildContext context) {
    final c = CadeauSeduction.depuisTexte(texte);
    final premium = texte == texteCadeauPremium;
    final emoji = premium ? '👑' : (c?.emoji ?? '🎁');
    final couleurs = premium
        ? const [Color(0xFFFFC107), Color(0xFF7B2FFF)]
        : (c?.couleurs ?? const [Color(0xFFFF3CAC), Color(0xFF7B2FFF)]);
    final titre = premium
        ? (isMine
            ? '72 h de Premium offertes à @nom'.trParams({'nom': autreNom})
            : '@nom t\'offre 72 h de Premium'.trParams({'nom': autreNom}))
        : (c?.nom.tr ?? 'Cadeau'.tr);
    final sous = premium
        ? (isMine ? 'Cadeau envoyé 🎁'.tr : 'Profite de tous les avantages 👑'.tr)
        : (isMine ? 'Cadeau envoyé 🎁'.tr : 'Touche pour revoir'.tr);
    return GestureDetector(
      onTap: () async {
        jouerAnimationCadeau(emoji);
        // Premium reçu : le compte se met à jour tout de suite
        if (premium && !isMine && Get.isRegistered<ControleurProfil>()) {
          await Get.find<ControleurProfil>().chargerMonProfil();
        }
      },
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: couleurs,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: couleurs.first.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 38)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre,
                  style: const TextStyle(
                      color: AppColors.surAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(sous,
                  style: TextStyle(
                      color: AppColors.surAccent.withValues(alpha: 0.85),
                      fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ─── Feuille « Cadeaux » (➕ → Cadeau) ───

Future<void> ouvrirCadeaux(ConversationController ctrl) {
  return Get.bottomSheet(_FeuilleCadeaux(ctrl: ctrl),
      isScrollControlled: true, backgroundColor: Colors.transparent);
}

class _FeuilleCadeaux extends StatefulWidget {
  final ConversationController ctrl;
  const _FeuilleCadeaux({required this.ctrl});
  @override
  State<_FeuilleCadeaux> createState() => _FeuilleCadeauxState();
}

class _FeuilleCadeauxState extends State<_FeuilleCadeaux> {
  Map<String, dynamic>? _monCadeau; // abonné ? prochain cadeau ?
  bool _envoi = false;

  String get _prenom => widget.ctrl.conversation.userName.split(' ').first;
  bool get _premium => ControleurProfil.estPremiumMaintenant();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final r = await Supabase.instance.client.rpc('mon_cadeau_premium');
      if (mounted && r is Map) setState(() => _monCadeau = Map.from(r));
    } catch (_) {} // SQL 099 pas encore passé
  }

  DateTime? get _prochain => DateTime.tryParse('${_monCadeau?['prochain'] ?? ''}')?.toLocal();
  bool get _abonne => _monCadeau?['premium'] == true;
  bool get _disponible =>
      _abonne && (_prochain == null || _prochain!.isBefore(DateTime.now()));

  void _paywall() {
    Get.back();
    if (Get.isRegistered<ControleurProfil>()) {
      Get.find<ControleurProfil>().ouvrirPaywall();
    }
  }

  Future<void> _envoyerSeduction(CadeauSeduction c) async {
    if (!_premium) return _paywall();
    if (!widget.ctrl.peutEnvoyer()) return;
    Get.back();
    jouerAnimationCadeau(c.emoji);
    await widget.ctrl.envoyerTexteSpecial(c.texte);
  }

  Future<void> _offrirPremium() async {
    if (!_abonne) return _paywall();
    if (!_disponible || _envoi) return;
    final ok = await Get.dialog<bool>(AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Offrir 72 h de Premium à @nom ?'.trParams({'nom': _prenom}),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      content: Text(
          'Un cadeau tous les 30 jours. @nom profitera de tous les avantages Premium pendant 3 jours.'
              .trParams({'nom': _prenom}),
          style: TextStyle(color: AppColors.textMuted, height: 1.4)),
      actions: [
        TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('Annuler'.tr, style: TextStyle(color: AppColors.textMuted))),
        TextButton(
            onPressed: () => Get.back(result: true),
            child: Text('Offrir 🎁'.tr,
                style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800))),
      ],
    ));
    if (ok != true) return;
    setState(() => _envoi = true);
    String res;
    try {
      res = (await Supabase.instance.client.rpc('offrir_premium',
              params: {'p_a': widget.ctrl.conversation.userId}))
          .toString();
    } catch (_) {
      res = 'erreur';
    }
    if (!mounted) return;
    setState(() => _envoi = false);
    if (res == 'ok') {
      Get.back();
      jouerAnimationCadeau('👑');
      await widget.ctrl.envoyerTexteSpecial(texteCadeauPremium);
      return;
    }
    final message = switch (res) {
      'deja_offert' => 'Tu as déjà offert ton cadeau ce mois-ci'.tr,
      'pas_premium' => 'Réservé aux abonnés Premium'.tr,
      'bloque' => 'Impossible avec cette personne'.tr,
      _ => 'Action impossible, réessaie'.tr,
    };
    Get.snackbar('🎁', message,
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: AppColors.textPrimary);
    _charger();
  }

  @override
  Widget build(BuildContext context) {
    final prochain = _prochain;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            Text('🎁 ${'Séduis @nom'.trParams({'nom': _prenom})}',
                style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
                _premium
                    ? 'Un cadeau animé qui ne passe pas inaperçu'.tr
                    : '👑 Réservé aux membres Premium'.tr,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.95,
              children: [
                for (final c in CadeauSeduction.tous)
                  GestureDetector(
                    onTap: () => _envoyerSeduction(c),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: c.couleurs,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(children: [
                        Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(c.emoji, style: const TextStyle(fontSize: 34)),
                            const SizedBox(height: 4),
                            Text(c.nom.tr,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: AppColors.surAccent,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800)),
                          ]),
                        ),
                        if (!_premium)
                          const Positioned(
                              top: 6,
                              right: 6,
                              child: Icon(Icons.lock_rounded,
                                  size: 14, color: AppColors.surAccent)),
                      ]),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Offrir du Premium ──
            GestureDetector(
              onTap: _offrirPremium,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: _disponible
                          ? const Color(0xFFFFC107)
                          : AppColors.border,
                      width: _disponible ? 1.5 : 1),
                ),
                child: Row(children: [
                  const Text('👑', style: TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Offrir 72 h de Premium'.tr,
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                              !_abonne
                                  ? 'Avec ton abonnement : un cadeau par mois'.tr
                                  : _disponible
                                      ? 'Ton cadeau du mois est disponible 🎁'.tr
                                      : 'Prochain cadeau le @d'.trParams({
                                          'd':
                                              '${prochain!.day.toString().padLeft(2, '0')}/${prochain.month.toString().padLeft(2, '0')}'
                                        }),
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ]),
                  ),
                  _envoi
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.accent))
                      : Icon(
                          _abonne
                              ? Icons.card_giftcard_rounded
                              : Icons.lock_rounded,
                          color: _disponible
                              ? const Color(0xFFFFC107)
                              : AppColors.textMuted),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
