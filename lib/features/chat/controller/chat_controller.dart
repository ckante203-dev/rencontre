import 'dart:async';
import 'package:rencontre/core/services/avis_service.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_compress/video_compress.dart';
import 'package:rencontre/features/album/album_service.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/features/chat/model/message_model.dart';
import 'package:rencontre/features/chat/view/conversation_screen.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/widget/story_report_sheet.dart';

enum ChatFilter { all, unread, online, favoris, groupes, archives }

/// Profil trouvé par son nom d'utilisateur (recherche dans Messages).
class ProfilTrouve {
  final String id;
  final String name;
  final String username;
  final String? photoUrl;
  final bool enLigne;
  const ProfilTrouve(
      {required this.id,
      required this.name,
      required this.username,
      this.photoUrl,
      this.enLigne = false});
}

class ChatListController extends GetxController {
  final _service = SupabaseService();
  final RxList<ConversationModel> conversations = <ConversationModel>[].obs;
  final RxBool isLoading = true.obs;
  final Rx<ChatFilter> activeFilter = ChatFilter.all.obs;
  final RxBool isSearching = false.obs;
  final RxString searchQuery = ''.obs;
  // Profils Zamu trouvés par pseudo (même sans conversation)
  final RxList<ProfilTrouve> profilsTrouves = <ProfilTrouve>[].obs;
  final RxBool rechercheProfils = false.obs;
  int _rechercheNumero = 0;

  /// Pseudo tapé (sans « @ »), ou '' s'il est trop court pour chercher.
  String get pseudoCherche {
    final q = searchQuery.value.trim().replaceFirst(RegExp(r'^@+'), '');
    return q.length >= 3 ? q : '';
  }

  Future<void> _chercherProfils(String _) async {
    final q = pseudoCherche;
    final numero = ++_rechercheNumero;
    if (q.isEmpty) {
      profilsTrouves.clear();
      rechercheProfils.value = false;
      return;
    }
    rechercheProfils.value = true;
    try {
      final rows = await Supabase.instance.client
          .rpc('chercher_par_pseudo', params: {'p_q': q}) as List;
      if (numero != _rechercheNumero) return; // une recherche plus récente
      profilsTrouves.assignAll(rows.map((r) => ProfilTrouve(
            id: r['id'] as String,
            name: (r['name'] as String?) ?? 'Utilisateur',
            username: (r['username'] as String?) ?? '',
            photoUrl: r['photo_url'] as String?,
            enLigne: r['en_ligne'] == true,
          )));
    } catch (e) {
      debugPrint('chercher_par_pseudo : $e'); // script SQL 027 absent
      if (numero == _rechercheNumero) profilsTrouves.clear();
    } finally {
      if (numero == _rechercheNumero) rechercheProfils.value = false;
    }
  }
  RealtimeChannel? _channel;
  // Épinglées et « marquées non lues » : mémorisées sur cet appareil.
  final RxSet<String> pinnedIds = <String>{}.obs;
  final RxSet<String> nonLuesForcees = <String>{}.obs;
  // Conversations en sourdine (table conversation_sourdines).
  final RxSet<String> sourdineIds = <String>{}.obs;

  // Conversations archivées (enregistrées sur le téléphone). Une
  // conversation archivée revient dans la liste dès qu'un message arrive.
  late final RxSet<String> archivees = <String>{
    ...(GetStorage().read<List>('conv_archivees') ?? const [])
        .map((e) => e.toString())
  }.obs;

  void basculerArchive(ConversationModel conv) {
    archivees.contains(conv.id)
        ? archivees.remove(conv.id)
        : archivees.add(conv.id);
    try {
      GetStorage().write('conv_archivees', archivees.toList());
    } catch (_) {}
  }

  // Personnes qui masquent leurs lectures (pas de coche bleue chez moi)
  final RxSet<String> masquentLu = <String>{}.obs;

  Future<void> _chargerMasquentLu() async {
    final ids = conversations.map((c) => c.userId).toSet().toList();
    if (ids.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .inFilter('id', ids)
          .eq('lectures_masquees', true);
      masquentLu.assignAll((rows as List).map((r) => r['id'] as String));
    } catch (_) {} // colonne absente (SQL 054 pas encore passé)
  }

  bool _estArchivee(ConversationModel c) =>
      archivees.contains(c.id) && c.unreadCount == 0;
  final _box = GetStorage();
  String get _cleEpingles => 'chat_epingles_${myId ?? ''}';
  String get _cleNonLues => 'chat_non_lues_${myId ?? ''}';
  // ✅ NOUVEAU — expose l'ID de l'utilisateur courant pour que
  // chat_list_screen.dart puisse appeler msg.isMine(controller.myId)
  String? get myId => _service.currentUserId;

  // ✅ FIX Realtime — polling de secours + horodatage de la dernière sync
  Timer? _pollingTimer;
  Timer? _watchdogTimer;
  DateTime? _lastSyncAt;
  // ✅ FIX — état du canal Realtime, dernière resynchro complète, et
  // drapeau de fermeture (les callbacks de statut arrivant après
  // onClose ne doivent plus relancer de polling).
  bool _realtimeSubscribed = false;
  DateTime? _lastFullSyncAt;
  bool _closed = false;
  // ✅ FIX — nombre de non-lus déjà signalés "delivered" par conversation,
  // pour ne pas renvoyer la requête à chaque rechargement.
  final Map<String, int> _deliveredMarkedFor = {};

  int get totalUnread => conversations.fold(0, (sum, c) => sum + c.unreadCount);
  int get conversationsNonLues =>
      conversations.where((c) => c.unreadCount > 0).length;

