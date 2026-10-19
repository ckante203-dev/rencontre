import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════
//  ⭐ ZAMU STAR (SQL 100) : statut public sur demande, validé par Zamu.
//  Critères calculés par le serveur ; avantages : badge ⭐ et stories en
//  tête de Découvrir.
// ══════════════════════════════════════════════════════════════════

/// Badge ⭐ doré (à côté du nom)
class BadgeStar extends StatelessWidget {
  final double size;
  const BadgeStar({super.key, this.size = 16});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFF9800)]),
      ),
      child: Icon(Icons.star_rounded, size: size * 0.78, color: Colors.white),
    );
  }
}

const _categories = [
  ('artiste', '🎤', 'Artiste / DJ'),
  ('createur', '📸', 'Créateur·rice'),
  ('lieu', '🍸', 'Lieu (maquis, bar, club)'),
  ('personnalite', '✨', 'Personnalité'),
];

/// Écran « Devenir Zamu Star » : critères, demande, état
class EcranZamuStar extends StatefulWidget {
  const EcranZamuStar({super.key});
  @override
  State<EcranZamuStar> createState() => _EcranZamuStarState();
}

class _EcranZamuStarState extends State<EcranZamuStar> {
  Map<String, dynamic>? _c; // critères + situation
  bool _chargement = true;
  bool _envoi = false;
  String _categorie = 'artiste';
  bool _accepte = false;
  final _presentation = TextEditingController();
  final _lien = TextEditingController();

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _presentation.dispose();
    _lien.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      final r = await Supabase.instance.client.rpc('criteres_star');
      if (mounted && r is Map) setState(() => _c = Map<String, dynamic>.from(r));
    } catch (e) {
      debugPrint('criteres_star : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _info(String t) => Get.snackbar('⭐', t,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary);

  Future<void> _envoyer() async {
    if (_envoi) return;
    if (_presentation.text.trim().length < 10) {
      _info('Présente-toi en quelques mots (10 caractères minimum)'.tr);
      return;
    }
    if (!_accepte) {
      _info('Coche la case pour accepter que tes stories soient publiques'.tr);
      return;
    }
    setState(() => _envoi = true);
    String res;
    try {
      res = (await Supabase.instance.client.rpc('demander_star', params: {
        'p_categorie': _categorie,
        'p_presentation': _presentation.text.trim(),
        'p_lien': _lien.text.trim(),
      }))
          .toString();
    } catch (_) {
      res = 'erreur';
    }
    if (!mounted) return;
    setState(() => _envoi = false);
    _info(switch (res) {
      'ok' => "Demande envoyée ! L'équipe Zamu te répond très vite 🙌".tr,
      'en_attente' => 'Ta demande est déjà en cours d\'examen'.tr,
      'criteres' => 'Tous les critères ne sont pas encore remplis'.tr,
      'trop_tot' => 'Tu pourras refaire une demande 14 jours après un refus'.tr,
      'deja_star' => 'Tu es déjà Zamu Star ⭐'.tr,
      _ => 'Action impossible, réessaie'.tr,
    });
    _charger();
  }

  Widget _critere(bool ok, String texte, [String? detail]) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: ok ? AppColors.online : AppColors.textMuted, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(texte,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: ok ? FontWeight.w600 : FontWeight.w400)),
          ),
          if (detail != null)
            Text(detail, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final estStar = c?['est_star'] == true;
    final demande = c?['demande'] as Map?;
    final enAttente = demande?['statut'] == 'en_attente';
    final refusee = demande?['statut'] == 'refusee';
    final ok = c?['ok'] == true;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        title: Text('⭐ Zamu Star'.tr,
            style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      ),
      body: _chargement
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : c == null
              ? Center(
                  child: Text('Bientôt disponible'.tr,
                      style: TextStyle(color: AppColors.textMuted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    // En-tête
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFFB300), Color(0xFFFF3CAC)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const BadgeStar(size: 34),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                    estStar
                                        ? 'Tu es Zamu Star !'.tr
                                        : 'Deviens Zamu Star'.tr,
                                    style: const TextStyle(
                                        color: AppColors.surAccent,
                                        fontSize: 21,
                                        fontWeight: FontWeight.w900)),
                              ),
                            ]),
                            const SizedBox(height: 10),
                            Text(
                                '⭐ Badge sur ton profil et tes stories\n🚀 Tes stories en tête de Découvrir, vues par tous\n👥 Une communauté qui te suit'
                                    .tr,
                                style: const TextStyle(
                                    color: AppColors.surAccent, height: 1.6)),
                          ]),
                    ),
                    const SizedBox(height: 20),
                    if (estStar) ...[
                      Text(
                          'Publie régulièrement : ton statut peut être retiré après 30 jours sans story, ou en cas de non-respect des règles (nudité, arnaque).'
                              .tr,
                          style: TextStyle(color: AppColors.textMuted, height: 1.5)),
                    ] else if (enAttente) ...[
                      _bandeau('⏳', 'Ta demande est en cours d\'examen'.tr,
                          "L'équipe Zamu te répond par message".tr),
                    ] else ...[
                      if (refusee)
                        _bandeau('ℹ️', 'Ta dernière demande n\'a pas été acceptée'.tr,
                            (demande?['motif'] as String?) ?? ''),
                      Text('Les critères'.tr,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      _critere(c['verifie'] == true, 'Profil vérifié (badge bleu ✓)'.tr),
                      _critere(c['visage'] == true, 'Photo principale avec ton visage'.tr),
                      _critere(c['anciennete'] == true, 'Membre depuis plus de 14 jours'.tr),
                      _critere(c['jamais_suspendu'] == true, 'Compte jamais suspendu'.tr),
                      _critere((c['stories'] ?? 0) >= (c['stories_min'] ?? 5),
                          'Stories publiées sur 30 jours'.tr,
                          '${c['stories'] ?? 0} / ${c['stories_min'] ?? 5}'),
                      _critere((c['vues'] ?? 0) >= (c['vues_min'] ?? 100),
                          'Vues de tes stories sur 30 jours'.tr,
                          '${c['vues'] ?? 0} / ${c['vues_min'] ?? 100}'),
                      const SizedBox(height: 14),
                      if (!ok)
                        Text(
                            'Continue à publier des stories : dès que tout est coché, tu pourras envoyer ta demande.'
                                .tr,
                            style: TextStyle(color: AppColors.textMuted, height: 1.5))
                      else ...[
                        Text('Ta demande'.tr,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final (id, emoji, nom) in _categories)
                            ChoiceChip(
                              label: Text('$emoji ${nom.tr}'),
                              selected: _categorie == id,
                              onSelected: (_) => setState(() => _categorie = id),
                            ),
                        ]),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _presentation,
                          maxLength: 400,
                          maxLines: 3,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Présente-toi : ce que tu fais, ce que tu partages…'.tr,
                            hintStyle: TextStyle(color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        TextField(
                          controller: _lien,
                          maxLength: 200,
                          style: TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Ton TikTok ou Instagram (facultatif)'.tr,
                            hintStyle: TextStyle(color: AppColors.textMuted),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _accepte,
                          activeColor: AppColors.accent,
                          onChanged: (v) => setState(() => _accepte = v ?? false),
                          title: Text(
                              "J'accepte que mes stories soient vues par tous les membres de Zamu"
                                  .tr,
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13.5)),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _envoyer,
                          child: Container(
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                  colors: [Color(0xFFFFB300), Color(0xFFFF3CAC)]),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: _envoi
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppColors.surAccent))
                                : Text('Envoyer ma demande ⭐'.tr,
                                    style: const TextStyle(
                                        color: AppColors.surAccent,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
    );
  }

  Widget _bandeau(String emoji, String titre, String texte) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titre,
                  style: TextStyle(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              if (texte.isNotEmpty)
                Text(texte, style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ]),
          ),
        ]),
      );
}
