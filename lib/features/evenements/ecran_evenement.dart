import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/groupes/groupes_controller.dart';
import 'package:rencontre/core/services/ouvrir_profil.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/evenements/evenement_model.dart';
import 'package:rencontre/features/evenements/evenements_controller.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Détail d'un événement : infos, « ✋ J'y vais » / « ⭐ Intéressé »,
/// « 📍 Je suis sur place », stories de l'événement, et qui vient
/// (visible seulement quand on participe soi-même).
class EcranEvenement extends StatefulWidget {
  final EvenementModel evenement;
  const EcranEvenement({super.key, required this.evenement});

  @override
  State<EcranEvenement> createState() => _EcranEvenementState();
}

class _EcranEvenementState extends State<EcranEvenement> {
  late EvenementModel _ev = widget.evenement;
  List<ParticipantEvenement>? _participants;
  List<StoryModel> _stories = const [];
  bool _envoi = false;

  EvenementsController get _ctrl => EvenementsController.to;

  @override
  void initState() {
    super.initState();
    if (_ev.jeParticipe) _chargerParticipants();
    _chargerStories();
  }

  Future<void> _chargerParticipants() async {
    final liste = await _ctrl.participants(_ev.id);
    if (mounted) setState(() => _participants = liste);
  }

  Future<void> _chargerStories() async {
    if (!Get.isRegistered<HomeController>()) return;
    final s = await Get.find<HomeController>().storiesEvenement(_ev.id);
    if (mounted) setState(() => _stories = s);
  }

  Future<void> _participer(String? statut) async {
    if (_envoi) return;
    setState(() => _envoi = true);
    final avant = _ev.jeParticipe;
    final maj = await _ctrl.participer(_ev, statut);
    if (!mounted) return;
    setState(() {
      _envoi = false;
      _ev = maj;
      if (!_ev.jeParticipe) _participants = null;
    });
    if (_ev.jeParticipe && !avant) _chargerParticipants();
  }

  Future<void> _surPlace() async {
    if (_envoi) return;
    setState(() => _envoi = true);
    final avant = _ev.jeParticipe;
    final maj = await _ctrl.marquerSurPlace(_ev);
    if (!mounted) return;
    setState(() {
      _envoi = false;
      _ev = maj;
    });
    // Nouvelle liste : je viens de rejoindre, ou je suis passé « sur place »
    if (_ev.jeParticipe || avant) _chargerParticipants();
  }

