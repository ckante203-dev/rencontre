import 'dart:ui' show ImageFilter;
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:rencontre/features/album/album_service.dart';
import 'package:rencontre/features/album/ecran_album_prive.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/chat/view/sticker_sheet.dart';
import 'package:rencontre/features/chat/view/chat_list_screen.dart'
    show BadgeFlamme;
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/features/home/widget/story_report_sheet.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

part 'conversation_bulles.dart';
part 'conversation_medias.dart';
part 'conversation_saisie.dart';

enum SnapDuration { unique, s3, s10, s30, none }

extension SnapDurationExt on SnapDuration {
  String get label {
    switch (this) {
      case SnapDuration.unique:
        return 'Vue unique';
      case SnapDuration.s3:
        return '3 secondes';
      case SnapDuration.s10:
        return '10 secondes';
      case SnapDuration.s30:
        return '30 secondes';
      case SnapDuration.none:
        return 'Ne pas supprimer';
    }
  }

  int? get seconds {
    switch (this) {
      case SnapDuration.unique:
        return 0;
      case SnapDuration.s3:
        return 3;
      case SnapDuration.s10:
        return 10;
      case SnapDuration.s30:
        return 30;
      case SnapDuration.none:
        return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  CONVERSATION SCREEN
// ═══════════════════════════════════════════════════════════════════

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late ConversationController ctrl;
  late String _convId;
  final _textController = TextEditingController();

  // ✅ FIX — contrôleurs créés par un nouvel écran alors que l'écran
  // précédent de la même conversation (en cours de fermeture) occupe
  // encore le tag convId. Ils prennent le relais sous ce tag dès que
  // l'ancien contrôleur est supprimé.
  static final Map<String, ConversationController> _pendingByConv = {};

  @override
  void initState() {
    super.initState();
    final conv = Get.arguments as ConversationModel;
    _convId = conv.id;
    // ✅ FIX — chaque écran possède SA propre instance. Auparavant,
    // Get.put renvoyait l'instance déjà enregistrée sous ce tag (ex :
    // réouverture depuis une notification : Get.back puis toNamed),
    // puis la suppression différée de l'ancien écran la fermait
    // (ScrollController utilisé après dispose, Realtime perdu).
    // L'enregistrement est "permanent" pour que le nettoyage automatique
    // de GetX par route (qui supprime par clé, donc potentiellement
    // l'instance du nouvel écran) ne s'applique pas : c'est dispose()
    // ci-dessous qui gère la durée de vie.
    ctrl = ConversationController();
    if (Get.isRegistered<ConversationController>(tag: _convId)) {
      ctrl.onStart();
      _pendingByConv[_convId] = ctrl;
    } else {
      Get.put(ctrl, tag: _convId, permanent: true);
    }
    ctrl.textController = _textController;
    _textController.addListener(ctrl.onTextChanged);
    ctrl.init(conv);
  }

  @override
  void dispose() {
    try {
      _textController.removeListener(ctrl.onTextChanged);
    } catch (_) {}
    _textController.dispose();
    final convId = _convId;
    final mine = ctrl;
    // ✅ FIX — si cet écran attendait encore de prendre le tag, il
    // renonce à le faire.
    if (identical(_pendingByConv[convId], mine)) {
      _pendingByConv.remove(convId);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ FIX — on ne supprime l'enregistrement que s'il s'agit bien
      // de l'instance créée par CET écran ; sinon on ferme seulement
      // notre propre instance, sans toucher à celle d'un autre écran.
      final registered = Get.isRegistered<ConversationController>(tag: convId)
          ? Get.find<ConversationController>(tag: convId)
          : null;
      if (identical(registered, mine)) {
        Get.delete<ConversationController>(tag: convId, force: true);
      } else {
        mine.onDelete();
      }
      // ✅ FIX — un écran plus récent de la même conversation prend le
      // relais sous le tag convId (utilisé par la liste, les stories…).
      if (!Get.isRegistered<ConversationController>(tag: convId)) {
        final next = _pendingByConv.remove(convId);
        if (next != null && !next.isClosed) {
          Get.put(next, tag: convId, permanent: true);
        }
      }
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(context),
      body: Column(children: [
        const _EphemeralBanner(),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: Obx(() => _FondConversation(
                    id: ctrl.fond.value,
                    child: _MessageList(ctrl: ctrl),
                  )),
            ),
            // ⌄ Redescendre aux derniers messages (+ nombre de nouveaux)
            Positioned(right: 12, bottom: 10, child: _BoutonBas(ctrl: ctrl)),
          ]),
        ),
        _BandeauEnvoi(ctrl: ctrl),
        _InputBar(ctrl: ctrl),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final conv = ctrl.conversation;
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      titleSpacing: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(color: AppColors.border, height: 0.5),
      ),
      leading: GestureDetector(
        onTap: () => Get.back(),
        child: Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(Icons.arrow_back_rounded,
              size: 24, color: AppColors.textPrimary),
        ),
      ),
      // ✅ FIX POLICE : DefaultTextStyle réinitialise le style ambiant
      // (Syne, hérité de AppBarTheme.titleTextStyle dans app_theme.dart)
      // à la police normale de l'app avant d'afficher le nom/statut.
      title: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodyMedium!,
        child: GestureDetector(
          onTap: () => _ouvrirProfil(conv),
          child: Row(children: [
            _AvatarWithStoryRing(
              userId: conv.userId,
              name: conv.userName,
              photoUrl: conv.userPhotoUrl,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(conv.userName,
                          style: TextStyle(
                              // ✅ Fix 1 : taille réduite, plus sobre
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    // 🔥 Série, lue dans la liste (mise à jour en direct)
                    if (Get.isRegistered<ChatListController>())
                      GetBuilder<ChatListController>(builder: (list) {
                        final c = list.conversations
                            .firstWhereOrNull((x) => x.id == conv.id);
                        if (c == null) return const SizedBox.shrink();
                        return BadgeFlamme(conv: c);
                      }),
                  ]),
                  Obx(() {
                    if (ctrl.isOtherTyping.value) {
                      return Text('en train d\'écrire...',
                          style: TextStyle(
                              // ✅ Fix 2 : taille réduite
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: AppColors.online,
                              fontStyle: FontStyle.italic));
                    }
                    return Text(
                      ctrl.isOtherOnline.value
                          ? 'en ligne'
                          : _vuLe(ctrl.otherLastSeen.value),
                      style: TextStyle(
                          // ✅ Fix 3 : taille et poids réduits
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: ctrl.isOtherOnline.value
                              ? AppColors.online
                              : AppColors.textMuted),
                    );
                  }),
                ],
              ),
            ),
          ]),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.more_vert_rounded,
              color: AppColors.textMuted, size: 22),
          onPressed: () => _showConvMenu(context, conv),
        ),
      ],
    );
  }

  /// « vu aujourd'hui à 14:32 », « vu hier à 21:05 », « vu le 3 oct. »
  static String _vuLe(DateTime? d) {
    if (d == null) return 'hors ligne';
    final now = DateTime.now();
    final jours = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    final h =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (jours <= 0) return "vu aujourd'hui à $h";
    if (jours == 1) return 'vu hier à $h';
    if (jours < 7) return 'vu il y a $jours jours';
    const mois = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.'
    ];
    return 'vu le ${d.day} ${mois[d.month - 1]}';
  }

  Future<void> _ouvrirProfil(ConversationModel conv) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', conv.userId)
          .maybeSingle();
      if (data == null) return;
      int age = 0;
      final birthdate = data['birthdate'] ?? data['birth_date'];
      if (birthdate != null) {
        try {
          DateTime birth;
          final s = birthdate.toString();
          if (s.contains('/')) {
            final p = s.split('/');
            birth = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
          } else {
            birth = DateTime.parse(s);
          }
          final now = DateTime.now();
          age = now.year - birth.year;
          if (now.month < birth.month ||
              (now.month == birth.month && now.day < birth.day)) age--;
        } catch (_) {
          age = data['age'] ?? 0;
        }
      }
      final user = UserModel(
        id: data['id'] ?? conv.userId,
        name: data['name'] ?? conv.userName,
        age: age,
        bio: data['bio'],
        photoUrl: data['photo_url'] ?? conv.userPhotoUrl,
        photoUrls: List<String>.from(data['photo_urls'] ?? []),
        interests: List<String>.from(data['interests'] ?? []),
        latitude: data['latitude']?.toDouble(),
        longitude: data['longitude']?.toDouble(),
        gender: data['gender'],
        lookingFor: data['looking_for'],
        isOnline: data['is_online'] ?? false,
        followersCount: data['followers_count'] ?? 0,
        followingCount: data['following_count'] ?? 0,
        matchesCount: data['matches_count'] ?? 0,
      );
      Get.toNamed('/profile/view', arguments: user);
    } catch (e) {
      debugPrint('_ouvrirProfil error: $e');
    }
  }

  void _showConvMenu(BuildContext context, ConversationModel conv) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConvMenu(
        ctrl: ctrl,
        conv: conv,
        onVoirProfil: () => _ouvrirProfil(conv),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MENU CONVERSATION
// ═══════════════════════════════════════════════════════════════════

class _ConvMenu extends StatelessWidget {
  final ConversationController ctrl;
  final ConversationModel conv;
  final VoidCallback onVoirProfil;
  const _ConvMenu(
      {required this.ctrl, required this.conv, required this.onVoirProfil});

  @override
  Widget build(BuildContext context) {
    final prenom = conv.userName;
    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.of(context).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          _EnTeteMenu(
            ctrl: ctrl,
            conv: conv,
            onTap: () {
              Get.back();
              onVoirProfil();
            },
          ),
          const SizedBox(height: 16),
          _GroupeMenu(children: [
            Obx(() => _MenuItem(
                  icon: ctrl.sourdine.value
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_outlined,
                  label: 'Couper les notifications',
                  sousTitre: ctrl.sourdine.value
                      ? 'Tu ne reçois plus d\'alerte pour cette conversation'
                      : null,
                  onTap: ctrl.basculerSourdine,
                  trailing: Switch.adaptive(
                    value: ctrl.sourdine.value,
                    onChanged: (_) => ctrl.basculerSourdine(),
                    activeColor: AppColors.accent,
                  ),
                )),
            _ItemAlbum(ctrl: ctrl),
            const _MenuItem(
              icon: Icons.videocam_outlined,
              label: 'Appel vidéo',
              desactive: true,
              trailing: _BadgeBientot(),
            ),
            Obx(() => _MenuItem(
                  icon: Icons.wallpaper_rounded,
                  label: 'Fond d\'écran',
                  onTap: () {
                    Get.back();
                    _choisirFond(context);
                  },
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(_FondsChat.nom(ctrl.fond.value),
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textMuted)),
                    Icon(Icons.chevron_right_rounded,
                        color: AppColors.textMuted, size: 20),
                  ]),
                )),
          ]),
          const SizedBox(height: 12),
          _GroupeMenu(children: [
            _MenuItem(
              icon: Icons.flag_outlined,
              label: 'Signaler $prenom',
              color: AppColors.yellow,
              onTap: () async {
                Get.back();
                final raison = await choisirMotifSignalement(
                    'Pourquoi signaler $prenom ?');
                if (raison != null) {
                  ControleurProfil.to.signalerProfil(conv.userId, raison);
                }
              },
            ),
            _MenuItem(
              icon: Icons.block_rounded,
              label: 'Bloquer $prenom',
              color: AppColors.error,
              onTap: () {
                Get.back();
                _confirmerBloquer(context);
              },
            ),
          ]),
          const SizedBox(height: 12),
          _GroupeMenu(children: [
            _MenuItem(
              icon: Icons.cleaning_services_outlined,
              label: 'Effacer l\'historique',
              onTap: () {
                Get.back();
                _confirmerEffacer(context);
              },
            ),
            _MenuItem(
              icon: Icons.delete_outline_rounded,
              label: 'Supprimer l\'échange',
              color: AppColors.error,
              onTap: () {
                Get.back();
                _confirmerSupprimer(context);
              },
            ),
          ]),
        ]),
      ),
    );
  }

  void _choisirFond(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoixFond(ctrl: ctrl),
    );
  }

  Future<bool?> _confirmer(BuildContext context,
      {required String titre, required String texte, required String action}) {
    return showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(titre,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 17)),
              content: Text(texte,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 14, height: 1.4)),
              actions: [
                TextButton(
                    onPressed: () => Get.back(result: false),
                    child: Text('Annuler',
                        style: TextStyle(color: AppColors.textMuted))),
                TextButton(
                  onPressed: () => Get.back(result: true),
                  child: Text(action,
                      style: TextStyle(
                          color: AppColors.error, fontWeight: FontWeight.w700)),
                ),
              ],
            ));
  }

  Future<void> _confirmerBloquer(BuildContext context) async {
    final ok = await _confirmer(context,
        titre: 'Bloquer ${conv.userName} ?',
        texte: '${conv.userName} ne pourra plus te voir ni t\'écrire, et '
            'cette conversation disparaîtra. Tu pourras annuler depuis '
            'Paramètres > Profils bloqués.',
        action: 'Bloquer');
    if (ok == true) await ControleurProfil.to.bloquerProfil(conv.userId);
  }

  Future<void> _confirmerEffacer(BuildContext context) async {
    final ok = await _confirmer(context,
        titre: 'Effacer l\'historique ?',
        texte: 'Les messages seront effacés sur ton téléphone uniquement. '
            '${conv.userName} les verra toujours.',
        action: 'Effacer');
    if (ok == true) ctrl.effacerHistorique();
  }

  Future<void> _confirmerSupprimer(BuildContext context) async {
    final ok = await _confirmer(context,
        titre: 'Supprimer l\'échange ?',
        texte: 'Cette conversation sera supprimée définitivement, '
            'pour toi et pour ${conv.userName}.',
        action: 'Supprimer');
    if (ok != true) return;
    try {
      await Supabase.instance.client
          .from('conversations')
          .delete()
          .eq('id', conv.id);
      Get.back();
      if (Get.isRegistered<ChatListController>()) {
        Get.find<ChatListController>()
            .conversations
            .removeWhere((c) => c.id == conv.id);
      }
    } catch (e) {
      debugPrint('supprimer error: $e');
    }
  }
}

