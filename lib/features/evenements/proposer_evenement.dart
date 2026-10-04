import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';

/// Proposer un événement : envoyé « en attente », publié par Zamu après
/// vérification (3 propositions en attente maximum par personne).
class ProposerEvenement extends StatefulWidget {
  const ProposerEvenement({super.key});

  @override
  State<ProposerEvenement> createState() => _ProposerEvenementState();
}

class _ProposerEvenementState extends State<ProposerEvenement> {
  final _titre = TextEditingController();
  final _lieu = TextEditingController();
  final _ville = TextEditingController();
  final _description = TextEditingController();
  String _categorie = 'sport';
  DateTime? _debut;
  bool _envoi = false;

  static const _categories = {
    'sport': '⚽ Sport',
    'concert': '🎤 Concert',
    'soiree': '🎉 Soirée',
    'festival': '🎪 Festival',
    'autre': '📅 Autre',
  };

  @override
  void dispose() {
    _titre.dispose();
    _lieu.dispose();
    _ville.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _choisirDate() async {
    final maintenant = DateTime.now();
    final jour = await showDatePicker(
      context: context,
      initialDate: _debut ?? maintenant.add(const Duration(days: 1)),
      firstDate: maintenant,
      lastDate: maintenant.add(const Duration(days: 365)),
    );
    if (jour == null || !mounted) return;
    final heure = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_debut ?? DateTime(0, 1, 1, 20)),
    );
    if (heure == null) return;
    setState(() => _debut =
        DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute));
  }

  Future<void> _envoyer() async {
    final titre = _titre.text.trim(), lieu = _lieu.text.trim();
    String? erreur;
    if (titre.length < 3) erreur = 'Donne un titre (3 caractères minimum)';
    if (lieu.length < 2) erreur ??= 'Indique le lieu';
    if (_debut == null) erreur ??= 'Choisis la date et l\'heure';
    if (_debut != null && _debut!.isBefore(DateTime.now())) {
      erreur ??= 'La date doit être dans le futur';
    }
    if (erreur != null) {
      Get.snackbar('Il manque quelque chose', erreur,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
      return;
    }
    setState(() => _envoi = true);
    final ok = await EvenementsController.to.proposer(
      titre: titre,
      categorie: _categorie,
      lieu: lieu,
      ville: _ville.text.trim(),
      description: _description.text.trim(),
      debut: _debut!,
    );
    if (!mounted) return;
    setState(() => _envoi = false);
    if (ok) {
      Get.back();
      Get.snackbar('Proposition envoyée 🎉',
          'Zamu la vérifie et la publie si elle est validée',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white,
          duration: const Duration(seconds: 4));
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surface,
        counterText: '',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: AppColors.textPrimary);
    final date = _debut == null
        ? 'Choisir la date et l\'heure'
        : EvenementModel(id: '', titre: '', lieu: '', debut: _debut!)
            .dateLongue;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text('Proposer un événement',
            style: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text(
              'Un match, un concert, une soirée… Zamu vérifie ta proposition '
              'avant de la publier pour tout le monde.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
          _label('Titre'),
          TextField(
              controller: _titre,
              maxLength: 80,
              style: style,
              decoration: _deco('ex : ASEC – Africa')),
          _label('Catégorie'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _categories.entries)
              ChoiceChip(
                label: Text(c.value),
                selected: _categorie == c.key,
                onSelected: (_) => setState(() => _categorie = c.key),
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.surface,
                labelStyle: TextStyle(
                    color: _categorie == c.key
                        ? Colors.white
                        : AppColors.textPrimary),
              ),
          ]),
          _label('Date et heure'),
          GestureDetector(
            onTap: _choisirDate,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(Icons.schedule_rounded, color: AppColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(date,
                        style: TextStyle(
                            color: _debut == null
                                ? AppColors.textMuted
                                : AppColors.textPrimary))),
              ]),
            ),
          ),
          _label('Lieu (public)'),
          TextField(
              controller: _lieu,
              maxLength: 120,
              style: style,
              decoration: _deco('ex : Stade Félix Houphouët-Boigny')),
          _label('Ville'),
          TextField(
              controller: _ville,
              maxLength: 60,
              style: style,
              decoration: _deco('ex : Abidjan')),
          _label('Description (facultatif)'),
          TextField(
              controller: _description,
              maxLength: 1000,
              maxLines: 4,
              style: style,
              decoration: _deco('Infos pratiques, ambiance…')),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _envoi ? null : _envoyer,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPink,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: _envoi
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Envoyer la proposition',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