  Future<void> _itineraire() async {
    final q = (_ev.latitude != null && _ev.longitude != null)
        ? '${_ev.latitude},${_ev.longitude}'
        : _ev.lieuComplet;
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1'
        '&query=${Uri.encodeComponent(q)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _partager() {
    SharePlus.instance.share(ShareParams(
      text: '${_ev.emoji} ${_ev.titre}\n'
          '📅 ${_ev.dateLongue}\n📍 ${_ev.lieuComplet}\n\n'
          '${_ev.jYVais ? 'J\'y vais ! ' : ''}Retrouve-moi sur Zamu, '
          'l\'événement est sur l\'accueil 👇\n'
          'https://play.google.com/store/apps/details?id=com.vybestyle.zamu',
    ));
  }

  void _ouvrirStories(int index) {
    if (_stories.isEmpty) return;
    Get.to(() => StoryViewerScreen(stories: _stories, initialIndex: index));
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
          foregroundColor: AppColors.surMedia,
          // Pastilles sombres : lisibles sur la photo comme sur la barre
          // (blanche en fond blanc une fois l'affiche repliée)
          leading: Padding(
            padding: const EdgeInsets.all(8),
            child: IconButton(
              onPressed: Get.back,
              style: IconButton.styleFrom(backgroundColor: Colors.black38),
              icon: const Icon(Icons.arrow_back_rounded,
                  color: AppColors.surMedia, size: 20),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: 'Partager',
                onPressed: _partager,
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
                icon: const Icon(Icons.share_rounded,
                    color: AppColors.surMedia, size: 20),
              ),
            ),
          ],
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
                const _Bandeau(
                    couleur: Colors.red, texte: '❌ Cet événement est annulé'),
              if (ev.enCours)
                _Bandeau(
                    couleur: AppColors.online,
                    texte: ev.nbSurPlace > 0
                        ? '🔴 En ce moment — ${ev.nbSurPlace} sur place'
                        : '🔴 En ce moment'),
              Text('${ev.emoji} ${ev.libelleCategorie}'.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.lien)),
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
                texte: ev.distanceKm == null
                    ? ev.lieuComplet
                    : '${ev.lieuComplet}  ·  ${_distance(ev.distanceKm!)}',
                action: 'Itinéraire',
                onAction: _itineraire,
              ),
              const SizedBox(height: 18),

              // ── Participation ──
              if (!ev.annule && !termine) _boutons(ev),
              const SizedBox(height: 10),
              Center(child: _compteurs(ev)),
              if (ev.nbMatchs > 0) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                      '💘 ${ev.nbMatchs} de tes matchs ${ev.nbMatchs > 1 ? 'y participent' : 'y participe'}',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.lien)),
                ),
              ],

              // ── Discussion de groupe des participants ──
              if (ev.jeParticipe) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => Get.isRegistered<GroupesController>()
                      ? GroupesController.to.ouvrirGroupeEvenement(ev.id)
                      : null,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.accent),
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.forum_rounded,
                              color: AppColors.accent, size: 20),
                          const SizedBox(width: 8),
                          Text('Discussion du groupe',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.lien)),
                        ]),
                  ),
                ),
              ],

              // ── Stories de l'événement ──
              if (_stories.isNotEmpty) ...[
                const SizedBox(height: 22),
                _titre('📸 Stories de l\'événement'),
                const SizedBox(height: 10),
                SizedBox(
                  height: 86,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _stories.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _BulleStory(
                        story: _stories[i], onTap: () => _ouvrirStories(i)),
                  ),
                ),
              ],

              // ── Qui vient ──
              const SizedBox(height: 22),
              _titre(termine ? '👋 Ils étaient là aussi' : 'Qui vient'),
              const SizedBox(height: 10),
              _qui(ev, termine),

              if ((ev.description ?? '').isNotEmpty) ...[
                const SizedBox(height: 22),
                _titre('À propos'),
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

  static String _distance(double km) =>
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';

  Widget _titre(String t) => Text(t,
      style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary));

  Widget _compteurs(EvenementModel ev) {
    final parts = <String>[
      if (ev.nbParticipants > 0)
        '${ev.nbParticipants} ${ev.nbParticipants > 1 ? 'y vont' : 'y va'}',
      if (ev.nbInteresses > 0)
        '${ev.nbInteresses} intéressé${ev.nbInteresses > 1 ? 's' : ''}',
      if (ev.nbSurPlace > 0) '${ev.nbSurPlace} sur place',
    ];
    return Text(parts.isEmpty ? 'Sois le premier à y aller 🎉' : parts.join('  ·  '),
        style: TextStyle(fontSize: 13, color: AppColors.textMuted));
  }

  Widget _boutons(EvenementModel ev) {
    Widget bouton(String label, bool actif, VoidCallback onTap,
            {bool principal = false}) =>
        Expanded(
          child: GestureDetector(
            onTap: _envoi ? null : onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 50,
              decoration: BoxDecoration(
                gradient: actif || !principal ? null : AppColors.gradientPink,
                color: actif
                    ? AppColors.online.withValues(alpha: 0.15)
                    : (principal ? null : AppColors.surface),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: actif
                        ? AppColors.online
                        : (principal ? Colors.transparent : AppColors.border),
                    width: actif ? 2 : 1),
              ),
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: actif
                            ? AppColors.online
                            : (principal
                                ? AppColors.surAccent
                                : AppColors.textPrimary))),
              ),
            ),
          ),
        );

    return Column(children: [
      Row(children: [
        bouton(ev.jYVais ? '✓ J\'y vais' : '✋ J\'y vais', ev.jYVais,
            () => _participer(ev.jYVais ? null : 'y_va'),
            principal: true),
        const SizedBox(width: 10),
        bouton(
            ev.maParticipation == 'interesse' ? '✓ Intéressé' : '⭐ Intéressé',
            ev.maParticipation == 'interesse',
            () => _participer(
                ev.maParticipation == 'interesse' ? null : 'interesse')),
      ]),
      // 📍 Sur place : pendant l'événement (1 h avant → fin)
      if (ev.surPlacePossible) ...[
        const SizedBox(height: 10),
        GestureDetector(
          onTap: ev.jeSuisSurPlace || _envoi ? null : _surPlace,
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: ev.jeSuisSurPlace
                  ? AppColors.online.withValues(alpha: 0.15)
                  : AppColors.online,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.online, width: 2),
            ),
            child: Center(
              child: _envoi
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.surAccent))
                  : Text(
                      ev.jeSuisSurPlace
                          ? '📍 Tu es sur place'
                          : '📍 Je suis sur place',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: ev.jeSuisSurPlace
                              ? AppColors.online
                              : AppColors.surAccent)),
            ),
          ),
        ),
      ],
      if (ev.jeParticipe) ...[
        const SizedBox(height: 6),
        Text('Touche à nouveau pour ne plus participer',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    ]);
  }

  Widget _qui(EvenementModel ev, bool termine) {
    if (!ev.jeParticipe && termine) {
      return Text('Cet événement est terminé.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted));
    }
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
                'Indique « J\'y vais » ou « Intéressé » pour voir qui vient '
                'et leur écrire avant de te retrouver sur place.',
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
      return Text(
          termine
              ? "Personne d'autre n'était inscrit cette fois."
              : 'Personne d\'autre pour l\'instant. Partage l\'événement à tes amis !',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted));
    }
    // Après l'événement : tout le monde ensemble, pour se dire bonjour
    if (termine) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sousTitre('Tu les as peut-être croisés : dis-leur bonjour 👋'),
        _grille(liste),
      ]);
    }
    final surPlace = liste.where((p) => p.surPlace).toList();
    final autres = liste.where((p) => !p.surPlace).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (surPlace.isNotEmpty) ...[
        _sousTitre('📍 Sur place maintenant (${surPlace.length})'),
        _grille(surPlace),
        const SizedBox(height: 14),
      ],
      if (autres.isNotEmpty) ...[
        if (surPlace.isNotEmpty)
          _sousTitre('Prévoient de venir (${autres.length})'),
        _grille(autres),
      ],
    ]);
  }

  Widget _sousTitre(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted)),
      );

  Widget _grille(List<ParticipantEvenement> liste) => GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 8,
            childAspectRatio: 0.72),
        itemCount: liste.length,
        itemBuilder: (_, i) => _Participant(p: liste[i]),
      );
}