class _EnTeteMenu extends StatelessWidget {
  final ConversationController ctrl;
  final ConversationModel conv;
  final VoidCallback onTap;
  const _EnTeteMenu(
      {required this.ctrl, required this.conv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            _AvatarWithStoryRing(
              userId: conv.userId,
              name: conv.userName,
              photoUrl: conv.userPhotoUrl,
              size: 52,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conv.userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Obx(() {
                      final enLigne = ctrl.isOtherOnline.value;
                      return Row(children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: enLigne
                                  ? AppColors.online
                                  : AppColors.textMuted),
                        ),
                        const SizedBox(width: 6),
                        Text(enLigne ? 'En ligne' : 'Hors ligne',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textMuted)),
                        Flexible(
                          child: Text('  ·  Voir le profil',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary)),
                        ),
                      ]);
                    }),
                  ]),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 22),
          ]),
        ),
      ),
    );
  }
}

class _GroupeMenu extends StatelessWidget {
  final List<Widget> children;
  const _GroupeMenu({required this.children});

  @override
  Widget build(BuildContext context) {
    final lignes = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) lignes.add(_Div());
      lignes.add(children[i]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: AppColors.surface,
        child: Column(mainAxisSize: MainAxisSize.min, children: lignes),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sousTitre;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  final bool desactive;
  const _MenuItem(
      {required this.icon,
      required this.label,
      this.sousTitre,
      this.onTap,
      this.color,
      this.trailing,
      this.desactive = false});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return Opacity(
      opacity: desactive ? 0.5 : 1,
      child: InkWell(
        onTap: desactive ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: c, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            color: c,
                            fontWeight: FontWeight.w500)),
                    if (sousTitre != null) ...[
                      const SizedBox(height: 2),
                      Text(sousTitre!,
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ]),
            ),
            if (trailing != null) trailing!,
          ]),
        ),
      ),
    );
  }
}

