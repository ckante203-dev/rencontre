import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/chat/controller/chat_controller.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/story_screen.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

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
        Expanded(child: _MessageList(ctrl: ctrl)),
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
                  Text(conv.userName,
                      style: TextStyle(
                          // ✅ Fix 1 : taille réduite, plus sobre
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Obx(() {
                    if (ctrl.isOtherTyping.value) {
                      return Text('en train d\'écrire...',
                          style: TextStyle(
                              // ✅ Fix 2 : taille réduite
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: AppColors.accent,
                              fontStyle: FontStyle.italic));
                    }
                    return Text(
                      ctrl.isOtherOnline.value ? 'en ligne' : 'hors ligne',
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
      builder: (_) => _ConvMenu(ctrl: ctrl, conv: conv),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MENU CONVERSATION
// ═══════════════════════════════════════════════════════════════════

class _ConvMenu extends StatelessWidget {
  final ConversationController ctrl;
  final ConversationModel conv;
  const _ConvMenu({required this.ctrl, required this.conv});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2))),
        _MenuItem(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            trailing: Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
            onTap: () {
              Get.back();
              Get.snackbar('Notifications', 'Bientôt disponible',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: AppColors.surface2,
                  colorText: Colors.white);
            }),
        _Div(),
        _MenuItem(
            icon: Icons.videocam_outlined,
            label: 'Appel vidéo',
            onTap: () {
              Get.back();
              Get.snackbar('📹 Appel vidéo', 'Bientôt disponible',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: AppColors.surface2,
                  colorText: Colors.white);
            }),
        _Div(),
        _MenuItem(
            icon: Icons.search_rounded,
            label: 'Rechercher',
            onTap: () {
              Get.back();
              Get.snackbar('🔍 Recherche', 'Bientôt disponible',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: AppColors.surface2,
                  colorText: Colors.white);
            }),
        _Div(),
        _MenuItem(
            icon: Icons.wallpaper_rounded,
            label: 'Fond d\'écran',
            onTap: () {
              Get.back();
              Get.snackbar('Fond d\'écran', 'Bientôt disponible',
                  snackPosition: SnackPosition.TOP,
                  backgroundColor: AppColors.surface2,
                  colorText: Colors.white);
            }),
        _Div(),
        _MenuItem(
            icon: Icons.cleaning_services_outlined,
            label: 'Effacer l\'historique',
            onTap: () {
              Get.back();
              _confirmerEffacer(context);
            }),
        _Div(),
        _MenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer l\'échange',
            color: AppColors.error,
            onTap: () {
              Get.back();
              _confirmerSupprimer(context);
            }),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ]),
    );
  }

  void _confirmerEffacer(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text('Effacer l\'historique ?',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              content: Text(
                  'Les messages seront masqués dans votre vue uniquement.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              actions: [
                TextButton(
                    onPressed: () => Get.back(),
                    child: Text('Annuler',
                        style: TextStyle(color: AppColors.textMuted))),
                TextButton(
                  onPressed: () {
                    Get.back();
                    ctrl.messages.clear();
                    Get.snackbar('Historique effacé', 'Votre vue a été effacée',
                        snackPosition: SnackPosition.TOP,
                        backgroundColor: AppColors.surface2,
                        colorText: Colors.white,
                        duration: const Duration(seconds: 2));
                  },
                  child:
                      Text('Effacer', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ));
  }

  void _confirmerSupprimer(BuildContext context) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text('Supprimer l\'échange ?',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              content: Text('Cette conversation sera supprimée définitivement.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              actions: [
                TextButton(
                    onPressed: () => Get.back(),
                    child: Text('Annuler',
                        style: TextStyle(color: AppColors.textMuted))),
                TextButton(
                  onPressed: () async {
                    Get.back();
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
                  },
                  child: Text('Supprimer',
                      style: TextStyle(color: AppColors.error)),
                ),
              ],
            ));
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;
  const _MenuItem(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color,
      this.trailing});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 16),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 15, color: c, fontWeight: FontWeight.w400))),
          if (trailing != null) trailing!,
        ]),
      ),
    );
  }
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(height: 0.5, color: AppColors.border, indent: 58);
}

// ═══════════════════════════════════════════════════════════════════
//  BANNIÈRE ÉPHÉMÈRE
// ═══════════════════════════════════════════════════════════════════

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

class _MessageList extends StatelessWidget {
  final ConversationController ctrl;
  const _MessageList({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (ctrl.isLoading.value) return _buildShimmer();
      if (ctrl.messages.isEmpty) return _buildEmpty();
      final msgs = ctrl.messages.where((m) => !m.isDisappeared).toList();
      final items = <_ChatItem>[];
      for (int i = 0; i < msgs.length; i++) {
        final msg = msgs[i];
        final prev = i > 0 ? msgs[i - 1] : null;
        final bool showDate =
            prev == null || !_isSameDay(prev.createdAt, msg.createdAt);
        if (showDate) items.add(_ChatItem.dateSep(msg.createdAt));
        final bool groupBreak = prev == null ||
            showDate ||
            prev.senderId != msg.senderId ||
            msg.createdAt.difference(prev.createdAt).inMinutes > 3;
        final next = i < msgs.length - 1 ? msgs[i + 1] : null;
        final bool isLast = next == null ||
            next.senderId != msg.senderId ||
            next.createdAt.difference(msg.createdAt).inMinutes > 3;
        items.add(_ChatItem.message(msg, isFirst: groupBreak, isLast: isLast));
      }
      return ListView.builder(
        controller: ctrl.scrollController,
        reverse: true,
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[items.length - 1 - i];
          if (item.isDateSep) return _DateLabel(date: item.date!);
          return _MessageBubble(
              msg: item.msg!,
              ctrl: ctrl,
              isFirst: item.isFirst,
              isLast: item.isLast);
        },
      );
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildShimmer() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, i) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.border,
        child: Align(
          alignment: i.isEven ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
              width: 140 + (i * 20.0).clamp(0.0, 100.0),
              height: 38,
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16))),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.chat_bubble_outline_rounded,
          size: 44, color: AppColors.textMuted),
      SizedBox(height: 12),
      Text('Dis bonjour !',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary)),
      SizedBox(height: 4),
      Text('Commence la conversation',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
    ]));
  }
}