class _Participant extends StatelessWidget {
  final ParticipantEvenement p;
  const _Participant({required this.p});

  @override
  Widget build(BuildContext context) {
    // Pastille : 💘 match, ❤️ liké, 🙋 dispo
    final pastille = p.estMatch
        ? '💘'
        : p.jeLike
            ? '❤️'
            : p.dispo
                ? '🙋'
                : null;
    return GestureDetector(
      onTap: () => ouvrirProfilParId(p.id),
      child: Column(children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: p.surPlace ? AppColors.online : Colors.transparent,
                  width: 2),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: AppColors.surface2,
              backgroundImage: (p.photoUrl ?? '').isNotEmpty
                  ? CachedNetworkImageProvider(p.photoUrl!)
                  : null,
              onBackgroundImageError:
                  (p.photoUrl ?? '').isNotEmpty ? (_, __) {} : null,
              child: (p.photoUrl ?? '').isEmpty
                  ? Text(p.nom.isEmpty ? '?' : p.nom[0].toUpperCase(),
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w700))
                  : null,
            ),
          ),
          if (p.enLigne)
            Positioned(
              right: 3,
              bottom: 3,
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
          if (pastille != null)
            Positioned(
              right: -2,
              top: -2,
              child: Text(pastille, style: const TextStyle(fontSize: 16)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(p.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
        if (p.interesse)
          Text('intéressé',
              style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ]),
    );
  }
}

class _BulleStory extends StatelessWidget {
  final StoryModel story;
  final VoidCallback onTap;
  const _BulleStory({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = story.isVideo || story.mediaUrl.isEmpty
        ? story.userPhotoUrl
        : story.mediaUrl;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: story.isSeen ? null : AppColors.anneauStory,
            color: story.isSeen ? AppColors.border : null,
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.surface2,
            backgroundImage: (image ?? '').isNotEmpty
                ? CachedNetworkImageProvider(image!)
                : null,
            onBackgroundImageError: (image ?? '').isNotEmpty ? (_, __) {} : null,
            child: (image ?? '').isEmpty
                ? Icon(Icons.auto_stories_rounded, color: AppColors.textPrimary)
                : null,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 64,
          child: Text(story.userName,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: AppColors.textPrimary)),
        ),
      ]),
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
                    color: AppColors.lien)),
          ),
      ]);
}