/// Partager / retirer mon album privé avec la personne de la conversation.
class _ItemAlbum extends StatefulWidget {
  final ConversationController ctrl;
  const _ItemAlbum({required this.ctrl});

  @override
  State<_ItemAlbum> createState() => _ItemAlbumState();
}

class _ItemAlbumState extends State<_ItemAlbum> {
  bool? _partage; // null = chargement
  bool _enCours = false;

  String get _autre => widget.ctrl.conversation.userId;

  @override
  void initState() {
    super.initState();
    AlbumService.partageAvec(_autre).then((v) {
      if (mounted) setState(() => _partage = v);
    }).catchError((_) {
      if (mounted) setState(() => _partage = false);
    });
  }

  Future<void> _basculer() async {
    if (_partage == null || _enCours) return;
    final partager = !_partage!;
    setState(() => _enCours = true);
    try {
      if (partager) {
        // Même chemin que ➕ Album : partage + carte dans la discussion,
        // sans écraser le texte en cours de saisie (avant : sendText()).
        final ok = await widget.ctrl.partagerAlbum();
        if (ok == null) return; // échec : message déjà affiché
        if (!ok) {
          Get.snackbar('Ton album privé est vide',
              'Ajoute des photos depuis ton profil, puis partage-le',
              snackPosition: SnackPosition.TOP,
              backgroundColor: AppColors.surface,
              colorText: Colors.white);
          return;
        }
      } else {
        await AlbumService.retirer(_autre);
      }
      if (mounted) setState(() => _partage = partager);
    } catch (_) {
      Get.snackbar('Album privé', 'Action impossible, réessaie',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _enCours = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prenom = widget.ctrl.conversation.userName;
    return _MenuItem(
      icon: _partage == true ? Icons.lock_open_rounded : Icons.lock_rounded,
      label: 'Partager mon album privé',
      sousTitre: _partage == true ? '$prenom peut voir ton album' : null,
      onTap: _basculer,
      trailing: _partage == null || _enCours
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.accent))
          : Switch.adaptive(
              value: _partage!,
              onChanged: (_) => _basculer(),
              activeColor: AppColors.accent,
            ),
    );
  }
}