class _ChatItem {
  final MessageModel? msg;
  final DateTime? date;
  final bool isDateSep;
  final bool isFirst;
  final bool isLast;
  const _ChatItem._(
      {this.msg,
      this.date,
      this.isDateSep = false,
      this.isFirst = true,
      this.isLast = true});
  factory _ChatItem.message(MessageModel m,
          {bool isFirst = true, bool isLast = true}) =>
      _ChatItem._(msg: m, isFirst: isFirst, isLast: isLast);
  factory _ChatItem.dateSep(DateTime d) =>
      _ChatItem._(date: d, isDateSep: true);
}

// ═══════════════════════════════════════════════════════════════════
//  DATE LABEL
// ═══════════════════════════════════════════════════════════════════

class _DateLabel extends StatelessWidget {
  final DateTime date;
  const _DateLabel({required this.date});
  String _label() {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    const mois = [
      'jan',
      'fév',
      'mars',
      'avr',
      'mai',
      'juin',
      'juil',
      'août',
      'sep',
      'oct',
      'nov',
      'déc'
    ];
    return '${date.day} ${mois[date.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
          child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
        child: Text(_label(),
            style: TextStyle(
                fontSize: 11,
                color: AppColors.textMuted,
                fontWeight: FontWeight.w500)),
      )),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _MessageBubble extends StatelessWidget {
  final MessageModel msg;
  final ConversationController ctrl;
  final bool isFirst;
  final bool isLast;
  const _MessageBubble(
      {required this.msg,
      required this.ctrl,
      this.isFirst = true,
      this.isLast = true});

  @override
  Widget build(BuildContext context) {
    final isMine = msg.senderId == ctrl.myId;
    final h = msg.createdAt.hour.toString().padLeft(2, '0');
    final m = msg.createdAt.minute.toString().padLeft(2, '0');
    return GestureDetector(
      onLongPress: () => ctrl.showMessageOptions(context, msg),
      child: Padding(
        padding: EdgeInsets.only(
            top: isFirst ? 4 : 1,
            bottom: isLast ? 4 : 1,
            left: isMine ? 56 : 4,
            right: isMine ? 4 : 56),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment:
                  isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMine) ...[
                  SizedBox(
                      width: 30,
                      child: isLast
                          ? _Avatar(
                              name: ctrl.conversation.userName,
                              size: 28,
                              photoUrl: ctrl.conversation.userPhotoUrl)
                          : const SizedBox()),
                  const SizedBox(width: 4),
                ],
                Flexible(
                    child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (msg.storyReply != null)
                      _StoryReplyPreview(
                          storyReply: msg.storyReply!, isMine: isMine),
                    if (msg.replyTo != null && msg.storyReply == null)
                      _ReplyPreview(
                          replyTo: msg.replyTo!, isMine: isMine, ctrl: ctrl),
                    _buildContent(isMine, context),
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$h:$m',
                          style: TextStyle(
                              fontSize: 10, color: AppColors.textMuted)),
                      if (isMine) ...[
                        const SizedBox(width: 3),
                        // ✅ Fix 4 : passer lastReadAt pour "Lu HH:MM"
                        Obx(() => _StatusIcon(
                            status: msg.status, readAt: ctrl.lastReadAt.value)),
                      ],
                    ]),
                  ],
                )),
              ],
            ),
            if (msg.hasReactions) _ReactionsRow(msg: msg, ctrl: ctrl),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isMine, BuildContext context) {
    switch (msg.type) {
      case MessageType.snap:
        return _SnapBubble(
            msg: msg,
            isMine: isMine,
            ctrl: ctrl,
            onTap: () => ctrl.openSnap(msg));
      case MessageType.audio:
        return _AudioBubble(msg: msg, isMine: isMine, ctrl: ctrl);
      case MessageType.image:
        return _MediaBubble(msg: msg, isMine: isMine, isVideo: false);
      case MessageType.location:
        return _LocationBubble(msg: msg, isMine: isMine);
      case MessageType.annonceReply:
        return _AnnonceReplyBubble(msg: msg, isMine: isMine);
      default:
        return _TextBubble(
            msg: msg, isMine: isMine, isFirst: isFirst, isLast: isLast);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RÉACTIONS
// ═══════════════════════════════════════════════════════════════════

class _ReactionsRow extends StatelessWidget {
  final MessageModel msg;
  final ConversationController ctrl;
  const _ReactionsRow({required this.msg, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final entries =
        msg.reactions.entries.where((e) => e.value.isNotEmpty).toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3, left: 34),
      child: Wrap(
          spacing: 3,
          children: entries.map((entry) {
            final emoji = entry.key;
            final count = entry.value.length;
            final me = entry.value.contains(ctrl.myId);
            return GestureDetector(
              onTap: () => ctrl.toggleReaction(msg, emoji),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: me
                      ? AppColors.accent.withOpacity(0.1)
                      : AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: me
                          ? AppColors.accent.withOpacity(0.5)
                          : AppColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(emoji, style: const TextStyle(fontSize: 12)),
                  if (count > 1) ...[
                    const SizedBox(width: 3),
                    Text('$count',
                        style: TextStyle(
                            fontSize: 10,
                            color: me ? AppColors.accent : AppColors.textMuted,
                            fontWeight: FontWeight.w600))
                  ],
                ]),
              ),
            );
          }).toList()),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STORY / REPLY PREVIEW
// ═══════════════════════════════════════════════════════════════════

// ✅ MIS À JOUR — cadre agrandi + tap pour voir la story façon Snapchat
// (plein écran, nom de l'auteur, bouton retour) au lieu de rester
// statique dans la bulle de chat.
class _StoryReplyPreview extends StatelessWidget {
  final StoryReplyData storyReply;
  final bool isMine;
  const _StoryReplyPreview({required this.storyReply, required this.isMine});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _StoryReplyFullScreen(storyReply: storyReply),
          ),
        );
      },
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.68),
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withOpacity(0.1) : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border(
              left: BorderSide(
                  color: isMine ? Colors.white38 : AppColors.accent, width: 3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9), bottomLeft: Radius.circular(9)),
            child: SizedBox(
              // ✅ Cadre agrandi (56x72 au lieu de 40x50)
              width: 56,
              height: 72,
              child: Stack(fit: StackFit.expand, children: [
                CachedNetworkImage(
                    imageUrl: storyReply.storyPreviewUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        color: AppColors.surface,
                        child: const Icon(Icons.photo_camera_rounded,
                            color: Colors.white38, size: 18))),
                if (storyReply.storyIsVideo)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                        child: Icon(Icons.play_circle_fill_rounded,
                            color: Colors.white, size: 22)),
                  ),
              ]),
            ),
          ),
          Flexible(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(storyReply.storyIsVideo ? '🎬 Vidéo' : '📸 Photo',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isMine ? Colors.white70 : AppColors.accent)),
                  const SizedBox(height: 3),
                  Text(
                      storyReply.storyOwnerName.isNotEmpty
                          ? 'Story de ${storyReply.storyOwnerName}'
                          : 'Story',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.visibility_rounded,
                        size: 11, color: AppColors.textMuted),
                    const SizedBox(width: 3),
                    Text('Voir',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w600)),
                  ]),
                ]),
          )),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ NOUVEAU — VISIONNAGE DE LA STORY DEPUIS LE CHAT, FAÇON SNAPCHAT