  List<ConversationModel> get filteredConversations {
    List<ConversationModel> list;
    switch (activeFilter.value) {
      case ChatFilter.unread:
        list = conversations.where((c) => c.unreadCount > 0).toList();
        break;
      case ChatFilter.online:
        list = conversations.where((c) => c.isOnline).toList();
        break;
      case ChatFilter.favoris:
        // ⭐ Favoris privés (gérés par HomeController)
        final favoris = Get.isRegistered<HomeController>()
            ? Get.find<HomeController>().favoris
            : <String>{};
        list = conversations.where((c) => favoris.contains(c.userId)).toList();
        break;
      case ChatFilter.archives:
        list = conversations.where(_estArchivee).toList();
        break;
      case ChatFilter.all:
      case ChatFilter.groupes: // les groupes ont leur propre liste
        list = conversations.toList();
    }
    if (activeFilter.value != ChatFilter.archives) {
      list = list.where((c) => !_estArchivee(c)).toList();
    }
    final q = searchQuery.value.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((c) => c.userName.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  void setFilter(ChatFilter f) => activeFilter.value = f;

  @override
  void onInit() {
    super.onInit();
    pinnedIds.addAll(List<String>.from(_box.read<List>(_cleEpingles) ?? []));
    nonLuesForcees
        .addAll(List<String>.from(_box.read<List>(_cleNonLues) ?? []));
    loadConversations();
    _subscribeToMessages();
    // Recherche par pseudo : 400 ms après la dernière lettre tapée
    debounce(searchQuery, _chercherProfils,
        time: const Duration(milliseconds: 400));
  }

  Future<void> loadConversations({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    try {
      final uid = _service.currentUserId!;
      // Hors ligne : on affiche d'abord les conversations gardées en cache
      if (conversations.isEmpty) {
        try {
          final cache = GetStorage().read<List>('cache_conversations_$uid');
          if (cache != null && cache.isNotEmpty) {
            conversations.value = _convertir(
                cache.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
                uid);
            _sortConversations();
            if (!silent) isLoading.value = false;
          }
        } catch (_) {}
      }
      final data = await _service.fetchConversations();
      if (_closed) return; // ✅ FIX — contrôleur fermé entre-temps
      unawaited(_chargerSourdines(uid));
      try {
        GetStorage().write('cache_conversations_$uid', data.take(50).toList());
      } catch (_) {}
      conversations.value = _convertir(data, uid);
      _sortConversations();
      unawaited(_chargerMasquentLu());
      // ✅ FIX Realtime — on marque l'heure de la dernière synchro réussie
      _lastSyncAt = DateTime.now();
      _lastFullSyncAt = _lastSyncAt;
      // ✅ FIX — l'expéditeur doit voir "distribué" dès que la liste
      // reçoit ses messages (pas seulement à l'ouverture de la conv).
      _markDeliveredForUnread();
    } catch (e) {
      debugPrint('ChatListController error: $e');
    } finally {
      if (!silent) isLoading.value = false;
    }
    update();
  }

  /// Lignes de la base (ou du cache) → conversations affichées
  List<ConversationModel> _convertir(List<Map<String, dynamic>> data, String uid) {
      return data.map((row) {
        final isUser1 = row['user1_id'] == uid;
        final otherProfile = isUser1
            ? _extractProfile(row, 'user2')
            : _extractProfile(row, 'user1');
        final lastMsg = row['_last_message'] as Map<String, dynamic>?;
        var unread = (row['_unread_count'] as int?) ?? 0;
        if (unread == 0 && nonLuesForcees.contains(row['id'])) unread = 1;
        return ConversationModel(
          id: row['id'],
          userId: otherProfile['id'] ?? '',
          userName: otherProfile['name'] ?? 'Utilisateur',
          userPhotoUrl: otherProfile['photo_url'],
          // En ligne = vu il y a moins de 30 min (is_online seul peut
          // rester à true si l'app a été fermée brutalement).
          isOnline: SupabaseService.isReallyOnline(
              otherProfile['is_online'], otherProfile['last_seen']),
          unreadCount: unread,
          lastActivity: row['updated_at'] != null
              ? DateTime.tryParse(row['updated_at'])
              : null,
          isPinned: pinnedIds.contains(row['id']),
          flammeCompte: (row['flamme_compte'] as int?) ?? 0,
          flammeDernierJour:
              ConversationModel.jourDepuisBase(row['flamme_dernier_jour']),
          lastMessage: lastMsg != null
              ? MessageModel(
                  id: lastMsg['id'] ?? '',
                  senderId: lastMsg['sender_id'] ?? '',
                  text: lastMsg['content'],
                  type: _parseType(lastMsg['type']),
                  status: _parseStatus(lastMsg['status']),
                  createdAt: DateTime.tryParse(lastMsg['created_at'] ?? '') ??
                      DateTime.now(),
                  isOpened: lastMsg['is_opened'] ?? false,
                  audioDurationSec: lastMsg['audio_duration'],
                )
              : null,
        );
      })
          // ✅ Conversation supprimée de mon côté : cachée tant qu'aucun
          // nouveau message n'est arrivé depuis la suppression.
          .where((c) {
        final avant = ConversationController.historiqueEffaceAvant(c.id);
        if (avant == null) return true;
        final dernier = c.lastMessage?.createdAt;
        return dernier != null && dernier.isAfter(avant);
      }).toList();
  }

  void _sortConversations() {
    conversations.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return (b.lastActivity ?? DateTime(0))
          .compareTo(a.lastActivity ?? DateTime(0));
    });
  }

  // ✅ FIX — marque "delivered" (sans attendre, sans bloquer) les
  // messages reçus des conversations ayant des non-lus. Une requête
  // n'est renvoyée que si le nombre de non-lus a changé.
  void _markDeliveredForUnread() {
    for (final c in conversations) {
      if (c.unreadCount <= 0) {
        _deliveredMarkedFor.remove(c.id);
        continue;
      }
      if (_deliveredMarkedFor[c.id] == c.unreadCount) continue;
      _deliveredMarkedFor[c.id] = c.unreadCount;
      unawaited(_service.markMessagesAsDelivered(c.id));
    }
  }

  Future<void> _chargerSourdines(String uid) async {
    try {
      final rows = await Supabase.instance.client
          .from('conversation_sourdines')
          .select('conversation_id')
          .eq('user_id', uid);
      if (_closed) return;
      sourdineIds
        ..clear()
        ..addAll(rows.map((r) => r['conversation_id'].toString()));
    } catch (_) {}
  }

  /// Coupe / réactive les notifications d'une conversation.
  Future<void> basculerSourdine(ConversationModel conv) async {
    final uid = myId;
    if (uid == null) return;
    final activer = !sourdineIds.contains(conv.id);
    activer ? sourdineIds.add(conv.id) : sourdineIds.remove(conv.id);
    try {
      final db = Supabase.instance.client.from('conversation_sourdines');
      if (activer) {
        await db.upsert({'user_id': uid, 'conversation_id': conv.id});
      } else {
        await db.delete().eq('user_id', uid).eq('conversation_id', conv.id);
      }
      _snackInfo(activer
          ? 'Notifications coupées pour @userName'.trParams({'userName': conv.userName.toString()})
          : 'Notifications réactivées pour @userName'.trParams({'userName': conv.userName.toString()}));
    } catch (e) {
      debugPrint('basculerSourdine error: $e');
      activer ? sourdineIds.remove(conv.id) : sourdineIds.add(conv.id);
      _snackInfo('Impossible de modifier les notifications'.tr);
    }
  }

  void _snackInfo(String texte) => Get.snackbar(texte, '',
      titleText: Text(texte,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      messageText: const SizedBox.shrink(),
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface2,
      margin: const EdgeInsets.all(12),
      borderRadius: 14,
      duration: const Duration(seconds: 2));

  void togglePin(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx == -1) return;
    final nowPinned = !conv.isPinned;
    nowPinned ? pinnedIds.add(conv.id) : pinnedIds.remove(conv.id);
    _box.write(_cleEpingles, pinnedIds.toList());
    conversations[idx] = conv.copyWith(isPinned: nowPinned);
    _sortConversations();
    update();
  }

  // « En train d'écrire… » dans la liste : conversations où l'autre
  // écrit en ce moment (effacé après 5 s sans nouvelle frappe).
  final RxSet<String> convsQuiEcrivent = <String>{}.obs;
  final Map<String, Timer> _minuteursEcrit = {};

  void _surFrappe(Map<String, dynamic> record) {
    final convId = record['conversation_id'] as String?;
    final auteur = record['user_id'] as String?;
    if (convId == null || auteur == null || auteur == _service.currentUserId) {
      return;
    }
    _minuteursEcrit.remove(convId)?.cancel();
    if (record['is_typing'] == true) {
      convsQuiEcrivent.add(convId);
      _minuteursEcrit[convId] = Timer(const Duration(seconds: 5), () {
        _minuteursEcrit.remove(convId);
        convsQuiEcrivent.remove(convId);
      });
    } else {
      convsQuiEcrivent.remove(convId);
    }
  }

  // ✅ FIX Realtime — abonnement avec callback de statut, logs de debug,
  // fallback de polling automatique, et watchdog périodique.
  void _subscribeToMessages() {
    final uid = _service.currentUserId;
    if (uid == null) return;
    _channel = Supabase.instance.client
        .channel('chatlist:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) async {
            if (_closed) return; // ✅ FIX — contrôleur fermé
            final record = payload.newRecord;
            final senderId = record['sender_id'] as String?;
            final convId = record['conversation_id'] as String?;
            // ✅ Log de debug : confirme que le Realtime arrive bien
            debugPrint(
                '📨 [Realtime ChatList] Nouveau message — conv=$convId sender=$senderId');
            if (convId == null) return;
            if (senderId != uid) {
              _minuteursEcrit.remove(convId)?.cancel();
              convsQuiEcrivent.remove(convId);
            }
            final isMine = senderId == uid;
            final isConvOpen =
                Get.isRegistered<ConversationController>(tag: convId);
            // ✅ FIX — message reçu par la liste : l'expéditeur doit le
            // voir "distribué" (sans bloquer). Si la conversation est
            // ouverte, elle le passe déjà en "lu".
            if (!isMine && !isConvOpen) {
              unawaited(_service.markMessagesAsDelivered(convId));
            }
            final idx = conversations.indexWhere((c) => c.id == convId);
            if (idx != -1) {
              final c = conversations[idx];
              conversations.removeAt(idx);
              conversations.insert(
                  0,
                  // 🔥 série mise à jour tout de suite (comme le trigger SQL)
                  c.avecMessageAujourdhui().copyWith(
                    unreadCount: (!isMine && !isConvOpen)
                        ? c.unreadCount + 1
                        : c.unreadCount,
                    lastActivity: DateTime.now().toUtc(),
                    lastMessage: MessageModel(
                      id: record['id'] ?? '',
                      senderId: senderId ?? '',
                      text: record['content'],
                      type: _parseType(record['type']),
                      status: MessageStatus.sent,
                      createdAt: DateTime.now(),
                    ),
                  ));
              _sortConversations();
              update();
            } else {
              await loadConversations(silent: true);
            }
            _lastSyncAt = DateTime.now();
          },
        )
        // « En train d'écrire… » (RLS : seulement mes conversations)
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'typing_status',
          callback: (payload) {
            if (_closed) return;
            _surFrappe(payload.newRecord);
          },
        )
        .subscribe((status, [error]) {
      // ✅ FIX — après onClose (removeChannel déclenche "closed"), on
      // ignore les statuts : sinon un polling jamais annulé démarrait.
      if (_closed) return;
      // ✅ Log de debug : confirme l'état de la connexion Realtime
      debugPrint('🔌 [Realtime ChatList] status=$status error=$error');
      if (status == RealtimeSubscribeStatus.subscribed) {
        // Connexion OK : on arrête le polling de secours s'il tournait
        _realtimeSubscribed = true;
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _lastSyncAt = DateTime.now();
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _realtimeSubscribed = false;
        // ✅ Fallback : Realtime en panne, on repasse en polling
        _startPolling();
      }
    });

    // ✅ FIX — Watchdog allégé : la liste n'est resynchronisée toutes
    // les 20s QUE si le canal Realtime n'est pas abonné. Quand il l'est,
    // on garde seulement une resynchro de sécurité toutes les 2 minutes
    // (statuts lus/distribués, etc. non couverts par le canal).
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 20), (t) {
      if (_closed || !Get.isRegistered<ChatListController>()) {
        t.cancel();
        return;
      }
      final now = DateTime.now();
      final last = _lastSyncAt;
      final lastFull = _lastFullSyncAt;
      final staleWhileDown = !_realtimeSubscribed &&
          (last == null || now.difference(last).inSeconds > 15);
      final safetyDue =
          lastFull == null || now.difference(lastFull).inMinutes >= 2;
      if (staleWhileDown || safetyDue) {
        debugPrint('⏱️ [ChatList] Resynchronisation périodique de sécurité');
        loadConversations(silent: true);
      }
    });
  }

  // ✅ FIX Realtime — polling de secours (3s) si le canal tombe en panne
  void _startPolling() {
    if (_closed) return; // ✅ FIX — jamais après onClose
    if (_pollingTimer != null) return; // déjà en cours
    debugPrint('⚠️ [ChatList] Realtime indisponible → passage en polling (3s)');
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (_closed) {
        t.cancel();
        return;
      }
      await loadConversations(silent: true);
    });
  }

  void openConversation(ConversationModel conv) {
    _retirerNonLueForcee(conv.id);
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx != -1) {
      conversations[idx] = conv.copyWith(unreadCount: 0);
      update();
    }
    NotificationService.clearConversationNotifications(conv.id);
    Get.toNamed('/chat/conversation', arguments: conv);
  }

  void _retirerNonLueForcee(String convId) {
    if (nonLuesForcees.remove(convId)) {
      _box.write(_cleNonLues, nonLuesForcees.toList());
    }
  }

  /// « Marquer comme lu » : lu aussi côté serveur (l'expéditeur voit
  /// « Lu »). « Marquer comme non lu » : pastille gardée sur cet appareil
  /// jusqu'à la prochaine ouverture de la conversation.
  void toggleReadStatus(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx == -1) return;
    final c = conversations[idx];
    if (c.unreadCount > 0) {
      _retirerNonLueForcee(c.id);
      unawaited(_service.markMessagesAsRead(c.id));
      NotificationService.clearConversationNotifications(c.id);
    } else {
      nonLuesForcees.add(c.id);
      _box.write(_cleNonLues, nonLuesForcees.toList());
    }
    conversations[idx] = c.copyWith(unreadCount: c.unreadCount > 0 ? 0 : 1);
    update();
  }

  /// ✅ Supprime la conversation de MON côté seulement (comme WhatsApp) :
  /// avant, la ligne était effacée en base et l'autre personne perdait
  /// aussi tout l'historique. Les anciens messages restent masqués sur cet
  /// appareil ; la conversation revient si un nouveau message arrive.
  Future<void> deleteConversation(String convId) async {
    conversations.removeWhere((c) => c.id == convId);
    _retirerNonLueForcee(convId);
    if (pinnedIds.remove(convId)) _box.write(_cleEpingles, pinnedIds.toList());
    _box.write('chat_efface_$convId', DateTime.now().toIso8601String());
    update();
    unawaited(_service.markMessagesAsRead(convId));
    NotificationService.clearConversationNotifications(convId);
  }

  Map<String, dynamic> _extractProfile(
      Map<String, dynamic> row, String prefix) {
    final key = '${prefix}_profile';
    if (row[key] is Map) return row[key] as Map<String, dynamic>;
    return {
      'id': row['${prefix}_id'],
      'name': 'Utilisateur',
      'photo_url': null,
      'is_online': false
    };
  }

  MessageType _parseType(String? t) {
    switch (t) {
      case 'image':
        return MessageType.image;
      case 'snap':
        return MessageType.snap;
      case 'audio':
        return MessageType.audio;
      case 'location':
        return MessageType.location;
      default:
        return MessageType.text;
    }
  }

  MessageStatus _parseStatus(String? s) {
    switch (s) {
      case 'sending':
        return MessageStatus.sending;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.sent;
    }
  }

  @override
  void onClose() {
    // ✅ FIX — drapeau posé AVANT de fermer le canal : le statut
    // "closed" qui en résulte ne relance plus le polling.
    _closed = true;
    for (final t in _minuteursEcrit.values) {
      t.cancel();
    }
    _minuteursEcrit.clear();
    _pollingTimer?.cancel(); // ✅ FIX Realtime
    _pollingTimer = null;
    _watchdogTimer?.cancel(); // ✅ FIX Realtime
    _watchdogTimer = null;
    // ✅ FIX — retire réellement le canal du client Realtime
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel).catchError((_) => '');
    }
    super.onClose();
  }
}