class _BadgeBientot extends StatelessWidget {
  const _BadgeBientot();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20)),
      child: Text('Bientôt',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
    );
  }
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 0.5, thickness: 0.5, color: AppColors.border, indent: 62);
}

// ═══════════════════════════════════════════════════════════════════
//  FONDS D'ÉCRAN DE CONVERSATION
// ═══════════════════════════════════════════════════════════════════

class _FondsChat {
  static const ids = ['defaut', 'doux', 'degrade', 'aurore', 'points', 'nuit'];

  static String nom(String id) =>
      const {
        'defaut': 'Aucun',
        'doux': 'Doux',
        'degrade': 'Dégradé',
        'aurore': 'Aurore',
        'points': 'Motif',
        'nuit': 'Nuit',
      }[id] ??
      'Aucun';

  static Color _teinte(Color c, double force) =>
      Color.alphaBlend(c.withOpacity(force), AppColors.bg);

  static BoxDecoration decoration(String id) {
    switch (id) {
      case 'doux':
        return BoxDecoration(color: _teinte(AppColors.accent, 0.06));
      case 'degrade':
        return BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.bg, _teinte(AppColors.accent, 0.16)]));
      case 'aurore':
        return BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
              _teinte(AppColors.accent, 0.14),
              AppColors.bg,
              _teinte(AppColors.accent2, 0.14),
            ]));
      case 'nuit':
        return BoxDecoration(
            color:
                Color.alphaBlend(Colors.black.withOpacity(0.45), AppColors.bg));
      default:
        return BoxDecoration(color: AppColors.bg);
    }
  }
}