//  Plein écran, nom de l'auteur en en-tête, bouton retour. On ne
//  rejoue pas la story originale (elle peut avoir expiré) : on
//  affiche l'aperçu conservé au moment de la réponse.
// ═══════════════════════════════════════════════════════════════════

class _StoryReplyFullScreen extends StatefulWidget {
  final StoryReplyData storyReply;
  const _StoryReplyFullScreen({required this.storyReply});

  @override
  State<_StoryReplyFullScreen> createState() => _StoryReplyFullScreenState();
}

class _StoryReplyFullScreenState extends State<_StoryReplyFullScreen> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.storyReply.storyIsVideo) {
      final ctrl = VideoPlayerController.networkUrl(
          Uri.parse(widget.storyReply.storyPreviewUrl));
      _videoCtrl = ctrl;
      ctrl.initialize().then((_) {
        if (!mounted) return;
        setState(() => _videoReady = true);
        ctrl.setLooping(true);
        ctrl.play();
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.storyReply;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        Center(
          child: story.storyIsVideo
              ? (_videoReady && _videoCtrl != null
                  ? AspectRatio(
                      aspectRatio: _videoCtrl!.value.aspectRatio,
                      child: VideoPlayer(_videoCtrl!))
                  : const CircularProgressIndicator(color: Colors.white))
              : CachedNetworkImage(
                  imageUrl: story.storyPreviewUrl,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image_rounded,
                          color: Colors.white38, size: 48)),
                ),
        ),
        // ── Dégradé + en-tête façon Snapchat ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(
                12, MediaQuery.of(context).padding.top + 8, 12, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCC000000), Colors.transparent],
              ),
            ),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                      color: Colors.black38,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  story.storyOwnerName.isNotEmpty
                      ? 'Story de ${story.storyOwnerName}'
                      : 'Story',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final MessageModel replyTo;
  final bool isMine;
  final ConversationController ctrl;
  const _ReplyPreview(
      {required this.replyTo, required this.isMine, required this.ctrl});
  String get _preview {
    switch (replyTo.type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.audio:
        return '🎤 Vocal';
      case MessageType.snap:
        return '📸 Snap';
      case MessageType.location:
        return '📍 Localisation';
      default:
        return replyTo.text ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReplyMine = replyTo.senderId == ctrl.myId;
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMine ? Colors.white.withOpacity(0.1) : AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(
                color: isMine ? Colors.white38 : AppColors.accent, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isReplyMine ? 'Vous' : ctrl.conversation.userName,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isMine ? Colors.white70 : AppColors.accent)),
        const SizedBox(height: 2),
        Text(_preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  TEXTE BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _TextBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine, isFirst, isLast;
  const _TextBubble(
      {required this.msg,
      required this.isMine,
      this.isFirst = true,
      this.isLast = true});
  @override
  Widget build(BuildContext context) {
    const r = Radius.circular(18);
    const rs = Radius.circular(5);
    final borderRadius = isMine
        ? BorderRadius.only(
            topLeft: r,
            topRight: isFirst ? r : rs,
            bottomLeft: r,
            bottomRight: isLast ? rs : rs)
        : BorderRadius.only(
            topLeft: isFirst ? r : rs,
            topRight: r,
            bottomLeft: isLast ? rs : rs,
            bottomRight: r);
    return Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          gradient: isMine ? AppColors.gradientPink : null,
          color: isMine ? null : AppColors.surface2,
          borderRadius: borderRadius),
      child: Text(msg.text ?? '',
          style: TextStyle(
              fontSize: 15,
              color: isMine ? Colors.white : AppColors.textPrimary,
              height: 1.35)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SNAP BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _SnapBubble extends StatefulWidget {
  final MessageModel msg;
  final bool isMine;
  final ConversationController ctrl;
  final VoidCallback onTap;
  const _SnapBubble(
      {required this.msg,
      required this.isMine,
      required this.ctrl,
      required this.onTap});
  @override
  State<_SnapBubble> createState() => _SnapBubbleState();
}

class _SnapBubbleState extends State<_SnapBubble> {
  int _countdown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.msg.isOpened && widget.msg.expiresAt != null) _startCountdown();
  }

  // ✅ FIX — le message devient "ouvert" APRÈS la création du widget
  // (openSnap met à jour isOpened/expiresAt) : on démarre alors le
  // compte à rebours, sinon "Snap expiré" s'affichait immédiatement.
  @override
  void didUpdateWidget(covariant _SnapBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final msg = widget.msg;
    if (msg.isOpened &&
        msg.expiresAt != null &&
        (!oldWidget.msg.isOpened ||
            oldWidget.msg.expiresAt != msg.expiresAt)) {
      _startCountdown();
    }
  }

  void _startCountdown() {
    if (widget.msg.expiresAt == null) return;
    _timer?.cancel(); // ✅ FIX — pas de double timer
    final rem = widget.msg.expiresAt!.difference(DateTime.now()).inSeconds;
    if (rem <= 0) return;
    // ✅ FIX — appelé depuis initState/didUpdateWidget, un build suit
    // toujours : affectation directe au lieu de setState.
    _countdown = rem;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final left = widget.msg.expiresAt!.difference(DateTime.now()).inSeconds;
      if (left <= 0) {
        t.cancel();
        if (mounted) setState(() => _countdown = 0);
        return;
      }
      if (mounted) setState(() => _countdown = left);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final hasPhoto = msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty;
    final isMine = widget.isMine;

    if (isMine) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
            gradient: AppColors.gradientPink,
            borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.auto_awesome_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 8),
          Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Snap envoyé',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(msg.isOpened ? 'Ouvert ✓' : 'En attente',
                    style: TextStyle(
                        fontSize: 10, color: Colors.white.withOpacity(0.7))),
              ]),
        ]),
      );
    }

    if (msg.isOpened && hasPhoto && _countdown > 0) {
      final urgent = _countdown <= 3;
      return Stack(children: [
        GestureDetector(
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      _PleinEcranMedia(url: msg.mediaUrl!, isVideo: false))),
          child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                  imageUrl: msg.mediaUrl!,
                  width: 210,
                  height: 260,
                  fit: BoxFit.cover)),
        ),
        Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: urgent ? Colors.red.withOpacity(0.85) : Colors.black54,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('${_countdown}s',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            )),
        Positioned(
            bottom: 8,
            left: 10,
            right: 10,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    value: _countdown / 10.0,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        urgent ? Colors.red : AppColors.accent3),
                    minHeight: 3))),
      ]);
    }

    if (!msg.isOpened && hasPhoto) {
      return GestureDetector(
        onTap: () {
          widget.onTap();
          Future.delayed(const Duration(milliseconds: 100), () {
            final ctx = Get.context;
            if (ctx == null) return;
            Navigator.push(
                ctx,
                MaterialPageRoute(
                    builder: (_) => _SnapPleinEcran(
                        url: msg.mediaUrl!,
                        snapDuration: msg.snapDurationSec ?? 10)));
          });
        },
        child: Container(
          width: 210,
          height: 85,
          decoration: BoxDecoration(
              gradient: AppColors.gradientPink,
              borderRadius: BorderRadius.circular(16)),
          child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.photo_camera_rounded, size: 26, color: Colors.white),
                SizedBox(height: 6),
                Text('Appuie pour voir',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text('Disparaît après ouverture',
                    style: TextStyle(fontSize: 10, color: Colors.white70)),
              ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.timer_off_rounded, size: 14, color: AppColors.textMuted),
        SizedBox(width: 6),
        Text('Snap expiré',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SNAP PLEIN ÉCRAN
// ═══════════════════════════════════════════════════════════════════

class _SnapPleinEcran extends StatefulWidget {
  final String url;
  final int snapDuration;
  const _SnapPleinEcran({required this.url, required this.snapDuration});
  @override
  State<_SnapPleinEcran> createState() => _SnapPleinEcranState();
}

class _SnapPleinEcranState extends State<_SnapPleinEcran> {
  late int _countdown;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _countdown = widget.snapDuration;
    if (_countdown > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        setState(() => _countdown--);
        if (_countdown <= 0) {
          t.cancel();
          if (mounted) Navigator.pop(context);
        }
      });
    } else {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _countdown <= 3 && _countdown > 0;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(
            child: CachedNetworkImage(
                imageUrl: widget.url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_rounded,
                        color: Colors.white38, size: 48)))),
        if (widget.snapDuration > 0)
          Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color:
                        urgent ? Colors.red.withOpacity(0.85) : Colors.black54,
                    borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.timer_rounded,
                      size: 14, color: urgent ? Colors.white : Colors.white70),
                  const SizedBox(width: 5),
                  Text('${_countdown}s',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: urgent ? Colors.white : Colors.white70)),
                ]),
              )),
        if (widget.snapDuration > 0)
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                  value: _countdown / widget.snapDuration,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      urgent ? Colors.red : AppColors.accent3),
                  minHeight: 4)),
        Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context))),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  MEDIA BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _MediaBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine, isVideo;
  const _MediaBubble(
      {required this.msg, required this.isMine, required this.isVideo});

  bool get _isVideoUrl {
    final url = msg.mediaUrl ?? '';
    return url.contains('.mp4') ||
        url.contains('.mov') ||
        url.contains('.avi') ||
        url.contains('video') ||
        isVideo;
  }

  @override
  Widget build(BuildContext context) {
    if (msg.mediaUrl == null || msg.mediaUrl!.isEmpty) return _fallback();
    return GestureDetector(
      onTap: () {
        final ctx = Get.context ?? context;
        Navigator.push(
            ctx,
            MaterialPageRoute(
                builder: (_) => _PleinEcranMedia(
                    url: msg.mediaUrl!, isVideo: _isVideoUrl)));
      },
      child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(children: [
            CachedNetworkImage(
                imageUrl: msg.mediaUrl!,
                width: 220,
                height: 220,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 100),
                memCacheWidth: 440,
                placeholder: (_, __) => Container(
                    width: 220,
                    height: 220,
                    color: AppColors.surface2,
                    child: Center(
                        child: CircularProgressIndicator(
                            color: AppColors.accent, strokeWidth: 2))),
                errorWidget: (_, __, ___) => _fallback()),
            if (_isVideoUrl)
              Positioned.fill(
                  child: Container(
                      color: Colors.black38,
                      child: const Center(
                          child: Icon(Icons.play_circle_filled_rounded,
                              color: Colors.white, size: 52)))),
          ])),
    );
  }

  Widget _fallback() => Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14), color: AppColors.surface2),
      child: const Center(
          child: Icon(Icons.broken_image_rounded,
              size: 36, color: Colors.white38)));
}