// ══════════════════════════════════════════════════════════════════
//  CONVERSATION CONTROLLER
// ══════════════════════════════════════════════════════════════════

class ConversationController extends GetxController
    with WidgetsBindingObserver {
  final _service = SupabaseService();
  late ConversationModel conversation;

  final RxList<MessageModel> messages = <MessageModel>[].obs;
  final RxBool isLoading = false.obs;
  final ScrollController scrollController = ScrollController();
  final RxBool isRecording = false.obs;
  final RxBool showAttachMenu = false.obs;
  late TextEditingController textController;
  final RxString inputText = ''.obs;
  final Rx<MessageModel?> replyToMessage = Rx<MessageModel?>(null);
  // Message en cours de modification (le champ de saisie le contient)
  final Rx<MessageModel?> enModification = Rx<MessageModel?>(null);
  final RxBool isOtherOnline = false.obs;
  final RxBool isOtherTyping = false.obs;
  final RxBool isOtherRecording = false.obs; // « enregistre un vocal… »
  final RxBool autreVerifie = false.obs; // badge bleu dans l'en-tête
  final RxBool autreMasqueLu = false.obs; // pas de « Lu » (réglage Premium)
  /// Derniers messages de l'autre personne (20 au plus), datés, pour
  /// accompagner un signalement.
  String extraitPourSignalement() {
    String deux(int n) => n.toString().padLeft(2, '0');
    final siens = messages
        .where((m) => m.senderId == conversation.userId && !m.id.startsWith('temp_'))
        .toList();
    final derniers = siens.length > 20 ? siens.sublist(siens.length - 20) : siens;
    final lignes = [
      for (final m in derniers)
        '[${deux(m.createdAt.day)}/${deux(m.createdAt.month)} '
            '${deux(m.createdAt.hour)}:${deux(m.createdAt.minute)}] '
            '${m.type == MessageType.text ? (m.text ?? '') : '(${m.type.name})'}'
    ];
    final texte = 'Derniers messages de la personne signalée :\n${lignes.join('\n')}';
    return texte.length > 3000 ? texte.substring(texte.length - 3000) : texte;
  }

  // Messages programmés (table messages_programmes, envoyés par le serveur)
  final RxList<Map<String, dynamic>> programmes = <Map<String, dynamic>>[].obs;

  Future<void> chargerProgrammes() async {
    try {
      final rows = await Supabase.instance.client
          .from('messages_programmes')
          .select('id, content, envoyer_le')
          .eq('conversation_id', conversation.id)
          .eq('sender_id', myId)
          .order('envoyer_le');
      programmes.assignAll(List<Map<String, dynamic>>.from(rows as List));
    } catch (_) {} // table absente (SQL 053 pas encore passé)
  }

  /// Choisir le jour et l'heure, puis enregistrer le message à envoyer
  Future<void> programmerMessage(BuildContext context) async {
    final texte = textController.text.trim();
    if (texte.isEmpty) return;
    final maintenant = DateTime.now();
    final jour = await showDatePicker(
      context: context,
      initialDate: maintenant,
      firstDate: maintenant,
      lastDate: maintenant.add(const Duration(days: 30)),
      helpText: 'Envoyer le…'.tr,
    );
    if (jour == null || !context.mounted) return;
    final heure = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
          maintenant.add(const Duration(hours: 1))),
      helpText: 'À quelle heure ?'.tr,
    );
    if (heure == null) return;
    final quand =
        DateTime(jour.year, jour.month, jour.day, heure.hour, heure.minute);
    if (quand.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      _snackInfo('Choisis une heure dans le futur'.tr);
      return;
    }
    try {
      await Supabase.instance.client.from('messages_programmes').insert({
        'conversation_id': conversation.id,
        'sender_id': myId,
        'content': texte.substring(0, texte.length.clamp(0, 2000)),
        'envoyer_le': quand.toUtc().toIso8601String(),
      });
      textController.clear();
      inputText.value = '';
      final h = '${quand.hour.toString().padLeft(2, '0')}:${quand.minute.toString().padLeft(2, '0')}';
      _snackInfo('⏰ Message programmé le @j/@m à @h'.trParams({
        'j': quand.day.toString().padLeft(2, '0'),
        'm': quand.month.toString().padLeft(2, '0'),
        'h': h,
      }));
      chargerProgrammes();
    } catch (e) {
      debugPrint('Programmation impossible : $e');
      _snackInfo('Action impossible, réessaie'.tr);
    }
  }

  Future<void> annulerProgramme(String id) async {
    try {
      await Supabase.instance.client
          .from('messages_programmes')
          .delete()
          .eq('id', id);
      programmes.removeWhere((p) => p['id'] == id);
    } catch (_) {
      _snackInfo('Action impossible, réessaie'.tr);
    }
  }

  // Message épinglé en haut de la conversation (conversations.message_epingle_id)
  final RxnString epingleId = RxnString();
  final RxnString epingleTexte = RxnString();
  Timer? _vocalPing;
  // Dernière activité de l'autre (« vu à 14:32 » dans l'en-tête)
  final Rx<DateTime?> otherLastSeen = Rx<DateTime?>(null);
  final Rx<DateTime?> lastReadAt = Rx<DateTime?>(null);
  // ✅ Messages directs : limite de 3 messages tant que l'autre n'a pas
  // répondu (sans match), et blocage. Règles appliquées par le serveur ;
  // ces valeurs servent à prévenir l'utilisateur.
  static const int limiteSansReponse = 3;
  final RxBool limiteAtteinte = false.obs;
  final RxBool bloque = false.obs;
  bool _enAttenteDeReponse = false;

  // ─── Menu ⋮ de la conversation ───
  // Sourdine : lue par le serveur (table conversation_sourdines).
  final RxBool sourdine = false.obs;
  final RxBool sourdineEnCours = false.obs;
  // Fond d'écran et historique effacé : propres à cet appareil.
  final RxString fond = 'defaut'.obs;
  final Rx<DateTime?> effaceAvant = Rx<DateTime?>(null);
  final _box = GetStorage();
  String get _cleFond => 'chat_fond_${conversation.id}';
  String get _cleEfface => 'chat_efface_${conversation.id}';
  String get _cleMasques => 'chat_masques_${conversation.id}';
  // Messages supprimés « pour moi » : masqués sur cet appareil seulement.
  final RxSet<String> masques = <String>{}.obs;

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderOpen = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RxInt recordingSeconds = 0.obs;
  final RxDouble recordingDb = 0.0.obs;
  String? _recordingPath;
  final RxString currentlyPlayingId = ''.obs;
  // Vitesse des vocaux : 1× → 1,5× → 2× (comme WhatsApp)
  final RxDouble vitesseAudio = 1.0.obs;

  void changerVitesseAudio() {
    vitesseAudio.value = vitesseAudio.value == 1.0
        ? 1.5
        : vitesseAudio.value == 1.5
            ? 2.0
            : 1.0;
    if (currentlyPlayingId.value.isNotEmpty) {
      _audioPlayer.setPlaybackRate(vitesseAudio.value).catchError((_) {});
    }
  }

  String get vitesseAudioLabel =>
      vitesseAudio.value == 1.0 ? '1×' : vitesseAudio.value == 1.5 ? '1,5×' : '2×';
  Timer? _recordingSecondsTimer;
  Codec? _detectedCodec;
  String? _detectedExt;
  RealtimeChannel? _channel;
  RealtimeChannel? _presenceChannel;
  RealtimeChannel? _typingChannel;
  Timer? _typingTimer;
  Timer? _myTypingTimer;
  bool _isCurrentlyTyping = false;
  Timer? _pollingTimer;
  // ✅ Retire de l'écran les messages lus depuis plus de 24h (règle
  // éphémère), sans attendre leur suppression par le serveur.
  Timer? _expirationTimer;
  final _imagePicker = ImagePicker();
  // ✅ FIX — drapeau de fermeture : callbacks Realtime/polling ignorés
  // après onClose.
  bool _closed = false;
  // ✅ FIX — suffixe unique par instance pour les noms de canaux
  // Realtime : deux écrans de la même conversation (ancien en cours de
  // fermeture + nouveau) ne partagent plus le même topic, sinon le
  // désabonnement de l'ancien coupait le Realtime du nouveau.
  late final String _channelSuffix =
      '${identityHashCode(this)}_${DateTime.now().microsecondsSinceEpoch}';

  static const List<String> availableEmojis = [
    '❤️',
    '😂',
    '👍',
    '😮',
    '😢',
    '🔥'
  ];

  void init(ConversationModel conv) {
    conversation = conv;
    isOtherOnline.value = conv.isOnline;
    fond.value = _box.read<String>(_cleFond) ?? 'defaut';
    final efface = _box.read<String>(_cleEfface);
    effaceAvant.value = efface == null ? null : DateTime.tryParse(efface);
    masques.addAll(List<String>.from(_box.read<List>(_cleMasques) ?? []));
    _audioPlayer.onPlayerComplete.listen((_) => currentlyPlayingId.value = '');
    // Recalcule la limite dès que la liste des messages change
    ever(messages, (_) => _majLimite());
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_closed) return; // ✅ FIX — écran déjà fermé
      _loadMessages();
      _subscribeToMessages();
      _subscribeToPresence(conv.userId);
      _subscribeToTyping(conv.id, conv.userId);
      _markReadAndUpdateBadge(conv.id);
      _fetchOtherOnlineStatus(conv.userId);
      _chargerStatutConversation();
      _chargerSourdine();
      _chargerEpingle();
      chargerProgrammes();
    });
  }

  Future<void> _chargerEpingle() async {
    try {
      final c = await Supabase.instance.client
          .from('conversations')
          .select('message_epingle_id')
          .eq('id', conversation.id)
          .maybeSingle();
      final id = c?['message_epingle_id'] as String?;
      if (id == null || _closed) return;
      final m = await Supabase.instance.client
          .from('messages')
          .select('content')
          .eq('id', id)
          .maybeSingle();
      epingleId.value = id;
      epingleTexte.value = m?['content'] as String?;
    } catch (_) {} // colonne absente (SQL 051 pas encore passé)
  }

  /// Épingle (ou désépingle avec null) un message pour les deux personnes
  Future<void> epingler(MessageModel? msg) async {
    final ancienId = epingleId.value, ancienTexte = epingleTexte.value;
    epingleId.value = msg?.id;
    epingleTexte.value = msg?.text;
    try {
      await Supabase.instance.client
          .from('conversations')
          .update({'message_epingle_id': msg?.id}).eq('id', conversation.id);
    } catch (e) {
      debugPrint('Épinglage impossible : $e');
      epingleId.value = ancienId;
      epingleTexte.value = ancienTexte;
      _snackInfo('Action impossible, réessaie'.tr);
    }
  }

  /// Date jusqu'à laquelle l'historique a été effacé sur cet appareil.
  static DateTime? historiqueEffaceAvant(String convId) {
    final v = GetStorage().read<String>('chat_efface_$convId');
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Messages affichés : hors messages expirés et historique effacé.
  bool estVisible(MessageModel m) {
    if (m.isDisappeared || masques.contains(m.id)) return false;
    final avant = effaceAvant.value;
    return avant == null || m.createdAt.isAfter(avant);
  }

  Future<void> _chargerSourdine() async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('conversation_sourdines')
          .select('user_id')
          .eq('user_id', uid)
          .eq('conversation_id', conversation.id)
          .maybeSingle();
      if (!_closed) sourdine.value = row != null;
    } catch (_) {}
  }

  Future<void> basculerSourdine() async {
    final uid = _service.currentUserId;
    if (uid == null || sourdineEnCours.value) return;
    final activer = !sourdine.value;
    sourdine.value = activer;
    sourdineEnCours.value = true;
    try {
      final db = Supabase.instance.client.from('conversation_sourdines');
      if (activer) {
        await db.upsert({'user_id': uid, 'conversation_id': conversation.id});
      } else {
        await db
            .delete()
            .eq('user_id', uid)
            .eq('conversation_id', conversation.id);
      }
      if (Get.isRegistered<ChatListController>()) {
        final ids = Get.find<ChatListController>().sourdineIds;
        activer ? ids.add(conversation.id) : ids.remove(conversation.id);
      }
      _snackInfo(activer
          ? 'Notifications coupées pour cette conversation'.tr
          : 'Notifications réactivées'.tr);
    } catch (e) {
      debugPrint('basculerSourdine error: $e');
      sourdine.value = !activer;
      _snackInfo('Impossible de modifier les notifications'.tr);
    } finally {
      sourdineEnCours.value = false;
    }
  }

  void choisirFond(String id) {
    fond.value = id;
    if (id == 'defaut') {
      _box.remove(_cleFond);
    } else {
      _box.write(_cleFond, id);
    }
  }

  /// Masque, sur cet appareil, tous les messages reçus ou envoyés jusqu'ici.
  void effacerHistorique() {
    final maintenant = DateTime.now();
    effaceAvant.value = maintenant;
    _box.write(_cleEfface, maintenant.toIso8601String());
    cancelReply();
    _snackInfo('Historique effacé sur cet appareil'.tr);
  }

  /// Signale un message reçu : motif, puis enregistrement dans `reports`
  /// avec une copie du contenu (le message disparaît après lecture).
  Future<void> signalerMessage(MessageModel msg) async {
    final uid = _service.currentUserId;
    if (uid == null || msg.senderId == uid) return;
    final raison = await choisirMotifSignalement('Pourquoi signaler ce message ?'.tr);
    if (raison == null) return;
    final db = Supabase.instance.client.from('reports');
    final base = {
      'reporter_id': uid,
      'reported_id': msg.senderId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      try {
        await db.insert({
          ...base,
          'reason': raison,
          'message_id': msg.id,
          if ((msg.text ?? '').isNotEmpty) 'message_contenu': msg.text,
          if ((msg.mediaUrl ?? '').isNotEmpty) 'message_media_url': msg.mediaUrl,
        });
      } on PostgrestException catch (e) {
        if (e.code == '23505') rethrow;
        // Colonnes message_* absentes (script 000014 pas appliqué) :
        // signalement enregistré sur le profil.
        await db.insert({...base, 'reason': 'Message : $raison (${msg.id})'});
      }
      _snackInfo('Signalement envoyé. Merci, notre équipe va l\'examiner.'.tr);
    } on PostgrestException catch (e) {
      _snackInfo(e.code == '23505'
          ? 'Tu as déjà signalé ce message'.tr
          : 'Impossible d\'envoyer le signalement'.tr);
    } catch (_) {
      _snackInfo('Impossible d\'envoyer le signalement'.tr);
    }
  }

  void _snackInfo(String texte) => Get.snackbar(texte, '',
      titleText: Text(texte,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      messageText: const SizedBox.shrink(),
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface2,
      margin: const EdgeInsets.all(12),
      borderRadius: 14,
      duration: const Duration(seconds: 2));

  /// Statut de la conversation : en attente de réponse (sans match) ?
  Future<void> _chargerStatutConversation() async {
    try {
      final c = await Supabase.instance.client
          .from('conversations')
          .select('request_status, initiated_by')
          .eq('id', conversation.id)
          .maybeSingle();
      if (c == null || _closed) return;
      var enAttente = c['request_status'] == 'pending' &&
          c['initiated_by'] == myId;
      if (enAttente) {
        try {
          final match = await Supabase.instance.client.rpc('ont_un_match',
              params: {'a': myId, 'b': conversation.userId});
          if (match == true) enAttente = false;
        } catch (_) {}
      }
      _enAttenteDeReponse = enAttente;
      _majLimite();
    } catch (_) {}
  }

  void _majLimite() {
    if (!_enAttenteDeReponse) {
      limiteAtteinte.value = false;
      return;
    }
    final mesMessages = messages
        .where((m) => m.senderId == myId && !m.id.startsWith('temp_'))
        .length;
    limiteAtteinte.value = mesMessages >= limiteSansReponse;
  }

  /// À appeler avant chaque envoi : prévient au lieu d'envoyer pour rien.
  bool peutEnvoyer() {
    if (bloque.value) {
      _snackRefus('Tu ne peux plus écrire à cette personne'.tr);
      return false;
    }
    if (limiteAtteinte.value) {
      _snackRefus('Attends sa réponse pour envoyer d\'autres messages'.tr);
      return false;
    }
    return true;
  }

  /// Erreur renvoyée par le serveur (limite ou blocage) : message clair.
  bool gererRefusServeur(Object e) {
    final t = e.toString();
    if (t.contains('limite_sans_reponse')) {
      limiteAtteinte.value = true;
      _snackRefus('Attends sa réponse pour envoyer d\'autres messages'.tr);
      return true;
    }
    if (t.contains('bloque')) {
      bloque.value = true;
      _snackRefus('Tu ne peux plus écrire à cette personne'.tr);
      return true;
    }
    return false;
  }

  void _snackRefus(String texte) => Get.snackbar('Message non envoyé'.tr, texte,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary);

  Future<void> _fetchOtherOnlineStatus(String otherUserId) async {
    try {
      Map<String, dynamic>? data;
      try {
        data = await Supabase.instance.client
            .from('profiles')
            .select('is_online, last_seen, est_verifie, lectures_masquees')
            .eq('id', otherUserId)
            .maybeSingle();
      } on PostgrestException {
        // Colonne lectures_masquees absente (SQL 054 pas encore passé)
        data = await Supabase.instance.client
            .from('profiles')
            .select('is_online, last_seen, est_verifie')
            .eq('id', otherUserId)
            .maybeSingle();
      }
      if (data != null) {
        autreVerifie.value = data['est_verifie'] == true;
        autreMasqueLu.value = data['lectures_masquees'] == true;
        isOtherOnline.value = SupabaseService.isReallyOnline(
            data['is_online'], data['last_seen']);
        otherLastSeen.value =
            DateTime.tryParse('${data['last_seen'] ?? ''}')?.toLocal();
      }
    } catch (_) {}
  }

  static const List<_CodecOption> _codecCandidates = [
    _CodecOption(Codec.aacMP4, '.mp4', 'audio/mp4'),
    _CodecOption(Codec.aacADTS, '.aac', 'audio/aac'),
    _CodecOption(Codec.opusOGG, '.ogg', 'audio/ogg'),
  ];

  Future<bool> _detectCodec(FlutterSoundRecorder recorder) async {
    if (_detectedCodec != null) return true;
    final dir = await getTemporaryDirectory();
    for (final candidate in _codecCandidates) {
      try {
        final testPath = '${dir.path}/test_codec${candidate.ext}';
        await recorder.startRecorder(toFile: testPath, codec: candidate.codec);
        await Future.delayed(const Duration(milliseconds: 200));
        await recorder.stopRecorder();
        _detectedCodec = candidate.codec;
        _detectedExt = candidate.ext;
        try {
          File(testPath).deleteSync();
        } catch (_) {}
        return true;
      } catch (_) {}
    }
    return false;
  }

  void onTextChanged() {
    inputText.value = textController.text;
    _handleMyTyping();
  }

  void _handleMyTyping() {
    if (textController.text.trim().isNotEmpty && !_isCurrentlyTyping) {
      _isCurrentlyTyping = true;
      _updateTypingStatus(true);
    }
    _myTypingTimer?.cancel();
    _myTypingTimer = Timer(const Duration(seconds: 2), () {
      if (_isCurrentlyTyping) {
        _isCurrentlyTyping = false;
        _updateTypingStatus(false);
      }
    });
  }

  Future<void> _updateTypingStatus(bool typing, {String? activite, bool avecActivite = false}) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('typing_status').upsert({
        'conversation_id': conversation.id,
        'user_id': uid,
        'is_typing': typing,
        // colonne « activite » (SQL 051) envoyée seulement pour le vocal
        if (avecActivite) 'activite': activite,
        // ✅ FIX — horodatage envoyé en UTC (timestamptz)
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  void _subscribeToTyping(String convId, String otherUserId) {
    _typingChannel = Supabase.instance.client
        .channel('typing:$convId:$_channelSuffix') // ✅ FIX — topic unique
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'typing_status',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) {
            final record = payload.newRecord;
            if (record['user_id'] != otherUserId) return;
            final typing = record['is_typing'] == true;
            isOtherRecording.value = typing && record['activite'] == 'vocal';
            if (typing) {
              isOtherTyping.value = true;
              _typingTimer?.cancel();
              _typingTimer = Timer(const Duration(seconds: 4), () {
                isOtherTyping.value = false;
                isOtherRecording.value = false;
              });
            } else {
              _typingTimer?.cancel();
              isOtherTyping.value = false;
            }
          },
        )
        .subscribe();
  }

  Future<void> toggleReaction(MessageModel msg, String emoji) async {
    final uid = _service.currentUserId!;
    final currentReactions = Map<String, List<String>>.from(
        msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))));
    final users = currentReactions[emoji] ?? [];
    if (users.contains(uid)) {
      users.remove(uid);
      if (users.isEmpty) currentReactions.remove(emoji);
    } else {
      users.add(uid);
      currentReactions[emoji] = users;
    }
    // ✅ FIX — intention de CET utilisateur (ajout ou retrait)
    final adding = users.contains(uid);
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1)
      messages[idx] = messages[idx].copyWith(reactions: currentReactions);
    try {
      // ✅ FIX — relit les réactions les plus récentes juste avant
      // d'écrire et n'applique QUE le changement de cet utilisateur :
      // on n'écrase plus les réactions posées entre-temps par l'autre.
      final latestRow = await Supabase.instance.client
          .from('messages')
          .select('reactions')
          .eq('id', msg.id)
          .maybeSingle();
      final rawLatest =
          latestRow?['reactions'] as Map<String, dynamic>? ?? const {};
      final merged = <String, List<String>>{
        for (final e in rawLatest.entries)
          e.key: List<String>.from(e.value as List? ?? []),
      };
      final latestUsers = merged[emoji] ?? <String>[];
      latestUsers.remove(uid);
      if (adding) latestUsers.add(uid);
      if (latestUsers.isEmpty) {
        merged.remove(emoji);
      } else {
        merged[emoji] = latestUsers;
      }
      await Supabase.instance.client
          .from('messages')
          .update({'reactions': merged}).eq('id', msg.id);
      final i = messages.indexWhere((m) => m.id == msg.id);
      if (i != -1) messages[i] = messages[i].copyWith(reactions: merged);
    } catch (_) {
      final i = messages.indexWhere((m) => m.id == msg.id);
      if (i != -1) messages[i] = messages[i].copyWith(reactions: msg.reactions);
    }
  }

  void _subscribeToPresence(String otherUserId) {
    _presenceChannel = Supabase.instance.client
        .channel('presence:$otherUserId:$_channelSuffix') // ✅ FIX — topic unique
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: otherUserId,
          ),
          callback: (payload) {
            final r = payload.newRecord;
            isOtherOnline.value =
                SupabaseService.isReallyOnline(r['is_online'], r['last_seen']);
            final vu = DateTime.tryParse('${r['last_seen'] ?? ''}')?.toLocal();
            if (vu != null) otherLastSeen.value = vu;
          },
        )
        .subscribe();
  }

  /// Message reçu pendant que l'appli est en arrière-plan (écran verrouillé
  /// sur la conversation) : marqué lu seulement au retour.
  bool _lectureEnAttente = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _lectureEnAttente && !_closed) {
      _lectureEnAttente = false;
      _markReadAndUpdateBadge(conversation.id);
    }
  }

  /// ✅ Avant, un message reçu écran éteint passait « Lu » chez l'expéditeur.
  void _marquerLuSiVisible(String convId) {
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _markReadAndUpdateBadge(convId);
    } else {
      _lectureEnAttente = true;
    }
  }

  void _markReadAndUpdateBadge(String convId) {
    _service.markMessagesAsRead(convId);
    NotificationService.clearConversationNotifications(convId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!Get.isRegistered<ChatListController>()) return;
      final listCtrl = Get.find<ChatListController>();
      final idx = listCtrl.conversations.indexWhere((c) => c.id == convId);
      if (idx != -1) {
        final c = listCtrl.conversations[idx];
        listCtrl.conversations[idx] = c.copyWith(unreadCount: 0);
        listCtrl.update();
      }
    });
  }

  void setReplyTo(MessageModel? msg) {
    replyToMessage.value = msg;
    if (msg != null) {
      Future.delayed(const Duration(milliseconds: 100), () {
        textController.selection = TextSelection.fromPosition(
            TextPosition(offset: textController.text.length));
      });
    }
  }

  void cancelReply() => replyToMessage.value = null;

  Future<void> _loadMessages() async {
    isLoading.value = true;
    try {
      final data = await _service.fetchMessages(conversation.id);
      final rawMessages = data.map((row) => _rowToMessage(row)).toList();
      final msgById = {for (final m in rawMessages) m.id: m};
      messages.value = data.map((row) {
        final msg = _rowToMessage(row);
        final replyId = row['reply_to_id'] as String?;
        if (replyId != null && msgById.containsKey(replyId)) {
          return msg.copyWith(replyTo: msgById[replyId]);
        }
        return msg;
      }).toList();
      _updateLastReadAt();
    } catch (e) {
      debugPrint('Load messages error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void _updateLastReadAt() {
    final myMsgs = messages
        .where((m) => m.senderId == myId && m.status == MessageStatus.read)
        .toList();
    if (myMsgs.isNotEmpty) {
      myMsgs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      lastReadAt.value = myMsgs.first.createdAt;
    }
  }

  void _subscribeToMessages() {
    final convId = conversation.id;
    _channel = Supabase.instance.client
        .channel('conv_screen:$convId:$_channelSuffix') // ✅ FIX — topic unique
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) async {
            if (_closed) return; // ✅ FIX — contrôleur fermé
            final record = payload.newRecord;
            MessageModel? replyTo;
            final replyId = record['reply_to_id'] as String?;
            if (replyId != null) {
              replyTo = messages.firstWhereOrNull((m) => m.id == replyId);
              if (replyTo == null) {
                try {
                  final rd = await Supabase.instance.client
                      .from('messages')
                      .select()
                      .eq('id', replyId)
                      .maybeSingle();
                  if (rd != null) replyTo = _rowToMessage(rd);
                } catch (_) {}
              }
            }
            final newMsg = _rowToMessage(record, replyTo: replyTo);
            messages.removeWhere((m) =>
                m.id.startsWith('temp_') &&
                m.text == newMsg.text &&
                m.senderId == newMsg.senderId);
            if (!messages.any((m) => m.id == newMsg.id)) {
              messages.add(newMsg);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (scrollController.hasClients) {
                  scrollController.animateTo(0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut);
                }
              });
              if (newMsg.senderId != myId) {
                HapticFeedback.lightImpact();
                try {
                  final player = AudioPlayer();
                  await player.play(AssetSource('sounds/message_sound.mp3'));
                  player.onPlayerComplete.listen((_) => player.dispose());
                } catch (_) {}
              }
            }
            if (newMsg.senderId != myId) {
              _marquerLuSiVisible(convId);
              // L'autre a répondu : la conversation devient normale
              _enAttenteDeReponse = false;
              limiteAtteinte.value = false;
            } else {
              _majLimite();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: convId,
          ),
          callback: (payload) {
            if (_closed) return; // ✅ FIX — contrôleur fermé
            final updated = payload.newRecord;
            final idx = messages.indexWhere((m) => m.id == updated['id']);
            if (idx != -1) {
              final rawReactions =
                  updated['reactions'] as Map<String, dynamic>? ?? {};
              final reactions = rawReactions.map(
                  (k, v) => MapEntry(k, List<String>.from(v as List? ?? [])));
              final newStatus = _parseStatus(updated['status']);
              messages[idx] = messages[idx].copyWith(
                text: updated['content'] as String?,
                modifieLe: updated['modifie_le'] != null
                    ? DateTime.tryParse(updated['modifie_le'].toString())
                        ?.toLocal()
                    : null,
                status: newStatus,
                reactions: reactions,
                isOpened: updated['is_opened'] ?? messages[idx].isOpened,
                readAt: updated['read_at'] != null
                    ? DateTime.tryParse(updated['read_at'].toString())
                        ?.toLocal()
                    : null,
              );
              if (newStatus == MessageStatus.read &&
                  messages[idx].senderId == myId) {
                lastReadAt.value = DateTime.now();
              }
            }
          },
        )
        // ✅ Messages supprimés par le serveur (purge éphémère) : les
        // suppressions ne sont pas filtrables par conversation, on
        // retire simplement l'id s'il est affiché.
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            if (_closed) return;
            final id = payload.oldRecord['id'];
            if (id != null) messages.removeWhere((m) => m.id == id);
          },
        )
        .subscribe((status, [error]) {
      if (_closed) return; // ✅ FIX — statuts ignorés après onClose
      if (status == RealtimeSubscribeStatus.subscribed) {
        // ✅ FIX — Realtime (re)connecté : on arrête le polling de secours
        _pollingTimer?.cancel();
        _pollingTimer = null;
      } else if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _startPolling();
      }
    });
    _service.markMessagesAsDelivered(convId);
    _expirationTimer?.cancel();
    _expirationTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_closed) return;
      if (messages.any((m) => m.isDisappeared)) {
        messages.removeWhere((m) => m.isDisappeared);
      }
    });
  }

  void _startPolling() {
    if (_closed) return; // ✅ FIX — jamais après onClose
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (_closed) {
        t.cancel();
        return;
      }
      try {
        final data = await _service.fetchMessages(conversation.id);
        if (_closed) return;
        final msgById = {for (final m in messages) m.id: m};
        bool receivedFromOther = false;
        for (final row in data) {
          final msg = _rowToMessage(row);
          final idx = messages.indexWhere((m) => m.id == msg.id);
          if (idx != -1) {
            // ✅ FIX — met à jour statut / réactions / ouverture des
            // messages déjà affichés (comme le fait l'événement UPDATE).
            final cur = messages[idx];
            final wasRead = cur.status == MessageStatus.read;
            if (cur.status != msg.status ||
                cur.text != msg.text ||
                cur.isOpened != msg.isOpened ||
                cur.expiresAt != msg.expiresAt ||
                cur.readAt != msg.readAt ||
                !_sameReactions(cur.reactions, msg.reactions)) {
              messages[idx] = cur.copyWith(
                text: msg.text,
                modifieLe: msg.modifieLe,
                status: msg.status,
                reactions: msg.reactions,
                isOpened: msg.isOpened,
                expiresAt: msg.expiresAt,
                readAt: msg.readAt,
              );
              if (!wasRead &&
                  msg.status == MessageStatus.read &&
                  cur.senderId == myId) {
                lastReadAt.value = DateTime.now();
              }
            }
            continue;
          }
          final replyId = row['reply_to_id'] as String?;
          final withReply = msg.copyWith(
              replyTo: replyId != null ? msgById[replyId] : null);
          // ✅ FIX — remplace la bulle temporaire "en cours d'envoi"
          // correspondante (même expéditeur + même contenu) au lieu
          // d'ajouter un doublon.
          final tempIdx = messages.indexWhere((m) =>
              m.id.startsWith('temp_') &&
              m.senderId == msg.senderId &&
              m.text == msg.text);
          if (tempIdx != -1) {
            messages[tempIdx] = withReply;
          } else {
            messages.add(withReply);
          }
          if (msg.senderId != myId) receivedFromOther = true;
        }
        // ✅ FIX — comme en Realtime : messages reçus => marqués lus
        if (receivedFromOther) _marquerLuSiVisible(conversation.id);
      } catch (_) {}
    });
  }

  // ✅ FIX — comparaison de deux maps de réactions
  bool _sameReactions(
      Map<String, List<String>> a, Map<String, List<String>> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      final other = b[e.key];
      if (other == null || other.length != e.value.length) return false;
      for (int i = 0; i < other.length; i++) {
        if (other[i] != e.value[i]) return false;
      }
    }
    return true;
  }

  void commencerModification(MessageModel msg) {
    replyToMessage.value = null;
    enModification.value = msg;
    textController.text = msg.text ?? '';
    inputText.value = textController.text;
    textController.selection =
        TextSelection.collapsed(offset: textController.text.length);
  }

  void annulerModification() {
    enModification.value = null;
    textController.clear();
    inputText.value = '';
  }

  /// Remplace le texte d'un de mes messages (le serveur vérifie que c'est
  /// bien le mien et pose modifie_le — script 20261002000019).
  Future<void> _enregistrerModification(MessageModel msg, String texte) async {
    enModification.value = null;
    textController.clear();
    inputText.value = '';
    if (texte == msg.text) return;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      messages[idx] =
          messages[idx].copyWith(text: texte, modifieLe: DateTime.now());
    }
    final db = Supabase.instance.client.from('messages');
    try {
      try {
        await db.update({
          'content': texte,
          'modifie_le': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', msg.id);
      } on PostgrestException catch (e) {
        // Colonne modifie_le absente (script pas encore exécuté)
        if (e.code != 'PGRST204' && e.code != '42703') rethrow;
        await db.update({'content': texte}).eq('id', msg.id);
      }
    } catch (_) {
      final i = messages.indexWhere((m) => m.id == msg.id);
      if (i != -1) messages[i] = msg;
      _snackInfo('Impossible de modifier le message'.tr);
    }
  }

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
    final aModifier = enModification.value;
    if (aModifier != null) {
      await _enregistrerModification(aModifier, text);
      return;
    }
    if (!peutEnvoyer()) return;
    final reply = replyToMessage.value;
    textController.clear();
    replyToMessage.value = null;
    _isCurrentlyTyping = false;
    _updateTypingStatus(false);
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: _service.currentUserId!,
      text: text,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      replyTo: reply,
    ));
    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: text,
        type: 'text',
        replyToId: reply?.id,
      );
      AvisService.messageEnvoye();
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
      // ✅ Le texte n'est plus perdu : il revient dans le champ
      if (textController.text.isEmpty) {
        textController.text = text;
        inputText.value = text;
      }
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur'.tr, 'Message non envoyé'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  /// Enregistre une réponse à une story. Essaie avec le texte de la
  /// story (colonnes story_text / story_bg_color), puis sans (si la
  /// migration 20260930000010 n'est pas encore appliquée), puis en
  /// simple message. Renvoie false si le lien vers la story est perdu ;
  /// lève une exception si même le simple message échoue.
  static Future<bool> insertStoryReplyRow({
    required String conversationId,
    required String senderId,
    required String text,
    required StoryReplyData storyData,
  }) async {
    final db = Supabase.instance.client.from('messages');
    final base = {
      'conversation_id': conversationId,
      'sender_id': senderId,
      'type': 'text',
      'content': text,
      'status': 'sent',
    };
    final hasText = storyData.storyText != null;
    try {
      await db.insert({...base, ...storyData.toColumns(withText: hasText)});
      return true;
    } catch (_) {}
    if (hasText) {
      try {
        await db.insert({...base, ...storyData.toColumns(withText: false)});
        return true;
      } catch (_) {}
    }
    await db.insert(base);
    return false;
  }

  Future<void> sendStoryReply({
    required String conversationId,
    required String text,
    required StoryReplyData storyData,
  }) async {
    if (!peutEnvoyer()) return;
    final uid = _service.currentUserId;
    if (uid == null) return;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: uid,
      text: text,
      type: MessageType.text,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      storyReply: storyData,
    ));
    bool sent = false;
    try {
      final keptStory = await insertStoryReplyRow(
        conversationId: conversationId,
        senderId: uid,
        text: text,
        storyData: storyData,
      );
      sent = true;
      if (!keptStory) {
        // ✅ FIX — le message réellement enregistré n'a pas de données
        // de story : la bulle temporaire est ajustée pour correspondre
        // (elle sera remplacée par le vrai message via Realtime/polling,
        // qui fait la correspondance sur expéditeur + contenu).
        final i = messages.indexWhere((m) => m.id == tempId);
        if (i != -1) {
          final t = messages[i];
          messages[i] = MessageModel(
            id: t.id,
            senderId: t.senderId,
            text: t.text,
            type: t.type,
            status: t.status,
            createdAt: t.createdAt,
          );
        }
      }
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
    }
    if (!sent) return;
    // ✅ FIX — comme sendMessage : la liste est triée par updated_at,
    // et une réponse du destinataire accepte une demande en attente.
    try {
      await Supabase.instance.client.from('conversations').update({
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', conversationId);
    } catch (_) {}
    await _service.maybePromoteMessageRequest(conversationId);
  }

  /// Supprimer « pour moi » : masqué sur cet appareil, l'autre le garde.
  void supprimerPourMoi(MessageModel msg) {
    if (msg.id.startsWith('temp_')) {
      messages.removeWhere((m) => m.id == msg.id);
      return;
    }
    masques.add(msg.id);
    _box.write(_cleMasques, masques.toList());
  }

  /// Choix « pour moi » / « pour tout le monde » (WhatsApp).
  void confirmerSuppression(MessageModel msg) {
    final mien = msg.senderId == myId;
    Get.dialog(AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Supprimer le message ?'.tr,
          style: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 16)),
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (mien)
          TextButton(
              onPressed: () {
                Get.back();
                deleteMessage(msg);
              },
              child:  Text('Supprimer pour tout le monde'.tr,
                  style: TextStyle(
                      color: Color(0xFFFF3B30), fontWeight: FontWeight.w700))),
        TextButton(
            onPressed: () {
              Get.back();
              supprimerPourMoi(msg);
            },
            child:  Text('Supprimer pour moi'.tr,
                style: TextStyle(
                    color: Color(0xFFFF3B30), fontWeight: FontWeight.w600))),
        TextButton(
            onPressed: () => Get.back(),
            child: Text('Annuler'.tr,
                style: TextStyle(color: AppColors.textMuted))),
      ],
    ));
  }

  /// Supprimer « pour tout le monde » (mes messages uniquement).
  Future<void> deleteMessage(MessageModel msg) async {
    final position = messages.indexWhere((m) => m.id == msg.id);
    messages.removeWhere((m) => m.id == msg.id);
    if (msg.id.startsWith('temp_')) return;
    try {
      await Supabase.instance.client.from('messages').delete().eq('id', msg.id);
    } catch (_) {
      // ✅ Avant : échec silencieux, le message revenait au rechargement.
      if (position >= 0 && !messages.any((m) => m.id == msg.id)) {
        messages.insert(position.clamp(0, messages.length), msg);
      }
      _snackInfo('Impossible de supprimer le message'.tr);
    }
  }

  void copyMessage(MessageModel msg) {
    if (msg.text != null && msg.text!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: msg.text!));
      Get.snackbar('Copié'.tr, 'Message copié'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary,
          duration: const Duration(seconds: 2));
    }
  }

  /// Transférer un message texte vers une autre conversation
  void transferer(BuildContext context, MessageModel msg) {
    final texte = (msg.text ?? '').trim();
    if (texte.isEmpty || !Get.isRegistered<ChatListController>()) return;
    final convs = Get.find<ChatListController>()
        .conversations
        .where((c) => c.id != conversation.id)
        .toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Transférer à…'.tr,
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            Expanded(
              child: convs.isEmpty
                  ? Center(
                      child: Text('Aucune conversation pour le moment'.tr,
                          style: TextStyle(color: AppColors.textMuted)))
                  : ListView.builder(
                      itemCount: convs.length,
                      itemBuilder: (_, i) {
                        final c = convs[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.surface2,
                            backgroundImage: (c.userPhotoUrl ?? '').isNotEmpty
                                ? CachedNetworkImageProvider(c.userPhotoUrl!, maxWidth: 400)
                                : null,
                            child: (c.userPhotoUrl ?? '').isEmpty
                                ? Text(c.userName.isNotEmpty
                                    ? c.userName[0].toUpperCase()
                                    : '?')
                                : null,
                          ),
                          title: Text(c.userName,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600)),
                          trailing: Icon(Icons.send_rounded,
                              color: AppColors.accent, size: 20),
                          onTap: () async {
                            Get.back();
                            try {
                              await _service.sendMessage(
                                  conversationId: c.id, content: texte);
                              Get.snackbar('Message transféré'.tr,
                                  'Envoyé à @nom'.trParams({'nom': c.userName}),
                                  snackPosition: SnackPosition.TOP,
                                  backgroundColor: AppColors.surface,
                                  colorText: AppColors.textPrimary);
                            } catch (e) {
                              debugPrint('Transfert échoué : $e');
                              Get.snackbar('Message non envoyé'.tr,
                                  'Vérifie ta connexion et réessaie'.tr,
                                  snackPosition: SnackPosition.TOP,
                                  backgroundColor: AppColors.surface,
                                  colorText: AppColors.textPrimary);
                            }
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  void showMessageOptions(BuildContext context, MessageModel msg) {
    HapticFeedback.mediumImpact();
    final isMine = msg.senderId == myId;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      // Défilant : sur les petits écrans, toutes les options restent
      // accessibles (plus de débordement).
      isScrollControlled: true,
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(32)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: availableEmojis.map((emoji) {
                final uid = _service.currentUserId ?? '';
                final hasReacted = msg.hasReacted(emoji, uid);
                return GestureDetector(
                  onTap: () {
                    Get.back();
                    toggleReaction(msg, emoji);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? AppColors.accent.withOpacity(0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: hasReacted
                          ? Border.all(color: AppColors.accent)
                          : null,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  ),
                );
              }).toList(),
            ),
          ),
          if (msg.type == MessageType.text && msg.text != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(msg.text!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ),
          _MsgOption(
              icon: Icons.reply_rounded,
              label: 'Répondre'.tr,
              onTap: () {
                Get.back();
                setReplyTo(msg);
              }),
          if (isMine && msg.modifiable)
            _MsgOption(
                icon: Icons.edit_rounded,
                label: 'Modifier'.tr,
                onTap: () {
                  Get.back();
                  commencerModification(msg);
                }),
          if (msg.type == MessageType.text)
            _MsgOption(
                icon: Icons.copy_rounded,
                label: 'Copier'.tr,
                onTap: () {
                  Get.back();
                  copyMessage(msg);
                }),
          if (msg.type == MessageType.text && !msg.id.startsWith('temp_'))
            _MsgOption(
                icon: Icons.push_pin_outlined,
                label: epingleId.value == msg.id
                    ? 'Désépingler'.tr
                    : 'Épingler'.tr,
                onTap: () {
                  Get.back();
                  epingler(epingleId.value == msg.id ? null : msg);
                }),
          if (msg.type == MessageType.text)
            _MsgOption(
                icon: Icons.forward_rounded,
                label: 'Transférer'.tr,
                onTap: () {
                  Get.back();
                  transferer(context, msg);
                }),
          _MsgOption(
              icon: Icons.delete_outline_rounded,
              label: 'Supprimer'.tr,
              color: const Color(0xFFFF3B30),
              onTap: () {
                Get.back();
                confirmerSuppression(msg);
              }),
          if (!isMine)
            _MsgOption(
                icon: Icons.flag_outlined,
                label: 'Signaler'.tr,
                color: const Color(0xFFFF9500),
                onTap: () {
                  Get.back();
                  signalerMessage(msg);
                }),
        ]),
      ),
    );
  }

  Future<void> openSnap(MessageModel msg) async {
    if (msg.isOpened) return;
    final duration = msg.snapDurationSec ?? 10;
    final idx = messages.indexWhere((m) => m.id == msg.id);
    if (idx != -1) {
      messages[idx] = messages[idx].copyWith(
        isOpened: true,
        expiresAt: duration == 0
            ? DateTime.now()
            : DateTime.now().add(Duration(seconds: duration)),
      );
    }
    try {
      await Supabase.instance.client.from('messages').update({
        'is_opened': true,
        'expires_at': (duration == 0
                ? DateTime.now()
                : DateTime.now().add(Duration(seconds: duration)))
            .toUtc() // ✅ FIX — horodatage envoyé en UTC (timestamptz)
            .toIso8601String(),
      }).eq('id', msg.id);
    } catch (e) {
      debugPrint('openSnap : ouverture non enregistrée — $e');
    }
    // Comme Snapchat : le snap n'est plus visible mais une trace
    // « Snap ouvert » reste dans la discussion (la bulle passe d'elle-même
    // en trace à la fin du compte à rebours ; le serveur supprime la photo).
  }

  Future<void> envoyerPhotoEphemere() async {
    if (!peutEnvoyer()) return;
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 85);
    if (picked == null) return;
    final uid = _service.currentUserId!;
    final path = 'snaps/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '📸 Photo éphémère',
        type: 'snap',
        mediaUrl: url,
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        snapDurationSeconds: 10,
      );
    } catch (e) {
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur'.tr, 'Impossible d\'envoyer le snap'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  Future<void> envoyerPhotoAvecDuree(
      {required bool camera, required SnapDuration duree}) async {
    if (!peutEnvoyer()) return;
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked == null) return;
    final uid = _service.currentUserId!;
    final isSnap = duree != SnapDuration.none;
    final path =
        '${isSnap ? 'snaps' : 'photos'}/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: isSnap ? '📸 Photo éphémère' : '📷 Photo',
        type: isSnap ? 'snap' : 'image',
        mediaUrl: url,
        snapDurationSeconds: duree.seconds,
      );
    } catch (e) {
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur'.tr, 'Impossible d\'envoyer la photo'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  void toggleAttachMenu() => showAttachMenu.toggle();

  /// Étape d'envoi des médias en cours (« Compression… », « Envoi… »),
  /// par id temporaire de message : affichée sur la bulle.
  static final RxMap<String, String> etatsEnvoi = <String, String>{}.obs;

  /// Photo / vidéo / snap envoyé EN ARRIÈRE-PLAN, comme WhatsApp : la
  /// bulle apparaît tout de suite (aperçu local), la vidéo est compressée
  /// (720p) puis envoyée avec sa vignette ; on peut continuer à écrire.
  Future<void> envoyerMediaEnFond({
    required String chemin,
    required bool video,
    bool ephemere = false,
    int? snapSecondes,
    bool sensible = false,
    String? legende, // texte envoyé juste après la photo / vidéo
  }) async {
    if (!peutEnvoyer()) return;
    final uid = _service.currentUserId!;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_media_$ts';
    var contenu = video
        ? (ephemere ? '🎬 Vidéo éphémère' : '🎬 Vidéo')
        : ephemere
            ? '📸 Photo éphémère'
            : '📷 Photo';
    if (sensible) {
      // Le texte sert de marqueur : « 🔞 Photo », « 🔞 Vidéo »…
      contenu = '$prefixeSensible ${contenu.substring(contenu.indexOf(' ') + 1)}';
    }
    // Snap : photo OU vidéo éphémère (le texte « Vidéo » indique la vidéo)
    final type = ephemere ? MessageType.snap : MessageType.image;
    messages.add(MessageModel(
      id: tempId,
      senderId: uid,
      text: contenu,
      mediaUrl: chemin, // aperçu local pendant l'envoi
      type: type,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
    ));
    void maj(MessageModel Function(MessageModel) f) {
      final i = messages.indexWhere((m) => m.id == tempId);
      if (i != -1) messages[i] = f(messages[i]);
    }

    var fichier = File(chemin);
    File? vignette;
    int? dureeSec;
    try {
      if (video) {
        etatsEnvoi[tempId] = 'Préparation…'.tr;
        try {
          vignette = await VideoCompress.getFileThumbnail(chemin,
              quality: 60, position: -1);
          final info = await VideoCompress.getMediaInfo(chemin);
          if (info.duration != null) dureeSec = (info.duration! / 1000).round();
          maj((m) => m.copyWith(
              vignetteUrl: vignette?.path, audioDurationSec: dureeSec));
          // Compression 720p si la vidéo dépasse ~6 Mo
          if ((info.filesize ?? 0) > 6 * 1024 * 1024) {
            etatsEnvoi[tempId] = 'Compression…'.tr;
            final c = await VideoCompress.compressVideo(chemin,
                quality: VideoQuality.Res1280x720Quality,
                deleteOrigin: false,
                includeAudio: true);
            if (c?.file != null) fichier = c!.file!;
          }
        } catch (e) {
          debugPrint('compression vidéo : $e'); // on envoie l'original
        }
      }
      etatsEnvoi[tempId] = 'Envoi…'.tr;
      final dossier = ephemere ? 'snaps' : 'photos';
      final base = '$dossier/$uid/${video ? 'video' : 'photo'}_$ts';
      final cheminMedia = '$base.${video ? 'mp4' : 'jpg'}';
      final store = Supabase.instance.client.storage.from('snaps');
      await store.upload(cheminMedia, fichier,
          fileOptions: FileOptions(
              upsert: true, contentType: video ? 'video/mp4' : 'image/jpeg'));
      final url = store.getPublicUrl(cheminMedia);
      String? urlVignette;
      if (vignette != null) {
        try {
          await store.upload('$base.jpg', vignette,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/jpeg'));
          urlVignette = store.getPublicUrl('$base.jpg');
        } catch (_) {}
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final ligne = {
        'conversation_id': conversation.id,
        'sender_id': uid,
        'type': type == MessageType.snap ? 'snap' : 'image',
        'content': contenu,
        'media_url': url,
        'status': 'sent',
        'created_at': now,
        if (ephemere && snapSecondes != null) 'snap_duration': snapSecondes,
        if (dureeSec != null) 'audio_duration': dureeSec,
      };
      Map<String, dynamic> enregistre;
      try {
        enregistre = await Supabase.instance.client
            .from('messages')
            .insert({...ligne, if (urlVignette != null) 'vignette_url': urlVignette})
            .select()
            .single();
      } on PostgrestException catch (e) {
        // Colonne vignette_url absente (script SQL 039 pas encore passé)
        if (e.code != 'PGRST204' && e.code != '42703') rethrow;
        enregistre = await Supabase.instance.client
            .from('messages')
            .insert(ligne)
            .select()
            .single();
      }
      await Supabase.instance.client
          .from('conversations')
          .update({'updated_at': now}).eq('id', conversation.id);
      // La bulle temporaire devient le vrai message
      final vrai = _rowToMessage(enregistre);
      messages.removeWhere((m) => m.id == tempId);
      if (!messages.any((m) => m.id == vrai.id)) messages.add(vrai);
      // Légende : envoyée après le média pour garder l'ordre
      final texte = (legende ?? '').trim();
      if (texte.isNotEmpty) {
        try {
          await _service.sendMessage(
              conversationId: conversation.id,
              content: texte.substring(0, texte.length.clamp(0, 1000)));
        } catch (e) {
          debugPrint('Légende non envoyée : $e');
        }
      }
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
      if (gererRefusServeur(e)) return;
      Get.snackbar(
          video ? 'Vidéo non envoyée'.tr : 'Photo non envoyée'.tr,
          'Vérifie ta connexion et réessaie'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary,
          duration: const Duration(seconds: 5),
          mainButton: TextButton(
            onPressed: () => envoyerMediaEnFond(
                chemin: chemin,
                video: video,
                ephemere: ephemere,
                snapSecondes: snapSecondes,
                sensible: sensible),
            child: Text('Réessayer'.tr,
                style: TextStyle(color: AppColors.lien)),
          ));
    } finally {
      etatsEnvoi.remove(tempId);
      if (video) {
        try {
          await VideoCompress.deleteAllCache();
        } catch (_) {}
      }
    }
  }

  /// Contenu texte des messages sticker / GIF (sert aussi à les reconnaître).
  static const texteSticker = '🎨 Sticker';
  static const texteGif = '🎞️ GIF';
  // 🔞 Photo / vidéo marquée sensible par l'expéditeur : floutée chez le
  // destinataire (réglage « Flouter les photos sensibles », activé par défaut).
  static const prefixeSensible = '🔞';
  static const cleFlouterSensibles = 'flouter_sensibles';
  static bool get flouterSensibles =>
      GetStorage().read<bool>(cleFlouterSensibles) ?? true;

  // Message « album privé partagé » : affiché comme une carte cliquable.
  static const texteAlbum = '🔓 Je t\'ai ouvert mon album privé';

  /// Partage mon album privé avec la personne + message dans la discussion
  /// (comme Grindr). true = partagé, false = album vide, null = échec.
  Future<bool?> partagerAlbum() async {
    if (!peutEnvoyer()) return null;
    showAttachMenu.value = false;
    try {
      final photos = await AlbumService.mesPhotos();
      if (photos.isEmpty) return false;
      await AlbumService.partager(conversation.userId);
    } catch (e) {
      // ✅ Avant : exception non gérée (bouton ➕ Album)
      debugPrint('partagerAlbum error: $e');
      _snackInfo('Impossible de partager l\'album'.tr);
      return null;
    }
    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: texteAlbum,
        type: 'text',
      );
    } catch (e) {
      if (!gererRefusServeur(e)) _snackInfo('Impossible d\'envoyer le message'.tr);
    }
    return true;
  }

  /// Sticker ou GIF GIPHY : envoyé comme image (lien GIPHY).
  Future<void> envoyerSticker(String url, {required bool gif}) async {
    if (!peutEnvoyer()) return;
    showAttachMenu.value = false;
    final texte = gif ? texteGif : texteSticker;
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: myId,
      text: texte,
      mediaUrl: url,
      type: MessageType.image,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
    ));
    try {
      await _service.sendMessage(
        conversationId: conversation.id,
        content: texte,
        type: 'image',
        mediaUrl: url,
      );
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
      if (gererRefusServeur(e)) return;
      _snackInfo('Impossible d\'envoyer le sticker'.tr);
    }
  }

  Future<void> startRecording() async {
    if (!peutEnvoyer()) return;
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      Get.snackbar(
          'Permission refusée'.tr, 'Active le microphone dans les paramètres'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary,
          mainButton: TextButton(
              onPressed: () => openAppSettings(),
              child: Text('Paramètres'.tr,
                  style: TextStyle(color: AppColors.textPrimary))));
      return;
    }
    if (_recorderOpen) {
      try {
        await _recorder.closeRecorder();
      } catch (_) {}
      _recorderOpen = false;
    }
    try {
      await _recorder.openRecorder();
      _recorderOpen = true;
      final codecFound = await _detectCodec(_recorder);
      if (!codecFound) {
        await _recorder.closeRecorder();
        _recorderOpen = false;
        Get.snackbar('Erreur'.tr, 'Enregistrement non supporté sur cet appareil'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: AppColors.textPrimary);
        return;
      }
      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}$_detectedExt';
      await _recorder
          .setSubscriptionDuration(const Duration(milliseconds: 150));
      await _recorder.startRecorder(
          toFile: _recordingPath!, codec: _detectedCodec!);
      isRecording.value = true;
      // Signale à l'autre « enregistre un vocal… » (rafraîchi toutes les 3 s)
      _updateTypingStatus(true, activite: 'vocal', avecActivite: true);
      _vocalPing?.cancel();
      _vocalPing = Timer.periodic(const Duration(seconds: 3), (t) {
        if (!isRecording.value) {
          t.cancel();
          return;
        }
        _updateTypingStatus(true, activite: 'vocal', avecActivite: true);
      });
      recordingSeconds.value = 0;
      recordingDb.value = 0;
      _recorder.onProgress!.listen((e) {
        if (!isRecording.value) return;
        if (e.decibels != null)
          recordingDb.value = (e.decibels! + 60).clamp(0.0, 80.0);
      });
      _recordingSecondsTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!isRecording.value) {
          t.cancel();
          return;
        }
        recordingSeconds.value++;
        if (recordingSeconds.value >= 120) {
          t.cancel();
          stopRecording();
        }
      });
    } catch (e) {
      _recorderOpen = false;
      isRecording.value = false;
    }
  }

  void _finVocal() {
    _vocalPing?.cancel();
    _updateTypingStatus(false, activite: null, avecActivite: true);
  }

  Future<void> stopRecording() async {
    if (!isRecording.value) return;
    _finVocal();
    try {
      _recordingSecondsTimer?.cancel();
      final path = await _recorder.stopRecorder();
      await _recorder.closeRecorder();
      _recorderOpen = false;
      isRecording.value = false;
      recordingDb.value = 0;
      if (path == null || recordingSeconds.value < 1) return;
      await _sendAudio(File(path), recordingSeconds.value);
    } catch (e) {
      _recorderOpen = false;
      isRecording.value = false;
    }
  }

  void cancelRecording() async {
    _recordingSecondsTimer?.cancel();
    _finVocal();
    try {
      await _recorder.stopRecorder();
      await _recorder.closeRecorder();
      _recorderOpen = false;
    } catch (_) {}
    isRecording.value = false;
    recordingSeconds.value = 0;
    recordingDb.value = 0;
  }

  Future<void> _sendAudio(File file, int duration) async {
    final uid = _service.currentUserId!;
    // ✅ Bulle affichée tout de suite (avant : rien pendant l'envoi, qui peut
    // prendre plusieurs secondes en 3G). Remplacée par le vrai message via
    // Realtime / polling (même expéditeur + même texte).
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    messages.add(MessageModel(
      id: tempId,
      senderId: uid,
      text: '🎤 Message vocal'.tr,
      type: MessageType.audio,
      status: MessageStatus.sending,
      createdAt: DateTime.now(),
      audioDurationSec: duration,
    ));
    final ext = _detectedExt ?? '.mp4';
    final contentType = ext == '.ogg'
        ? 'audio/ogg'
        : ext == '.aac'
            ? 'audio/aac'
            : 'audio/mp4';
    final path = 'audio/$uid/${DateTime.now().millisecondsSinceEpoch}$ext';
    try {
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions: FileOptions(upsert: true, contentType: contentType));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '🎤 Message vocal',
        type: 'audio',
        mediaUrl: url,
        audioDuration: duration,
      );
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur'.tr, 'Impossible d\'envoyer le vocal'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  Future<void> playAudio(String url, String messageId) async {
    try {
      if (currentlyPlayingId.value == messageId) {
        await _audioPlayer.stop();
        currentlyPlayingId.value = '';
        return;
      }
      if (currentlyPlayingId.value.isNotEmpty) await _audioPlayer.stop();
      currentlyPlayingId.value = messageId;
      await _audioPlayer.play(UrlSource(url));
      if (vitesseAudio.value != 1.0) {
        await _audioPlayer.setPlaybackRate(vitesseAudio.value);
      }
    } catch (e) {
      currentlyPlayingId.value = '';
    }
  }

  Future<void> envoyerPhoto({bool camera = false}) async {
    if (!peutEnvoyer()) return;
    showAttachMenu.value = false;
    final picked = await _imagePicker.pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 80);
    if (picked == null) return;
    final uid = _service.currentUserId!;
    final path = 'photos/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final file = File(picked.path);
      await Supabase.instance.client.storage.from('snaps').upload(path, file,
          fileOptions:
              const FileOptions(upsert: true, contentType: 'image/jpeg'));
      final url =
          Supabase.instance.client.storage.from('snaps').getPublicUrl(path);
      await _service.sendMessage(
        conversationId: conversation.id,
        content: '📷 Photo',
        type: 'image',
        mediaUrl: url,
      );
    } catch (e) {
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur'.tr, 'Impossible d\'envoyer la photo'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  Future<void> envoyerLocalisation() async {
    if (!peutEnvoyer()) return;
    showAttachMenu.value = false;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar('GPS désactivé'.tr, 'Active la localisation'.tr,
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: AppColors.textPrimary);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      Get.snackbar('📍', 'Récupération en cours...'.tr,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.surface2,
          colorText: AppColors.textPrimary);
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _service.sendMessage(
        conversationId: conversation.id,
        content:
            '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}',
        type: 'location',
      );
    } catch (e) {
      Get.snackbar('Erreur'.tr, 'Impossible de récupérer la position'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  String get myId => _service.currentUserId ?? '';

  MessageModel _rowToMessage(Map<String, dynamic> row,
      {MessageModel? replyTo}) {
    // ── Story reply ──────────────────────────────────────────────
    StoryReplyData? storyReply;
    final storyId = row['story_id'] as String?;
    final storyPreviewUrl = row['story_preview_url'] as String?;
    if (storyId != null && storyPreviewUrl != null) {
      storyReply = StoryReplyData(
        storyId: storyId,
        storyPreviewUrl: storyPreviewUrl,
        storyIsVideo: row['story_is_video'] as bool? ?? false,
        storyOwnerName: _parseStoryOwnerName(row['topic'] as String?),
        storyText: row['story_text'] as String?,
        storyBgColor: row['story_bg_color'] as String?,
      );
    }

    final type = _parseType(row['type'] as String?);

    final rawReactions = row['reactions'] as Map<String, dynamic>? ?? {};
    final reactions = rawReactions
        .map((k, v) => MapEntry(k, List<String>.from(v as List? ?? [])));

    return MessageModel(
      id: row['id'] ?? '',
      senderId: row['sender_id'] ?? '',
      text: row['content'],
      mediaUrl: row['media_url'],
      type: type,
      status: _parseStatus(row['status']),
      createdAt: DateTime.tryParse(row['created_at'] ?? '')?.toLocal() ??
          DateTime.now(),
      isOpened: row['is_opened'] ?? false,
      audioDurationSec: row['audio_duration'],
      snapDurationSec: row['snap_duration'] as int?,
      expiresAt: row['expires_at'] != null
          ? DateTime.tryParse(row['expires_at'])
          : null,
      disappearsAt: row['disappears_at'] != null
          ? DateTime.tryParse(row['disappears_at'])
          : null,
      readAt: row['read_at'] != null
          ? DateTime.tryParse(row['read_at'].toString())?.toLocal()
          : null,
      reactions: reactions,
      storyReply: storyReply,
      replyTo: replyTo,
      modifieLe: row['modifie_le'] != null
          ? DateTime.tryParse(row['modifie_le'].toString())?.toLocal()
          : null,
      vignetteUrl: row['vignette_url'] as String?,
    );
  }

  String _parseStoryOwnerName(String? topic) {
    if (topic == null) return '';
    const prefix = '📸 Story de ';
    if (topic.startsWith(prefix)) return topic.substring(prefix.length);
    return topic;
  }

  MessageType _parseType(String? t) {
    switch (t) {
      case 'image':
        return MessageType.image;
      case 'snap':
        return MessageType.snap;
      case 'audio':
        return MessageType.audio;
      case 'location':
        return MessageType.location;
      default:
        return MessageType.text;
    }
  }

  MessageStatus _parseStatus(String? s) {
    switch (s) {
      case 'sending':
        return MessageStatus.sending;
      case 'delivered':
        return MessageStatus.delivered;
      case 'read':
        return MessageStatus.read;
      default:
        return MessageStatus.sent;
    }
  }

  @override
  void onClose() {
    // ✅ FIX — drapeau posé avant de fermer les canaux : les statuts
    // "closed"/erreurs qui suivent ne relancent plus le polling.
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    // ✅ FIX — retire réellement les canaux du client Realtime
    for (final ch in [_channel, _presenceChannel, _typingChannel]) {
      if (ch != null) {
        Supabase.instance.client.removeChannel(ch).catchError((_) => '');
      }
    }
    _channel = null;
    _presenceChannel = null;
    _typingChannel = null;
    _typingTimer?.cancel();
    _myTypingTimer?.cancel();
    _vocalPing?.cancel();
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _recordingSecondsTimer?.cancel();
    _updateTypingStatus(false);
    if (_recorderOpen) _recorder.closeRecorder().catchError((_) {});
    _expirationTimer?.cancel();
    _audioPlayer.dispose();
    scrollController.dispose();
    super.onClose();
  }
}

class _CodecOption {
  final Codec codec;
  final String ext;
  final String mimeType;
  const _CodecOption(this.codec, this.ext, this.mimeType);
}

class _MsgOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;
  const _MsgOption(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: c, size: 22),
      title: Text(label,
          style:
              TextStyle(color: c, fontSize: 15, fontWeight: FontWeight.w500)),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