/// Fond de la liste des messages, selon le choix de l'utilisateur.
class _FondConversation extends StatelessWidget {
  final String id;
  final Widget child;
  const _FondConversation({required this.id, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _FondsChat.decoration(id),
      child: id == 'points'
          ? CustomPaint(
              painter: _MotifPoints(AppColors.textMuted), child: child)
          : child,
    );
  }
}

class _MotifPoints extends CustomPainter {
  final Color couleur;
  _MotifPoints(this.couleur);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = couleur.withOpacity(0.10);
    const pas = 22.0;
    var ligne = 0;
    for (double y = pas / 2; y < size.height; y += pas, ligne++) {
      final decalage = ligne.isEven ? 0.0 : pas / 2;
      for (double x = pas / 2 + decalage; x < size.width; x += pas) {
        canvas.drawCircle(Offset(x, y), 1.4, p);
      }
    }
  }

  @override
  bool shouldRepaint(_MotifPoints old) => old.couleur != couleur;
}

class _ChoixFond extends StatelessWidget {
  final ConversationController ctrl;
  const _ChoixFond({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, MediaQuery.of(context).padding.bottom + 20),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2))),
        Text('Fond d\'écran',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Visible uniquement par toi',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 18),
        Obx(() => GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.72,
              children: _FondsChat.ids.map((id) {
                final choisi = ctrl.fond.value == id;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ctrl.choisirFond(id);
                  },
                  child: Column(children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color:
                                  choisi ? AppColors.accent : AppColors.border,
                              width: choisi ? 2 : 1),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _FondConversation(
                            id: id,
                            child: _ApercuBulles(choisi: choisi),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_FondsChat.nom(id),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                choisi ? FontWeight.w700 : FontWeight.w500,
                            color: choisi
                                ? AppColors.textPrimary
                                : AppColors.textMuted)),
                  ]),
                );
              }).toList(),
            )),
      ]),
    );
  }
}