// ═══════════════════════════════════════════════════════════════════
//  PLEIN ÉCRAN MEDIA
// ═══════════════════════════════════════════════════════════════════

class _PleinEcranMedia extends StatefulWidget {
  final String url;
  final bool isVideo;
  const _PleinEcranMedia({required this.url, required this.isVideo});
  @override
  State<_PleinEcranMedia> createState() => _PleinEcranMediaState();
}

class _PleinEcranMediaState extends State<_PleinEcranMedia> {
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoCtrl = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      _videoCtrl!.initialize().then((_) {
        if (mounted) {
          setState(() => _videoReady = true);
          _videoCtrl!.play();
        }
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (widget.isVideo && _videoReady)
            IconButton(
              icon: Icon(
                  _videoCtrl!.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white),
              onPressed: () {
                setState(() {
                  _videoCtrl!.value.isPlaying
                      ? _videoCtrl!.pause()
                      : _videoCtrl!.play();
                });
              },
            ),
        ],
      ),
      body: Center(
          child: widget.isVideo
              ? (_videoReady && _videoCtrl != null
                  ? AspectRatio(
                      aspectRatio: _videoCtrl!.value.aspectRatio,
                      child: VideoPlayer(_videoCtrl!))
                  : const CircularProgressIndicator(color: Colors.white))
              : InteractiveViewer(
                  child: CachedNetworkImage(
                      imageUrl: widget.url,
                      fit: BoxFit.contain,
                      placeholder: (_, __) =>
                          const CircularProgressIndicator(color: Colors.white),
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.broken_image_rounded,
                          color: Colors.white38,
                          size: 48)))),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AUDIO BUBBLE
