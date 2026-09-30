import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rencontre/core/services/notification_service.dart';
import 'package:get/get.dart';
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

enum ChatFilter { all, unread, online, nearby, media }

class ChatListController extends GetxController {
  final _service = SupabaseService();
  final RxList<ConversationModel> conversations = <ConversationModel>[].obs;
  final RxBool isLoading = true.obs;
  final Rx<ChatFilter> activeFilter = ChatFilter.all.obs;
  final RxBool isSearching = false.obs;
  final RxString searchQuery = ''.obs;
  RealtimeChannel? _channel;
  final RxSet<String> pinnedIds = <String>{}.obs;
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

  List<ConversationModel> get filteredConversations {
    List<ConversationModel> list;
    switch (activeFilter.value) {
      case ChatFilter.unread:
        list = conversations.where((c) => c.unreadCount > 0).toList();
        break;
      case ChatFilter.online:
        list = conversations.where((c) => c.isOnline).toList();
        break;
      case ChatFilter.nearby:
        final cutoff = DateTime.now().subtract(const Duration(hours: 1));
        list = conversations
            .where((c) =>
                c.lastActivity != null && c.lastActivity!.isAfter(cutoff))
            .toList();
        break;
      case ChatFilter.media:
        list = conversations
            .where((c) =>
                c.lastMessage != null &&
                (c.lastMessage!.type == MessageType.image ||
                    c.lastMessage!.type == MessageType.snap))
            .toList();
        break;
      case ChatFilter.all:
      default:
        list = conversations.toList();
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
    loadConversations();
    _subscribeToMessages();
  }

  Future<void> loadConversations({bool silent = false}) async {
    if (!silent) isLoading.value = true;
    try {
      final uid = _service.currentUserId!;
      final data = await _service.fetchConversations();
      if (_closed) return; // ✅ FIX — contrôleur fermé entre-temps
      conversations.value = data.map((row) {
        final isUser1 = row['user1_id'] == uid;
        final otherProfile = isUser1
            ? _extractProfile(row, 'user2')
            : _extractProfile(row, 'user1');
        final lastMsg = row['_last_message'] as Map<String, dynamic>?;
        final unread = (row['_unread_count'] as int?) ?? 0;
        return ConversationModel(
          id: row['id'],
          userId: otherProfile['id'] ?? '',
          userName: otherProfile['name'] ?? 'Utilisateur',
          userPhotoUrl: otherProfile['photo_url'],
          isOnline: otherProfile['is_online'] ?? false,
          unreadCount: unread,
          lastActivity: row['updated_at'] != null
              ? DateTime.tryParse(row['updated_at'])
              : null,
          isPinned: pinnedIds.contains(row['id']),
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
      }).toList();
      _sortConversations();
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

  void togglePin(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx == -1) return;
    final nowPinned = !conv.isPinned;
    nowPinned ? pinnedIds.add(conv.id) : pinnedIds.remove(conv.id);
    conversations[idx] = ConversationModel(
      id: conv.id,
      userId: conv.userId,
      userName: conv.userName,
      userPhotoUrl: conv.userPhotoUrl,
      isOnline: conv.isOnline,
      lastMessage: conv.lastMessage,
      unreadCount: conv.unreadCount,
      lastActivity: conv.lastActivity,
      isPinned: nowPinned,
    );
    _sortConversations();
    update();
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
                  ConversationModel(
                    id: c.id,
                    userId: c.userId,
                    userName: c.userName,
                    userPhotoUrl: c.userPhotoUrl,
                    isOnline: c.isOnline,
                    isPinned: c.isPinned,
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
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx != -1) {
      conversations[idx] = ConversationModel(
        id: conv.id,
        userId: conv.userId,
        userName: conv.userName,
        userPhotoUrl: conv.userPhotoUrl,
        isOnline: conv.isOnline,
        isPinned: conv.isPinned,
        unreadCount: 0,
        lastActivity: conv.lastActivity,
        lastMessage: conv.lastMessage,
      );
      update();
    }
    NotificationService.clearConversationNotifications(conv.id);
    Get.toNamed('/chat/conversation', arguments: conv);
  }

  void toggleReadStatus(ConversationModel conv) {
    final idx = conversations.indexWhere((c) => c.id == conv.id);
    if (idx == -1) return;
    final c = conversations[idx];
    conversations[idx] = ConversationModel(
      id: c.id,
      userId: c.userId,
      userName: c.userName,
      userPhotoUrl: c.userPhotoUrl,
      isOnline: c.isOnline,
      isPinned: c.isPinned,
      unreadCount: c.unreadCount > 0 ? 0 : 1,
      lastActivity: c.lastActivity,
      lastMessage: c.lastMessage,
    );
    update();
  }

  Future<void> deleteConversation(String convId) async {
    conversations.removeWhere((c) => c.id == convId);
    update();
    try {
      await Supabase.instance.client
          .from('conversations')
          .delete()
          .eq('id', convId);
    } catch (e) {
      debugPrint('deleteConversation error: $e');
    }
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

class ConversationController extends GetxController {
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
  final RxBool isOtherOnline = false.obs;
  final RxBool isOtherTyping = false.obs;
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

  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _recorderOpen = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  final RxInt recordingSeconds = 0.obs;
  final RxDouble recordingDb = 0.0.obs;
  String? _recordingPath;
  final RxString currentlyPlayingId = ''.obs;
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
    _audioPlayer.onPlayerComplete.listen((_) => currentlyPlayingId.value = '');
    // Recalcule la limite dès que la liste des messages change
    ever(messages, (_) => _majLimite());
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
    });
  }

  /// Date jusqu'à laquelle l'historique a été effacé sur cet appareil.
  static DateTime? historiqueEffaceAvant(String convId) {
    final v = GetStorage().read<String>('chat_efface_$convId');
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Messages affichés : hors messages expirés et historique effacé.
  bool estVisible(MessageModel m) {
    if (m.isDisappeared) return false;
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
      _snackInfo(activer
          ? 'Notifications coupées pour cette conversation'
          : 'Notifications réactivées');
    } catch (e) {
      debugPrint('basculerSourdine error: $e');
      sourdine.value = !activer;
      _snackInfo('Impossible de modifier les notifications');
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
    _snackInfo('Historique effacé sur cet appareil');
  }

  /// Signale un message reçu : motif, puis enregistrement dans `reports`
  /// avec une copie du contenu (le message disparaît après lecture).
  Future<void> signalerMessage(MessageModel msg) async {
    final uid = _service.currentUserId;
    if (uid == null || msg.senderId == uid) return;
    final raison = await choisirMotifSignalement('Pourquoi signaler ce message ?');
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
      _snackInfo("Signalement envoyé. Merci, notre équipe va l'examiner.");
    } on PostgrestException catch (e) {
      _snackInfo(e.code == '23505'
          ? 'Tu as déjà signalé ce message'
          : "Impossible d'envoyer le signalement");
    } catch (_) {
      _snackInfo("Impossible d'envoyer le signalement");
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
      _snackRefus('Tu ne peux plus écrire à cette personne');
      return false;
    }
    if (limiteAtteinte.value) {
      _snackRefus('Attends sa réponse pour envoyer d\x27autres messages');
      return false;
    }
    return true;
  }

  /// Erreur renvoyée par le serveur (limite ou blocage) : message clair.
  bool gererRefusServeur(Object e) {
    final t = e.toString();
    if (t.contains('limite_sans_reponse')) {
      limiteAtteinte.value = true;
      _snackRefus('Attends sa réponse pour envoyer d\x27autres messages');
      return true;
    }
    if (t.contains('bloque')) {
      bloque.value = true;
      _snackRefus('Tu ne peux plus écrire à cette personne');
      return true;
    }
    return false;
  }

  void _snackRefus(String texte) => Get.snackbar('Message non envoyé', texte,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: Colors.white);

  Future<void> _fetchOtherOnlineStatus(String otherUserId) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('is_online')
          .eq('id', otherUserId)
          .maybeSingle();
      if (data != null) {
        isOtherOnline.value = data['is_online'] == true;
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

  Future<void> _updateTypingStatus(bool typing) async {
    final uid = _service.currentUserId;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('typing_status').upsert({
        'conversation_id': conversation.id,
        'user_id': uid,
        'is_typing': typing,
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
            if (typing) {
              isOtherTyping.value = true;
              _typingTimer?.cancel();
              _typingTimer = Timer(const Duration(seconds: 4),
                  () => isOtherTyping.value = false);
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
            isOtherOnline.value = payload.newRecord['is_online'] == true;
          },
        )
        .subscribe();
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
        listCtrl.conversations[idx] = ConversationModel(
          id: c.id,
          userId: c.userId,
          userName: c.userName,
          userPhotoUrl: c.userPhotoUrl,
          isOnline: c.isOnline,
          isPinned: c.isPinned,
          unreadCount: 0,
          lastActivity: c.lastActivity,
          lastMessage: c.lastMessage,
        );
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
              _markReadAndUpdateBadge(convId);
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
                status: newStatus,
                reactions: reactions,
                isOpened: updated['is_opened'] ?? messages[idx].isOpened,
                readAt: updated['read_at'] != null
                    ? DateTime.tryParse(updated['read_at'].toString())
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
                cur.isOpened != msg.isOpened ||
                cur.expiresAt != msg.expiresAt ||
                cur.readAt != msg.readAt ||
                !_sameReactions(cur.reactions, msg.reactions)) {
              messages[idx] = cur.copyWith(
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
        if (receivedFromOther) _markReadAndUpdateBadge(conversation.id);
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

  Future<void> sendText() async {
    final text = textController.text.trim();
    if (text.isEmpty) return;
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
    } catch (e) {
      messages.removeWhere((m) => m.id == tempId);
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur', 'Message non envoyé',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
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

  Future<void> deleteMessage(MessageModel msg) async {
    messages.removeWhere((m) => m.id == msg.id);
    if (!msg.id.startsWith('temp_')) {
      try {
        await Supabase.instance.client
            .from('messages')
            .delete()
            .eq('id', msg.id);
      } catch (_) {}
    }
  }

  void copyMessage(MessageModel msg) {
    if (msg.text != null && msg.text!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: msg.text!));
      Get.snackbar('Copié', 'Message copié',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white,
          duration: const Duration(seconds: 2));
    }
  }

  void showMessageOptions(BuildContext context, MessageModel msg) {
    HapticFeedback.mediumImpact();
    final isMine = msg.senderId == myId;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
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
              label: 'Répondre',
              onTap: () {
                Get.back();
                setReplyTo(msg);
              }),
          if (msg.type == MessageType.text)
            _MsgOption(
                icon: Icons.copy_rounded,
                label: 'Copier',
                onTap: () {
                  Get.back();
                  copyMessage(msg);
                }),
          if (isMine)
            _MsgOption(
                icon: Icons.delete_outline_rounded,
                label: 'Supprimer',
                color: const Color(0xFFFF3B30),
                onTap: () {
                  Get.back();
                  deleteMessage(msg);
                }),
          if (!isMine)
            _MsgOption(
                icon: Icons.flag_outlined,
                label: 'Signaler',
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
    } catch (_) {}
    if (duration > 0) {
      Timer(Duration(seconds: duration), () {
        final i = messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) messages.removeAt(i);
      });
    } else {
      Timer(const Duration(milliseconds: 500), () {
        final i = messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) messages.removeAt(i);
      });
    }
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
      Get.snackbar('Erreur', "Impossible d'envoyer le snap",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
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
      Get.snackbar('Erreur', "Impossible d'envoyer la photo",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    }
  }

  void toggleAttachMenu() => showAttachMenu.toggle();

  Future<void> startRecording() async {
    if (!peutEnvoyer()) return;
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      Get.snackbar(
          'Permission refusée', 'Active le microphone dans les paramètres',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white,
          mainButton: TextButton(
              onPressed: () => openAppSettings(),
              child: Text('Paramètres',
                  style: TextStyle(color: AppColors.accent))));
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
        Get.snackbar('Erreur', 'Enregistrement non supporté sur cet appareil',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
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

  Future<void> stopRecording() async {
    if (!isRecording.value) return;
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
      if (gererRefusServeur(e)) return;
      Get.snackbar('Erreur', "Impossible d'envoyer le vocal",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
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
      Get.snackbar('Erreur', "Impossible d'envoyer la photo",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
    }
  }

  Future<void> envoyerLocalisation() async {
    if (!peutEnvoyer()) return;
    showAttachMenu.value = false;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        Get.snackbar('GPS désactivé', 'Active la localisation',
            snackPosition: SnackPosition.TOP,
            backgroundColor: AppColors.surface,
            colorText: Colors.white);
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      Get.snackbar('📍', 'Récupération en cours...',
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 1),
          backgroundColor: AppColors.surface2,
          colorText: Colors.white);
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _service.sendMessage(
        conversationId: conversation.id,
        content:
            '${position.latitude.toStringAsFixed(6)},${position.longitude.toStringAsFixed(6)}',
        type: 'location',
      );
    } catch (e) {
      Get.snackbar('Erreur', 'Impossible de récupérer la position',
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: Colors.white);
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
      createdAt: DateTime.tryParse(row['created_at'] ?? '') ?? DateTime.now(),
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
          ? DateTime.tryParse(row['read_at'].toString())
          : null,
      reactions: reactions,
      storyReply: storyReply,
      replyTo: replyTo,
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
    final c = color ?? Colors.white;
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