/// Mini-conversation dessinée dans l'aperçu d'un fond.
class _ApercuBulles extends StatelessWidget {
  final bool choisi;
  const _ApercuBulles({required this.choisi});

  @override
  Widget build(BuildContext context) {
    Widget bulle(double largeur, bool moi) => Align(
          alignment: moi ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: largeur,
            height: 12,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
                color: moi ? AppColors.accent : AppColors.surface2,
                borderRadius: BorderRadius.circular(6)),
          ),
        );
    return Stack(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          bulle(44, false),
          bulle(56, true),
          bulle(36, false),
        ]),
      ),
      if (choisi)
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration:
                BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
            child:
                const Icon(Icons.check_rounded, size: 13, color: Colors.white),
          ),
        ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════
//  BANNIÈRE ÉPHÉMÈRE
// ═══════════════════════════════════════════════════════════════════

// ✅ Messages directs : explique pourquoi l'envoi est bloqué
// (limite de messages sans réponse, ou blocage).
class _BandeauEnvoi extends StatelessWidget {
  final ConversationController ctrl;
  const _BandeauEnvoi({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final String? texte = ctrl.bloque.value
          ? 'Tu ne peux plus écrire à cette personne'
          : ctrl.limiteAtteinte.value
              ? 'Tu as envoyé '
                  '${ConversationController.limiteSansReponse} messages. '
                  'Attends sa réponse pour continuer.'
              : null;
      if (texte == null) return const SizedBox.shrink();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.surface2,
        child: Row(children: [
          Icon(Icons.hourglass_top_rounded,
              size: 14, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texte,
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ]),
      );
    });
  }
}

class _EphemeralBanner extends StatelessWidget {
  const _EphemeralBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.surface2,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.timer_outlined, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 6),
        Flexible(
          child: Text('Les messages disparaissent 24h après avoir été vus',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MESSAGE LIST
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  BOUTON « REDESCENDRE » (façon WhatsApp)
// ═══════════════════════════════════════════════════════════════════

class _BoutonBas extends StatefulWidget {
  final ConversationController ctrl;
  const _BoutonBas({required this.ctrl});
  @override
  State<_BoutonBas> createState() => _BoutonBasState();
}

class _BoutonBasState extends State<_BoutonBas> {
  bool _visible = false;
  int _nouveaux = 0;
  int _nbVu = 0;
  Worker? _worker;

  ScrollController get _scroll => widget.ctrl.scrollController;

  @override
  void initState() {
    super.initState();
    _nbVu = widget.ctrl.messages.length;
    _scroll.addListener(_surDefilement);
    // Messages reçus pendant qu'on lit plus haut → compteur
    _worker = ever(widget.ctrl.messages, (List<MessageModel> l) {
      if (!mounted) return;
      if (!_visible) {
        _nbVu = l.length;
        return;
      }
      final n = l.length - _nbVu;
      final recus = l.reversed
          .take(n.clamp(0, l.length))
          .where((m) => m.senderId != widget.ctrl.myId)
          .length;
      if (recus != _nouveaux) setState(() => _nouveaux = recus);
    });
  }

  void _surDefilement() {
    if (!_scroll.hasClients) return;
    // Liste inversée : 0 = tout en bas
    final loin = _scroll.offset > 400;
    if (loin != _visible) {
      setState(() {
        _visible = loin;
        if (!loin) {
          _nouveaux = 0;
          _nbVu = widget.ctrl.messages.length;
        }
      });
    }
  }

  @override
  void dispose() {
    _worker?.dispose();
    try {
      _scroll.removeListener(_surDefilement);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedScale(
        scale: _visible ? 1 : 0.6,
        duration: const Duration(milliseconds: 180),
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: GestureDetector(
            onTap: () => _scroll.animateTo(0,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic),
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface2,
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 8),
                  ],
                ),
                child: Icon(Icons.keyboard_double_arrow_down_rounded,
                    color: AppColors.textPrimary, size: 22),
              ),
              if (_nouveaux > 0)
                Positioned(
                  top: -6,
                  right: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_nouveaux > 99 ? '99+' : '$_nouveaux',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