// ═══════════════════════════════════════════════════════════════════

class _AudioBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  final ConversationController ctrl;
  const _AudioBubble(
      {required this.msg, required this.isMine, required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final dur = msg.audioDurationSec ?? 0;
    final min = (dur ~/ 60).toString().padLeft(2, '0');
    final sec = (dur % 60).toString().padLeft(2, '0');
    return Obx(() {
      final isPlaying = ctrl.currentlyPlayingId.value == msg.id;
      return GestureDetector(
        onTap: () {
          if (msg.mediaUrl != null && msg.mediaUrl!.isNotEmpty)
            ctrl.playAudio(msg.mediaUrl!, msg.id);
        },
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              gradient: isMine ? AppColors.gradientPink : null,
              color: isMine ? null : AppColors.surface2,
              borderRadius: BorderRadius.circular(18)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.15)),
                child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white)),
            const SizedBox(width: 8),
            Flexible(child: _AudioWaveform(isPlaying: isPlaying)),
            const SizedBox(width: 8),
            Text('$min:$sec',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      );
    });
  }
}

class _AudioWaveform extends StatefulWidget {
  final bool isPlaying;
  const _AudioWaveform({required this.isPlaying});
  @override
  State<_AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<_AudioWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  final _h = [6.0, 12, 8, 16, 10, 18, 7, 20, 9, 15, 17, 8, 11, 14, 9, 7];
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => SizedBox(
              height: 20,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(_h.length, (i) {
                  final phase = (i / _h.length + _ctrl.value) % 1.0;
                  final h = widget.isPlaying
                      ? _h[i] * (0.4 + 0.6 * math.sin(phase * 2 * math.pi))
                      : _h[i] * 0.4;
                  return Container(
                      width: 2.5,
                      height: h.clamp(3.0, 18.0),
                      margin: const EdgeInsets.symmetric(horizontal: 0.8),
                      decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(widget.isPlaying ? 0.9 : 0.4),
                          borderRadius: BorderRadius.circular(1.5)));
                }),
              ),
            ));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ STATUS ICON — avec "Lu HH:MM"
// ═══════════════════════════════════════════════════════════════════

class _StatusIcon extends StatelessWidget {
  final MessageStatus status;
  final DateTime? readAt; // ✅ heure de lecture
  const _StatusIcon({required this.status, this.readAt});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
                strokeWidth: 1.5, color: AppColors.textMuted));
      case MessageStatus.sent:
        return Icon(Icons.check_rounded, size: 12, color: AppColors.textMuted);
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded,
            size: 12, color: AppColors.textMuted);
      case MessageStatus.read:
        // ✅ Affiche "Lu HH:MM" si on a l'heure, sinon double coche rose
        if (readAt != null) {
          final h = readAt!.hour.toString().padLeft(2, '0');
          final m = readAt!.minute.toString().padLeft(2, '0');
          return ShaderMask(
              shaderCallback: (b) => AppColors.gradientPink.createShader(b),
              child: Text('Lu $h:$m',
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600)));
        }
        return ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Icon(Icons.done_all_rounded,
                size: 12, color: Colors.white));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  LOCATION BUBBLE
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
//  LOCATION BUBBLE — design moderne façon Telegram/WhatsApp
// ═══════════════════════════════════════════════════════════════════

