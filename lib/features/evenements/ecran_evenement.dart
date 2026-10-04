import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';
import 'package:url_launcher/url_launcher.dart';

/// Détail d'un événement : infos, « ✋ J'y vais », et qui vient (visible
/// seulement quand on participe soi-même).
class EcranEvenement extends StatefulWidget {
  final EvenementModel evenement;
  const EcranEvenement({super.key, required this.evenement});

  @override
  State<EcranEvenement> createState() => _EcranEvenementState();
}

class _EcranEvenementState extends State<EcranEvenement> {
  late EvenementModel _ev = widget.evenement;
  List<ParticipantEvenement>? _participants;
  bool _envoi = false;

  EvenementsController get _ctrl => EvenementsController.to;

  @override
  void initState() {
    super.initState();
    if (_ev.jeParticipe) _chargerParticipants();
  }

  Future<void> _chargerParticipants() async {
    final liste = await _ctrl.participants(_ev.id);
    if (mounted) setState(() => _participants = liste);
  }

  Future<void> _basculer() async {
    if (_envoi) return;
    setState(() => _envoi = true);
    final maj = await _ctrl.basculerParticipation(_ev);
    if (!mounted) return;
    setState(() {
      _envoi = false;
      if (maj != null) _ev = maj;
      if (!_ev.jeParticipe) _participants = null;
    });
    if (_ev.jeParticipe) _chargerParticipants();
  }

  Future<void> _itineraire() async {
    final q = (_ev.latitude != null && _ev.longitude != null)
        ? '${_ev.latitude},${_ev.longitude}'
        : _ev.lieuComplet;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1'
        '&query=${Uri.encodeComponent(q)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final ev = _ev;
    final termine = DateTime.now().isAfter(ev.finEffective);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        // ── Affiche ──
        SliverAppBar(
          expandedHeight: 240,
          pinned: true,
          backgroundColor: AppColors.bg,
          foregroundColor: Colors.white,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              if ((ev.imageUrl ?? '').isNotEmpty)
                CachedNetworkImage(imageUrl: ev.imageUrl!, fit: BoxFit.cover)
              else
                Container(
                  decoration: BoxDecoration(gradient: AppColors.gradientPink),
                  child: Center(
                      child:
                          Text(ev.emoji, style: const TextStyle(fontSize: 80))),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent, Colors.black54],
                  ),
                ),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (ev.annule)
                _Bandeau(
                    couleur: Colors.red,
                    texte: '❌ Cet événement est annulé'),
              if (ev.enCours)
                _Bandeau(
                    couleur: AppColors.online,
                    texte: '🔴 En ce moment — retrouve les participants'),
              Text('${ev.emoji} ${ev.libelleCategorie}'.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent)),
              const SizedBox(height: 6),
              Text(ev.titre,
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 14),
              _Ligne(icon: Icons.schedule_rounded, texte: ev.dateLongue),
              const SizedBox(height: 8),
              _Ligne(
                icon: Icons.place_rounded,
                texte: ev.lieuComplet,
                action: 'Itinéraire',
                onAction: _itineraire,
              ),
              const SizedBox(height: 18),

              // ── J'y vais ──
              if (!ev.annule && !termine)
                GestureDetector(
                  onTap: _basculer,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: ev.jeParticipe ? null : AppColors.gradientPink,
                      color: ev.jeParticipe ? AppColors.surface : null,
                      borderRadius: BorderRadius.circular(16),
                      border: ev.jeParticipe
                          ? Border.all(color: AppColors.online, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: _envoi
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              ev.jeParticipe
                                  ? '✓ J\'y vais  ·  toucher pour annuler'
                                  : '✋ J\'y vais',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: ev.jeParticipe
                                      ? AppColors.online
                                      : Colors.white)),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                    ev.nbParticipants == 0
                        ? 'Sois le premier à y aller 🎉'
                        : '${ev.nbParticipants} personne${ev.nbParticipants > 1 ? 's' : ''} y ${ev.nbParticipants > 1 ? 'vont' : 'va'}',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              ),
              const SizedBox(height: 22),

              // ── Qui vient ──
              Text('Qui vient',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              _qui(ev),

              if ((ev.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('À propos',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text(ev.description!,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppColors.textPrimary)),
              ],

              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                    '🛡️ Rencontre-toi dans un endroit public et fréquenté, '
                    'préviens un proche, et ne pars pas seul(e) avec quelqu\'un '
                    'que tu viens de rencontrer. Un comportement suspect ? '
                    'Signale le profil.',
                    style: TextStyle(
                        fontSize: 12, height: 1.5, color: AppColors.textMuted)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _qui(EvenementModel ev) {
    if (!ev.jeParticipe) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Text('🔒', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                'Indique « J\'y vais » pour voir qui vient et leur écrire avant '
                'de te retrouver sur place.',
                style: TextStyle(
                    fontSize: 13, height: 1.4, color: AppColors.textPrimary)),
          ),
        ]),
      );
    }
    final liste = _participants;
    if (liste == null) {
      return Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2));
    }
    if (liste.isEmpty) {
      return Text('Personne d\'autre pour l\'instant. Partage l\'événement à tes amis !',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 8,
          childAspectRatio: 0.78),
      itemCount: liste.length,
      itemBuilder: (_, i) {
        final p = liste[i];
        return GestureDetector(
          onTap: () => ouvrirProfilParId(p.id),
          child: Column(children: [
            Stack(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.surface2,
                backgroundImage: (p.photoUrl ?? '').isNotEmpty
                    ? CachedNetworkImageProvider(p.photoUrl!)
                    : null,
                onBackgroundImageError:
                    (p.photoUrl ?? '').isNotEmpty ? (_, __) {} : null,
                child: (p.photoUrl ?? '').isEmpty
                    ? Text(p.nom.isEmpty ? '?' : p.nom[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              if (p.enLigne)
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: AppColors.online,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.bg, width: 2),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 5),
            Text(p.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          ]),
        );
      },
    );
  }
}

class _Bandeau extends StatelessWidget {
  final Color couleur;
  final String texte;
  const _Bandeau({required this.couleur, required this.texte});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: couleur.withValues(alpha: 0.6)),
        ),
        child: Text(texte,
            style: TextStyle(
                color: couleur, fontWeight: FontWeight.w700, fontSize: 13)),
      );
}

class _Ligne extends StatelessWidget {
  final IconData icon;
  final String texte;
  final String? action;
  final VoidCallback? onAction;
  const _Ligne(
      {required this.icon, required this.texte, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(texte,
              style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        ),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Text(action!,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.accent)),
          ),
      ]);
}