class _LocationBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _LocationBubble({required this.msg, required this.isMine});

  LatLng? _parseLatLng() {
    final c = msg.text ?? '';
    if (c.contains(',') && !c.startsWith('http')) {
      final p = c.split(',');
      if (p.length == 2) {
        final lat = double.tryParse(p[0].trim());
        final lng = double.tryParse(p[1].trim());
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }
    return null;
  }

  Future<void> _open(LatLng pt) async {
    final geoUri = Uri.parse(
        'geo:${pt.latitude},${pt.longitude}?q=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    final gUri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${pt.latitude},${pt.longitude}');
    if (await canLaunchUrl(gUri)) {
      await launchUrl(gUri, mode: LaunchMode.externalApplication);
    }
  }

  String _coordsLabel(LatLng pt) {
    return '${pt.latitude.toStringAsFixed(4)}, ${pt.longitude.toStringAsFixed(4)}';
  }

  @override
  Widget build(BuildContext context) {
    final pt = _parseLatLng();
    return Container(
      width: 240,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color:
                isMine ? AppColors.accent.withOpacity(0.35) : AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // ── Carte avec pin flottant ──
        GestureDetector(
          onTap: pt != null ? () => _open(pt) : null,
          child: SizedBox(
            height: 150,
            child: pt != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      FlutterMap(
                        options: MapOptions(
                            initialCenter: pt,
                            initialZoom: 15.5,
                            interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none)),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.vybestyle.zamu',
                          ),
                        ],
                      ),
                      // Léger voile pour unifier la carte avec le thème sombre
                      Container(color: Colors.black.withOpacity(0.12)),
                      // Pin central avec ombre douce, style goutte moderne
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.gradientPink,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withOpacity(0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.location_on_rounded,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withOpacity(0.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badge "en direct" discret en haut à gauche
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.my_location_rounded,
                                  size: 10, color: Colors.white),
                              const SizedBox(width: 4),
                              Text('Position',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: AppColors.surface,
                    child: Center(
                        child: Icon(Icons.map_outlined,
                            size: 32, color: AppColors.textMuted)),
                  ),
          ),
        ),

        // ── Footer avec infos + bouton ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withOpacity(0.12),
              ),
              child:
                  Icon(Icons.place_rounded, size: 16, color: AppColors.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Position partagée',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  if (pt != null) ...[
                    const SizedBox(height: 1),
                    Text(_coordsLabel(pt),
                        style: TextStyle(
                            fontSize: 10.5, color: AppColors.textMuted)),
                  ],
                ],
              ),
            ),
            if (pt != null)
              GestureDetector(
                onTap: () => _open(pt),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.directions_rounded,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    const Text('Itinéraire',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  INPUT BAR
// ═══════════════════════════════════════════════════════════════════

class _InputBar extends StatelessWidget {
  final ConversationController ctrl;
  const _InputBar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border, width: 0.5))),
      padding: EdgeInsets.fromLTRB(
          10, 8, 10, MediaQuery.of(context).viewInsets.bottom + 10),
      child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Obx(() => ctrl.replyToMessage.value != null
                ? _ReplyBar(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.isRecording.value
                ? _RecordingIndicator(ctrl: ctrl)
                : const SizedBox.shrink()),
            Obx(() => ctrl.showAttachMenu.value
                ? _AttachMenu(ctrl: ctrl)
                : const SizedBox.shrink()),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Obx(() => GestureDetector(
                    onTap: ctrl.toggleAttachMenu,
                    child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: ctrl.showAttachMenu.value
                                ? AppColors.gradientPink
                                : null,
                            color: ctrl.showAttachMenu.value
                                ? null
                                : AppColors.surface2,
                            border: Border.all(color: AppColors.border)),
                        child: Icon(
                            ctrl.showAttachMenu.value
                                ? Icons.close_rounded
                                : Icons.add_rounded,
                            size: 20,
                            color: Colors.white)),
                  )),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AppColors.border)),
                child: TextField(
                  controller: ctrl.textController,
                  style: TextStyle(
                      fontSize: 15, color: AppColors.textPrimary, height: 1.35),
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => ctrl.sendText(),
                  decoration: InputDecoration(
                      hintText: 'Message...',
                      hintStyle:
                          TextStyle(color: AppColors.textMuted, fontSize: 15),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
                ),
              )),
              const SizedBox(width: 8),
              Obx(() {
                final hasText = ctrl.inputText.value.trim().isNotEmpty;
                final isRec = ctrl.isRecording.value;
                return GestureDetector(
                  onTap: hasText ? ctrl.sendText : null,
                  onLongPressStart:
                      hasText ? null : (_) => ctrl.startRecording(),
                  onLongPressEnd: hasText ? null : (_) => ctrl.stopRecording(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: isRec ? 46 : 38,
                    height: isRec ? 46 : 38,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [AppColors.accent, AppColors.accent2]),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.accent
                                  .withOpacity(isRec ? 0.5 : 0.3),
                              blurRadius: isRec ? 14 : 7)
                        ]),
                    child: Icon(
                        hasText
                            ? Icons.send_rounded
                            : (isRec ? Icons.stop_rounded : Icons.mic_rounded),
                        size: 18,
                        color: Colors.white),
                  ),
                );
              }),
            ]),
          ])),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  REPLY BAR
// ═══════════════════════════════════════════════════════════════════

class _ReplyBar extends StatelessWidget {
  final ConversationController ctrl;
  const _ReplyBar({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    final msg = ctrl.replyToMessage.value!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: AppColors.accent, width: 3))),
      child: Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(msg.senderId == ctrl.myId ? 'Vous' : ctrl.conversation.userName,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent)),
          const SizedBox(height: 2),
          Text(_preview(msg),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ])),
        GestureDetector(
            onTap: ctrl.cancelReply,
            child: Icon(Icons.close_rounded,
                size: 16, color: AppColors.textMuted)),
      ]),
    );
  }

  String _preview(MessageModel msg) {
    switch (msg.type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.audio:
        return '🎤 Vocal';
      case MessageType.snap:
        return '📸 Snap';
      case MessageType.location:
        return '📍 Position';
      default:
        return msg.text ?? '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RECORDING INDICATOR
// ═══════════════════════════════════════════════════════════════════

class _RecordingIndicator extends StatefulWidget {
  final ConversationController ctrl;
  const _RecordingIndicator({required this.ctrl});
  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                        AppColors.error, Colors.transparent, _anim.value)))),
        const SizedBox(width: 8),
        Obx(() {
          final n = (widget.ctrl.recordingDb.value / 80.0).clamp(0.0, 1.0);
          return Row(
              children: List.generate(
                  8,
                  (i) => Container(
                      width: 2.5,
                      height: 4 + (i % 2 == 0 ? n : n * 0.6) * 14,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(2)))));
        }),
        const SizedBox(width: 8),
        Text('Enregistrement...',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const Spacer(),
        Obx(() {
          final s = widget.ctrl.recordingSeconds.value;
          return Text(
              '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600));
        }),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: widget.ctrl.cancelRecording,
            child: Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.textMuted)),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ATTACH MENU
// ═══════════════════════════════════════════════════════════════════

class _AttachMenu extends StatelessWidget {
  final ConversationController ctrl;
  const _AttachMenu({required this.ctrl});
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _AttachItem(
            icon: Icons.camera_alt_rounded,
            label: 'Caméra',
            color: AppColors.accent,
            onTap: () => _selectionnerEtEnvoyer(context, camera: true)),
        _AttachItem(
            icon: Icons.photo_library_rounded,
            label: 'Galerie',
            color: AppColors.accent2,
            onTap: () => _selectionnerEtEnvoyer(context, camera: false)),
        _AttachItem(
            icon: Icons.videocam_rounded,
            label: 'Vidéo',
            color: const Color(0xFF00B4DB),
            onTap: () => _selectionnerVideo(context)),
        _AttachItem(
            icon: Icons.location_on_rounded,
            label: 'Position',
            color: const Color(0xFFFFD93D),
            onTap: ctrl.envoyerLocalisation),
      ]),
    );
  }

  void _selectionnerEtEnvoyer(BuildContext context,
      {required bool camera}) async {
    ctrl.showAttachMenu.value = false;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85);
    if (picked == null) return;
    final ctx = Get.context;
    if (ctx == null) return;
    showModalBottomSheet(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _PreviewSheet(ctrl: ctrl, filePath: picked.path));
  }

  void _selectionnerVideo(BuildContext context) async {
    ctrl.showAttachMenu.value = false;
    final picker = ImagePicker();
    final picked = await picker.pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
    if (picked == null) return;
    final ctx = Get.context;
    if (ctx == null) return;
    showModalBottomSheet(
        context: ctx,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) =>
            _PreviewSheet(ctrl: ctrl, filePath: picked.path, isVideo: true));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  PREVIEW SHEET
// ═══════════════════════════════════════════════════════════════════

class _PreviewSheet extends StatefulWidget {
  final ConversationController ctrl;
  final String filePath;
  final bool isVideo;
  const _PreviewSheet(
      {required this.ctrl, required this.filePath, this.isVideo = false});
  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  bool _modeEphemere = false;
  SnapDuration _duree = SnapDuration.s10;
  bool _showDureePicker = false;
  bool _uploading = false;
  VideoPlayerController? _videoCtrl;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoCtrl = VideoPlayerController.file(File(widget.filePath));
      _videoCtrl!.initialize().then((_) {
        if (mounted) {
          setState(() => _videoReady = true);
          _videoCtrl!.setLooping(true);
          _videoCtrl!.play();
        }
      });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Container(
        height: size.height * 0.85,
        decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          Expanded(
              child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: widget.isVideo
                ? (_videoReady && _videoCtrl != null
                    ? AspectRatio(
                        aspectRatio: _videoCtrl!.value.aspectRatio,
                        child: VideoPlayer(_videoCtrl!))
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)))
                : Image.file(File(widget.filePath), fit: BoxFit.contain),
          )),
          if (_modeEphemere && _showDureePicker)
            Container(
                color: AppColors.surface,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text('Durée d\'affichage après ouverture',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted),
                          textAlign: TextAlign.center)),
                  ...SnapDuration.values.map((d) => InkWell(
                        onTap: () => setState(() {
                          _duree = d;
                          _showDureePicker = false;
                        }),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            child: Row(children: [
                              Expanded(
                                  child: Text(d.label,
                                      style: TextStyle(
                                          fontSize: 15,
                                          color: _duree == d
                                              ? AppColors.textPrimary
                                              : AppColors.textMuted,
                                          fontWeight: _duree == d
                                              ? FontWeight.w600
                                              : FontWeight.w400))),
                              if (_duree == d)
                                Icon(Icons.check_rounded,
                                    color: AppColors.accent, size: 18),
                            ])),
                      )),
                ])),
          Container(
            color: AppColors.surface,
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Row(children: [
              GestureDetector(
                onTap: () => setState(() {
                  _modeEphemere = !_modeEphemere;
                  if (_modeEphemere) _showDureePicker = true;
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _modeEphemere
                        ? AppColors.accent.withOpacity(0.15)
                        : AppColors.surface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _modeEphemere
                            ? AppColors.accent.withOpacity(0.5)
                            : AppColors.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_rounded,
                        size: 16,
                        color: _modeEphemere
                            ? AppColors.accent
                            : AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(_modeEphemere ? _duree.label : 'Éphémère',
                        style: TextStyle(
                            fontSize: 12,
                            color: _modeEphemere
                                ? AppColors.accent
                                : AppColors.textMuted,
                            fontWeight: FontWeight.w500)),
                    if (_modeEphemere) ...[
                      const SizedBox(width: 4),
                      GestureDetector(
                          onTap: () => setState(
                              () => _showDureePicker = !_showDureePicker),
                          child: Icon(
                              _showDureePicker
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: AppColors.accent)),
                    ],
                  ]),
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _uploading ? null : _envoyer,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      gradient: AppColors.gradientPink,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: AppColors.accent.withOpacity(0.4),
                            blurRadius: 12)
                      ]),
                  child: _uploading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: const [
                          Icon(Icons.send_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('Envoyer',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                        ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Future<void> _envoyer() async {
    setState(() => _uploading = true);
    try {
      final file = File(widget.filePath);
      final uid = widget.ctrl.myId;
      final ts = DateTime.now().millisecondsSinceEpoch;
      String storagePath, contentType, msgType, msgContent;
      if (widget.isVideo) {
        storagePath = 'snaps/$uid/video_$ts.mp4';
        contentType = 'video/mp4';
        msgType = 'image';
        msgContent = '🎬 Vidéo';
      } else if (_modeEphemere) {
        storagePath = 'snaps/$uid/snap_$ts.jpg';
        contentType = 'image/jpeg';
        msgType = 'snap';
        msgContent = '📸 Photo éphémère';
      } else {
        storagePath = 'snaps/$uid/photo_$ts.jpg';
        contentType = 'image/jpeg';
        msgType = 'image';
        msgContent = '📷 Photo';
      }
      await Supabase.instance.client.storage.from('snaps').upload(
          storagePath, file,
          fileOptions: FileOptions(upsert: true, contentType: contentType));
      final url = Supabase.instance.client.storage
          .from('snaps')
          .getPublicUrl(storagePath);
      // ✅ FIX — horodatages envoyés en UTC (timestamptz)
      final now = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client.from('messages').insert({
        'conversation_id': widget.ctrl.conversation.id,
        'sender_id': widget.ctrl.myId,
        'type': msgType,
        'content': msgContent,
        'media_url': url,
        'status': 'sent',
        'created_at': now,
        if (_modeEphemere && _duree.seconds != null)
          'snap_duration': _duree.seconds,
      });
      await Supabase.instance.client
          .from('conversations')
          .update({'updated_at': now}).eq('id', widget.ctrl.conversation.id);
      if (mounted) Get.back();
    } catch (e) {
      Get.snackbar('Erreur',
          e.toString().substring(0, e.toString().length.clamp(0, 100)),
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.error,
          colorText: Colors.white,
          duration: const Duration(seconds: 6));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ATTACH ITEM
// ═══════════════════════════════════════════════════════════════════

class _AttachItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachItem(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withOpacity(0.3))),
              child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color.withOpacity(0.9),
                  fontWeight: FontWeight.w500)),
        ]));
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ANNONCE REPLY BUBBLE — style WhatsApp statut
// ═══════════════════════════════════════════════════════════════════

class _AnnonceReplyBubble extends StatelessWidget {
  final MessageModel msg;
  final bool isMine;
  const _AnnonceReplyBubble({required this.msg, required this.isMine});

  String get _catEmoji {
    final cat = msg.annonceReply?.annonceCategorie ?? '';
    const m = {
      'rencontre': '💕',
      'amitie': '🤝',
      'sortie': '🎉',
      'voyage': '✈️',
    };
    return m[cat] ?? '📢';
  }

  @override
  Widget build(BuildContext context) {
    final reply = msg.annonceReply;
    final hasText = msg.text != null &&
        msg.text!.isNotEmpty &&
        msg.text != '📢 A répondu à une annonce';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // ── Preview annonce (comme WhatsApp statut) ──
          Container(
            decoration: BoxDecoration(
              color:
                  isMine ? Colors.white.withOpacity(0.12) : AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(
                  color: isMine ? Colors.white38 : AppColors.accent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Auteur annonce
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$_catEmoji ',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              reply?.annonceAuteur ?? 'Annonce',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color:
                                    isMine ? Colors.white70 : AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        // Titre
                        Text(
                          reply?.annonceTitre ?? 'Annonce',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color:
                                isMine ? Colors.white : AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Description
                        if (reply?.annonceDescription.isNotEmpty == true)
                          Text(
                            reply!.annonceDescription,
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  isMine ? Colors.white54 : AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ),
                // Miniature photo
                if (reply?.annonceMediaUrl != null &&
                    reply?.annonceIsVideo == false)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: reply!.annonceMediaUrl!,
                      width: 56,
                      height: 64,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  )
                else if (reply?.annonceIsVideo == true)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    child: Container(
                      width: 56,
                      height: 64,
                      color: Colors.white.withOpacity(0.08),
                      child: Center(
                        child: Icon(Icons.videocam_rounded,
                            color: AppColors.accent, size: 20),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Message texte en dessous (si présent) ──
          if (hasText)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: isMine ? AppColors.gradientPink : null,
                color: isMine ? null : AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                msg.text!,
                style: TextStyle(
                  fontSize: 14,
                  color: isMine ? Colors.white : AppColors.textPrimary,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  AVATAR
// ═══════════════════════════════════════════════════════════════════

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  final String? photoUrl;
  const _Avatar({required this.name, required this.size, this.photoUrl});
  @override
  Widget build(BuildContext context) {
    final palettes = [
      [const Color(0xFFFF6B6B), const Color(0xFFFECA57)],
      [const Color(0xFF48DBFB), const Color(0xFFFF9FF3)],
      [const Color(0xFFFF9F43), const Color(0xFFEE5A24)],
      [const Color(0xFFA29BFE), const Color(0xFF6C5CE7)],
      [const Color(0xFFFD79A8), const Color(0xFFE84393)],
      [const Color(0xFF55EFC4), const Color(0xFF00B894)],
    ];
    final idx = name.hashCode.abs() % palettes.length;
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                colors: palettes[idx],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)),
        child: Center(
            child: Text(letter,
                style: TextStyle(
                    fontSize: size * 0.4,
                    fontWeight: FontWeight.w700,
                    color: Colors.white))));
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
          child: CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_, __) => fallback,
              errorWidget: (_, __, ___) => fallback));
    }
    return fallback;
  }
}

// ═══════════════════════════════════════════════════════════════════
//  ✅ AVATAR AVEC ANNEAU DE STORY (en-tête de conversation)
// ═══════════════════════════════════════════════════════════════════

class _AvatarWithStoryRing extends StatelessWidget {
  final String userId;
  final String name;
  final String? photoUrl;
  final double size;

  const _AvatarWithStoryRing({
    required this.userId,
    required this.name,
    required this.photoUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (!Get.isRegistered<HomeController>()) {
      return _Avatar(name: name, size: size, photoUrl: photoUrl);
    }
    final homeCtrl = Get.find<HomeController>();

    return Obx(() {
      final hasStory = homeCtrl.userHasActiveStory(userId);
      final storySeen = homeCtrl.userStoryIsSeen(userId);

      final avatar = _Avatar(name: name, size: size, photoUrl: photoUrl);

      if (!hasStory) return avatar;

      return GestureDetector(
        onTap: () => _openStory(homeCtrl),
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: storySeen
                ? null
                : LinearGradient(
                    colors: [
                      AppColors.accent,
                      AppColors.accent2,
                      AppColors.accent3,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: storySeen ? AppColors.border : null,
          ),
          child: Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
            ),
            child: avatar,
          ),
        ),
      );
    });
  }

  void _openStory(HomeController homeCtrl) {
    final userStories = homeCtrl.storiesForUser(userId);
    if (userStories.isEmpty) return;
    Get.to(
      () => StoryViewerScreen(stories: userStories, initialIndex: 0),
      transition: Transition.fadeIn,
    );
    homeCtrl.markStoryAsSeen(userStories.first.id);
  }
}
