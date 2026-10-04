import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:rencontre/core/utils/video_init.dart';
import 'package:video_player/video_player.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/services/moderation_service.dart';
import 'package:rencontre/shared/models/story_model.dart';
import 'package:rencontre/shared/models/user_model.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/core/theme/app_theme.dart';

/// Ville proposée par le mode voyage (table villes_voyage).
class VilleVoyage {
  final String nom;
  final double lat;
  final double lng;
  final String pays;
  final String drapeau;
  final int? nbProfils; // profils à moins de 30 km (null = inconnu)
  const VilleVoyage(this.nom, this.lat, this.lng,
      {this.pays = "Côte d'Ivoire", this.drapeau = '🇨🇮', this.nbProfils});

  String get libelle => '$nom, $pays';

  Map<String, dynamic> toJson() =>
      {'nom': nom, 'lat': lat, 'lng': lng, 'pays': pays, 'drapeau': drapeau};

  static VilleVoyage? fromJson(dynamic m) {
    if (m is! Map) return null;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (m['nom'] == null || lat == null || lng == null) return null;
    return VilleVoyage(m['nom'] as String, lat, lng,
        pays: (m['pays'] as String?) ?? "Côte d'Ivoire",
        drapeau: (m['drapeau'] as String?) ?? '',
        nbProfils: (m['nb_profils'] as num?)?.toInt());
  }
}

class HomeController extends GetxController with WidgetsBindingObserver {
  final _service = SupabaseService();
  final _storageBox = GetStorage();

  final RxList<UserModel> _allUsers = <UserModel>[].obs;
  final RxList<UserModel> profiles = <UserModel>[].obs;
  final RxBool isLoading = false.obs;
  RxBool get isLoadingUsers => isLoading;

  final Rx<UserModel?> _myProfile = Rx<UserModel?>(null);
  UserModel? get myProfile => _myProfile.value;

  final RxList<StoryModel> _allStories = <StoryModel>[].obs;
  final Set<String> _viewedStoryIds = {};
  final RxList<StoryModel> _discoverOrder = <StoryModel>[].obs;

  // Stories signalées par moi : masquées définitivement (mémorisé sur
  // l'appareil ; elles expirent de toute façon côté serveur).
  static const _kHiddenStoriesKey = 'hidden_story_ids';
  late final Set<String> _hiddenStoryIds = {
    ...(_storageBox.read<List>(_kHiddenStoriesKey) ?? const [])
        .whereType<String>(),
  };

  final RxSet<String> likedMeIds = <String>{}.obs;
  RealtimeChannel? _likesChannel;

  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(seconds: 60);

  Timer? _offlineTimer;
  StreamSubscription<Position>? _positionStreamSub;

  RealtimeChannel? _onlineChannel;
  RealtimeChannel? _storiesChannel; // ✅ auto-refresh des stories

  double? _myLat;
  double? _myLng;

  // ✈️ MODE VOYAGE (Premium) : les profils et distances sont calculés depuis
  // une ville choisie au lieu de ma position. Ma vraie position reste celle
  // publiée (les autres ne me voient pas « déplacé »).
  // Liste de secours (Côte d'Ivoire) tant que la table villes_voyage n'a pas
  // répondu (script 20261003000024). Les pays s'ouvrent depuis Supabase.
  static const villesParDefaut = <VilleVoyage>[
    VilleVoyage('Abidjan', 5.3600, -4.0083),
    VilleVoyage('Bouaké', 7.6906, -5.0303),
    VilleVoyage('Yamoussoukro', 6.8276, -5.2893),
    VilleVoyage('San-Pédro', 4.7485, -6.6363),
    VilleVoyage('Korhogo', 9.4580, -5.6296),
    VilleVoyage('Daloa', 6.8774, -6.4502),
    VilleVoyage('Man', 7.4125, -7.5536),
    VilleVoyage('Gagnoa', 6.1319, -5.9506),
    VilleVoyage('Grand-Bassam', 5.2118, -3.7388),
    VilleVoyage('Assinie', 5.1300, -3.2900),
  ];
  static const _kVilleVoyage = 'ville_voyage';
  final Rxn<VilleVoyage> villeVoyage = Rxn<VilleVoyage>();
  final RxList<VilleVoyage> villesDisponibles =
      <VilleVoyage>[...villesParDefaut].obs;

  /// Villes actives (tous pays ouverts) + nombre de profils autour.
  Future<void> chargerVillesVoyage() async {
    try {
      final rows = await Supabase.instance.client
          .rpc('villes_voyage_disponibles') as List;
      final villes = rows.map(VilleVoyage.fromJson).whereType<VilleVoyage>();
      if (villes.isNotEmpty) villesDisponibles.assignAll(villes);
    } catch (e) {
      debugPrint('chargerVillesVoyage : $e'); // liste de secours gardée
    }
  }

  VilleVoyage? get _villeActive {
    final v = villeVoyage.value;
    if (v == null || !ControleurProfil.estPremiumMaintenant()) return null;
    return v;
  }

  /// Ville explorée complète (null = ma position).
  VilleVoyage? get villeVoyageChoisie => _villeActive;

  /// Ville explorée (null = ma position). Ignorée si le Premium a expiré.
  String? get villeVoyageActive => _villeActive?.nom;

  double? get _latRecherche => _villeActive?.lat ?? _myLat;
  double? get _lngRecherche => _villeActive?.lng ?? _myLng;

  /// null = revenir à ma position.
  Future<void> choisirVilleVoyage(VilleVoyage? ville) async {
    villeVoyage.value = ville;
    if (ville == null) {
      _storageBox.remove(_kVilleVoyage);
    } else {
      _storageBox.write(_kVilleVoyage, ville.toJson());
    }
    await loadProfiles();
    await loadStories();
  }

  final RxBool locationError = false.obs;
  final RxString filterMode = 'all'.obs;
  final RxString filterGender = 'tous'.obs;
  final RxDouble filterDistance = 50.0.obs;
  // Filtre par âge (70 = « 70 ans et plus »)
  static const ageMin = 18.0, ageMax = 70.0;
  final Rx<RangeValues> filterAge = const RangeValues(ageMin, ageMax).obs;
  bool get filtreAgeActif =>
      filterAge.value.start > ageMin || filterAge.value.end < ageMax;

  // ⭐ FAVORIS (privés : la personne ne sait pas qu'elle est en favori)
  final RxSet<String> favoris = <String>{}.obs;

  bool estFavori(String userId) => favoris.contains(userId);

  Future<void> chargerFavoris() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('favoris')
          .select('favori_id')
          .eq('user_id', uid);
      favoris.assignAll((rows as List).map((r) => r['favori_id'] as String));
    } catch (e) {
      debugPrint('chargerFavoris error: $e'); // table absente : script SQL
    }
  }

  /// Ajoute / retire un favori. Renvoie le nouvel état (null = échec).
  Future<bool?> basculerFavori(String userId) async {
    final uid = _myUid;
    if (uid == null || uid == userId) return null;
    final ajouter = !favoris.contains(userId);
    ajouter ? favoris.add(userId) : favoris.remove(userId);
    try {
      final db = Supabase.instance.client.from('favoris');
      if (ajouter) {
        // ignoreDuplicates : pas de règle UPDATE sur favoris (double tap)
        await db.upsert({'user_id': uid, 'favori_id': userId},
            ignoreDuplicates: true);
      } else {
        await db.delete().eq('user_id', uid).eq('favori_id', userId);
      }
      return ajouter;
    } catch (e) {
      debugPrint('basculerFavori error: $e');
      ajouter ? favoris.remove(userId) : favoris.add(userId);
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ NOUVEAU — état d'upload de story façon Snapchat/TikTok
  // ═══════════════════════════════════════════════════════════════
  final RxBool isUploadingStory = false.obs;
  final RxDouble storyUploadProgress = 0.0.obs;
  final Rx<String?> storyUploadPreviewPath = Rx<String?>(null);
  final RxBool storyUploadIsVideo = false.obs;

  // ═══════════════════════════════════════════════════════════════
  // ✅ NOUVEAU — cache partagé de médias de story (perf d'ouverture)
  // Permet de précharger l'image/vidéo d'une story pendant que
  // l'utilisateur est encore sur l'écran d'accueil, pour un affichage
  // instantané dès l'ouverture du StoryViewerScreen.
  // ═══════════════════════════════════════════════════════════════
  final Map<String, VideoPlayerController> storyVideoCache = {};
  final List<String> _videoCacheOrder = [];
  static const int _maxCachedVideos = 4;
  final Set<String> _precachedImageIds = {};

  // ═══════════════════════════════════════════════════════════════
  // ✅ NOUVEAU — essai Premium local (30 minutes, une seule fois par
  // COMPTE — les clés de stockage sont rattachées à l'uid connecté,
  // pour qu'un changement de compte sur le même appareil n'hérite
  // jamais de l'essai d'un autre utilisateur) + échéance d'"offre de
  // lancement" pour le paywall. Persisté avec GetStorage pour
  // survivre au redémarrage de l'app.
  //
  // ⚠️ Cet essai est purement LOCAL : il ne met pas à jour la colonne
  // `is_premium` en base Supabase. Seules les parties de l'app qui
  // vérifient explicitement `hasActiveTrial` (comme cette grille)
  // traitent l'utilisateur comme premium pendant l'essai — une
  // vérification côté base de données (RLS, autre écran, autre
  // appareil) ne le verra pas comme premium. Si tu veux que l'essai
  // soit visible partout (y compris depuis un autre appareil), il
  // faudrait le synchroniser en base (ex: colonne `trial_until` sur
  // `profiles`) — dis-le-moi si tu veux qu'on ajoute ça.
  // ═══════════════════════════════════════════════════════════════
  static const _kOfferDeadlineKey = 'offer_deadline';
  DateTime? _offerDeadlineCache;

  // ✅ Compteur purement technique : incrémenté à chaque changement
  // d'état de l'essai pour que les Obx() qui lisent hasActiveTrial
  // se reconstruisent, alors que la vraie source de vérité reste
  // toujours relue fraîchement depuis le stockage (scopé par uid).
  final RxInt _trialTick = 0.obs;

  String _trialUntilKeyFor(String uid) => 'trial_until_$uid';
  String _trialUsedKeyFor(String uid) => 'trial_used_$uid';

  bool get hasUsedTrial {
    final uid = _myUid;
    if (uid == null) return false;
    return _storageBox.read<bool>(_trialUsedKeyFor(uid)) ?? false;
  }

  DateTime? get _trialUntilForCurrentUser {
    final uid = _myUid;
    if (uid == null) return null;
    final str = _storageBox.read<String>(_trialUntilKeyFor(uid));
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  bool get hasActiveTrial {
    _trialTick.value; // ✅ dépendance Obx — voir commentaire ci-dessus
    final until = _trialUntilForCurrentUser;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Démarre l'essai Premium gratuit de 30 minutes pour le compte
  /// ACTUELLEMENT connecté. Ne fait rien si déjà utilisé une fois sur
  /// ce compte, ou déjà actif.
  Future<void> startFreeTrial() async {
    final uid = _myUid;
    if (uid == null) return;
    if (hasUsedTrial || hasActiveTrial) return;
    final until = DateTime.now().add(const Duration(minutes: 30));
    await _storageBox.write(_trialUntilKeyFor(uid), until.toIso8601String());
    await _storageBox.write(_trialUsedKeyFor(uid), true);
    _trialTick.value++;
  }

  /// Échéance de "l'offre de lancement" affichée sur le paywall —
  /// fixée à 24h après la première fois qu'elle est consultée, puis
  /// stable (persistée) tant qu'elle n'est pas dépassée ; se
  /// renouvelle automatiquement pour 24h de plus une fois expirée.
  DateTime get offerDeadline {
    if (_offerDeadlineCache != null &&
        DateTime.now().isBefore(_offerDeadlineCache!)) {
      return _offerDeadlineCache!;
    }
    final str = _storageBox.read<String>(_kOfferDeadlineKey);
    DateTime? d = str != null ? DateTime.tryParse(str) : null;
    if (d == null || DateTime.now().isAfter(d)) {
      d = DateTime.now().add(const Duration(hours: 24));
      _storageBox.write(_kOfferDeadlineKey, d.toIso8601String());
    }
    _offerDeadlineCache = d;
    return d;
  }

  String? get _myUid => _service.currentUserId;

  // ✅ Chargement identique pour tous — on récupère assez de profils
  // pour que même un utilisateur gratuit les VOIE dans la grille
  // (façon Grindr). Le blocage se fait à l'ouverture, pas au chargement.
  int get _profileLimit => 600;

  // ✅ NOUVEAU — nombre de profils que l'utilisateur peut réellement
  // OUVRIR/consulter. Premium OU essai gratuit actif → illimité (dans
  // la limite chargée) ; sinon, limite gratuite. Au-delà, le tap doit
  // proposer le passage Premium au lieu de naviguer vers le profil.
  int get unlockedProfileCount {
    final isPremium = ControleurProfil.estPremiumMaintenant();
    if (isPremium || hasActiveTrial) return 600;
    return 15;
  }

  // ✅ Toutes les stories actives que je peux voir (RLS filtre déjà les "amis" non autorisées), hors les miennes
  List<StoryModel> get stories {
    final seen = <String>{};
    final result = <StoryModel>[];
    for (final s
        in _allStories.where((s) => s.userId != _myUid && s.isActive)) {
      if (!seen.contains(s.userId)) {
        seen.add(s.userId);
        result.add(s.copyWith(isSeen: _viewedStoryIds.contains(s.id)));
      }
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ TOUTES LES STORIES DES AUTRES — plus de distinction
  // amis/suivis/découvrir depuis le retrait des abonnements
  // ═══════════════════════════════════════════════════════════════

  List<StoryModel> get discoverStories => _discoverOrder;

  void _buildDiscoverOrder() {
    final myUid = _myUid ?? '';
    bool vu(StoryModel s) =>
        s.isSeen || s.viewedBy.contains(myUid) || _viewedStoryIds.contains(s.id);

    // ✅ Toutes les stories de chaque profil (et plus seulement la
    // première), regroupées par profil dans l'ordre chronologique.
    final byUser = <String, List<StoryModel>>{};
    for (final s
        in _allStories.where((s) => s.userId != _myUid && s.isActive)) {
      byUser
          .putIfAbsent(s.userId, () => [])
          .add(s.copyWith(isSeen: _viewedStoryIds.contains(s.id)));
    }
    for (final l in byUser.values) {
      l.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    // Ordre des profils : ceux qui ont du nouveau d'abord (Premium en
    // tête, le reste mélangé), puis ceux déjà entièrement vus.
    final unseen = <List<StoryModel>>[];
    final dejaVues = <List<StoryModel>>[];
    for (final l in byUser.values) {
      (l.every(vu) ? dejaVues : unseen).add(l);
    }

    unseen.shuffle(Random());
    final premiumUnseen = unseen.where((l) => l.first.isPremium);
    final autresUnseen = unseen.where((l) => !l.first.isPremium);

    dejaVues.sort((a, b) => a.last.createdAt.compareTo(b.last.createdAt));

    final fresh = [
      ...premiumUnseen,
      ...autresUnseen,
      ...dejaVues,
    ].expand((l) => l).toList();

    // ✅ Ordre STABLE : la liste est affichée en continu dans le fil
    // Découvrir. La remélanger à chaque loadStories (realtime, reprise,
    // actualisation) décalait les pages sous les yeux de l'utilisateur.
    // On garde les stories déjà présentes à leur place (données mises à
    // jour), on retire celles qui ont disparu, et on ajoute les
    // nouvelles à la fin selon la règle habituelle.
    final previous = _discoverOrder.toList();
    if (previous.isEmpty) {
      _discoverOrder.value = fresh;
      return;
    }
    final freshById = {for (final s in fresh) s.id: s};
    final kept = <StoryModel>[];
    final keptIds = <String>{};
    for (final old in previous) {
      final updated = freshById[old.id];
      if (updated != null) {
        kept.add(updated);
        keptIds.add(old.id);
      }
    }
    final added = fresh.where((s) => !keptIds.contains(s.id));
    _discoverOrder.value = [...kept, ...added];
  }

  StoryModel? get myActiveStory =>
      _allStories.where((s) => s.userId == _myUid && s.isActive).firstOrNull;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    // Ville gardée en mémoire (avec ses coordonnées : utilisable tout de
    // suite). Ancien format = juste le nom d'une ville ivoirienne.
    final gardee = _storageBox.read(_kVilleVoyage);
    villeVoyage.value = gardee is String
        ? villesParDefaut.firstWhereOrNull((v) => v.nom == gardee)
        : VilleVoyage.fromJson(gardee);
    chargerVillesVoyage();
    _init();
    chargerFavoris();
  }

  // ✅ Chaque étape est isolée : une erreur réseau sur l'une d'elles
  // (ex: _loadMyProfile) n'empêche plus le reste de l'initialisation
  // (profils, stories, likes, heartbeat, realtime, jeton FCM).
  Future<void> _safeStep(String label, FutureOr<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      debugPrint('HomeController _init [$label] error: $e');
    }
  }

  Future<void> _init() async {
    await _safeStep('loadMyProfile', _loadMyProfile);

    isLoading.value = true;

    await Future.wait([
      _safeStep('locateMe', _locateMe),
      _safeStep('setOnline', () => _service.setOnline(true)),
    ]);

    await Future.wait([
      _safeStep('loadProfiles', loadProfiles),
      _safeStep('loadStories', loadStories),
      _safeStep('loadLikedMe', loadLikedMe),
    ]);
    isLoading.value = false;

    await _safeStep('heartbeat', _startHeartbeat);
    await _safeStep('onlineChanges', _subscribeToOnlineChanges);
    await _safeStep('likes', _subscribeToLikes);
    await _safeStep('stories', _subscribeToStories);
    await _safeStep('fcmToken', _ensureFcmToken);
  }

  void _subscribeToOnlineChanges() {
    _onlineChannel = Supabase.instance.client
        .channel('profiles:online')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (payload) {
            final updated = payload.newRecord;
            final userId = updated['id'] as String?;
            if (userId == null || userId == _myUid) return;

            // ✅ Ignore tôt les profils qui ne sont pas dans la liste
            // chargée (la grande majorité des événements), et ne touche
            // aux listes réactives que si le statut en ligne a changé
            // (évite une reconstruction de la grille à chaque heartbeat).
            final idx = profiles.indexWhere((u) => u.id == userId);
            final idx2 = _allUsers.indexWhere((u) => u.id == userId);
            if (idx == -1 && idx2 == -1) return;

            final isOnline = SupabaseService.isReallyOnline(
                updated['is_online'], updated['last_seen']);

            if (idx != -1 && profiles[idx].isOnline != isOnline) {
              profiles[idx] = profiles[idx].copyWith(isOnline: isOnline);
            }
            if (idx2 != -1 && _allUsers[idx2].isOnline != isOnline) {
              _allUsers[idx2] = _allUsers[idx2].copyWith(isOnline: isOnline);
            }
          },
        )
        .subscribe();
  }

  // ✅ auto-refresh des stories (insert / update / delete)
  void _subscribeToStories() {
    _storiesChannel = Supabase.instance.client
        .channel('stories:realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'stories',
          callback: (_) => _scheduleStoriesReload(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'stories',
          callback: (payload) => _patchStoryLocally(payload.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'stories',
          callback: (_) => _scheduleStoriesReload(),
        )
        .subscribe();
  }

  // ✅ Anti-rebond : une rafale d'insertions/suppressions de stories
  // (tous les clients reçoivent chaque événement) ne déclenche plus
  // qu'un seul rechargement complet.
  Timer? _storiesReloadDebounce;
  static const _storiesReloadDelay = Duration(seconds: 2);

  void _scheduleStoriesReload() {
    _storiesReloadDebounce?.cancel();
    _storiesReloadDebounce = Timer(_storiesReloadDelay, () {
      _storiesReloadDebounce = null;
      loadStories();
    });
  }

  void _patchStoryLocally(Map<String, dynamic> row) {
    final id = row['id'] as String?;
    if (id == null) return;
    final idx = _allStories.indexWhere((s) => s.id == id);
    if (idx == -1) return;

    final viewedBy = List<String>.from(row['viewed_by'] ?? []);
    final uid = _myUid ?? '';

    _allStories[idx] = _allStories[idx].copyWith(
      isSeen: viewedBy.contains(uid) || _viewedStoryIds.contains(id),
      isPinned: row['is_pinned'] ?? _allStories[idx].isPinned,
      viewedBy: viewedBy,
    );
  }

  Future<void> _ensureFcmToken() async {
    try {
      final uid = _myUid;
      if (uid == null) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', uid);
    } catch (e) {
      debugPrint('_ensureFcmToken error: $e');
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
      await _service.heartbeat();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _offlineTimer?.cancel();
        _offlineTimer = null;
        _service.setOnline(true);
        _startHeartbeat();
        _ensureFcmToken();
        _silentRefresh();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _heartbeatTimer?.cancel();
        _offlineTimer?.cancel();
        _offlineTimer = Timer(const Duration(minutes: 5), () {
          _service.setOnline(false);
        });
        break;
    }
  }

  Future<void> _silentRefresh() async {
    try {
      final fetched = await _service.fetchProfiles(
        myLat: _latRecherche,
        myLng: _lngRecherche,
        limit: _profileLimit,
      );
      _allUsers.value = fetched;
      profiles.value = fetched;
      await loadStories();
      await loadLikedMe();
    } catch (_) {}
  }

  Future<void> _loadMyProfile() async {
    _myProfile.value = await _service.fetchMyProfile();
  }

  /// Recharge mon profil (ex. : Boost accordé par le serveur).
  Future<void> rafraichirMonProfil() async {
    try {
      await _loadMyProfile();
    } catch (_) {}
  }

  Future<void> _locateMe() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        locationError.value = true;
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          locationError.value = true;
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        locationError.value = true;
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );
      _myLat = pos.latitude;
      _myLng = pos.longitude;
      locationError.value = false;
      unawaited(_updateLocationIfAllowed(pos.latitude, pos.longitude));
      _startListeningToPositionChanges();
    } catch (e) {
      locationError.value = true;
      debugPrint('_locateMe error: $e');
    }
  }

  void _startListeningToPositionChanges() {
    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50, // recalcule seulement après 50m de déplacement
      ),
    ).listen((pos) {
      _myLat = pos.latitude;
      _myLng = pos.longitude;
      _updateDistancesLocally();
      unawaited(_updateLocationIfAllowed(pos.latitude, pos.longitude));
    });
  }

  // ✅ Ne publie plus la position en base quand l'utilisateur est en
  // mode fantôme ou invisible sur la carte (la position locale reste
  // utilisée pour les distances). Conditions reprises à l'identique de
  // MapController.estInvisible / estFantome.
  Future<void> _updateLocationIfAllowed(double lat, double lng) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      // ✅ select('*') : certaines colonnes de la carte (map_visible…)
      // peuvent manquer en base ; une liste explicite faisait échouer la
      // requête et bloquait toute mise à jour de position.
      final data = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (data != null) {
        final now = DateTime.now();

        // estInvisible
        final mapVisible = data['map_visible'] ?? true;
        final invisibleUntil = data['map_invisible_until'] != null
            ? StoryModel.tryParseDbTimestamp(data['map_invisible_until'])
            : null;
        final estInvisible = !mapVisible ||
            (invisibleUntil != null && now.isBefore(invisibleUntil));

        // estFantome
        final isGhost = data['is_ghost'] ?? false;
        final isPremium = data['is_premium'] ?? false;
        final ghostUntil = data['ghost_until'] != null
            ? StoryModel.tryParseDbTimestamp(data['ghost_until'])
            : null;
        final estFantome = isPremium &&
            isGhost &&
            !(ghostUntil != null && now.isAfter(ghostUntil));

        if (estInvisible || estFantome) return;
      }
      await _service.updateLocation(lat, lng);
    } catch (e) {
      debugPrint('_updateLocationIfAllowed error: $e');
    }
  }

  void _updateDistancesLocally() {
    // En mode voyage, les distances sont relatives à la ville choisie.
    if (_villeActive != null) return;
    if (_myLat == null || _myLng == null) return;
    final updated = _allUsers.map((u) {
      if (u.latitude != null && u.longitude != null) {
        final d = _distanceKm(_myLat!, _myLng!, u.latitude!, u.longitude!);
        return u.copyWith(distanceMeters: d * 1000);
      }
      return u;
    }).toList();
    _allUsers.value = updated;
    profiles.value = updated;
  }

  Future<void> loadProfiles() async {
    isLoading.value = true;
    try {
      final fetched = await _service.fetchProfiles(
        myLat: _latRecherche,
        myLng: _lngRecherche,
        limit: _profileLimit,
      );
      _allUsers.value = fetched;
      profiles.value = fetched;
    } catch (e) {
      debugPrint('loadProfiles error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  // Masque une story (après signalement) et la retire des listes.
  void hideStory(String storyId) {
    _hiddenStoryIds.add(storyId);
    try {
      _storageBox.write(_kHiddenStoriesKey, _hiddenStoryIds.toList());
    } catch (_) {}
    _allStories.removeWhere((s) => s.id == storyId);
    _buildDiscoverOrder();
  }

  void removeUser(String userId) {
    _allUsers.removeWhere((u) => u.id == userId);
    profiles.removeWhere((u) => u.id == userId);
  }

  void setFilter(String mode) => filterMode.value = mode;

  // ✅ MODIFIÉ — tri systématique du profil le plus proche
  // au plus éloigné, quel que soit le filtre actif (Tous /
  // En ligne / Proche...). Les profils sans distance connue
  // (localisation indisponible) sont relégués en fin de liste.
  List<UserModel> get filteredUsers {
    final age = filterAge.value;
    final list = profiles.where((u) {
      if (filterMode.value == 'online' && !u.isOnline) return false;
      if (filterMode.value == 'dispo' && !u.estDispo) return false;
      if (filterMode.value == 'favoris' && !favoris.contains(u.id)) {
        return false;
      }
      // Âge : les personnes qui cachent leur âge ne sont pas filtrées
      // (sinon le filtre révélerait leur tranche d'âge).
      if (filtreAgeActif && u.showBirthdate) {
        if (u.age < age.start) return false;
        if (age.end < ageMax && u.age > age.end) return false;
      }
      if (filterMode.value == 'new' && !u.isNewMember)
        return false; // ← ligne ajoutée
      if (filterMode.value == 'nearby') {
        final dist = u.distanceMeters;
        if (dist == null || dist > filterDistance.value * 1000) return false;
      }
      if (filterGender.value != 'tous') {
        final g = u.gender?.toLowerCase();
        if (g != filterGender.value.toLowerCase() &&
            g != null &&
            g != 'non précisé' &&
            g.isNotEmpty) {
          return false;
        }
      }
      if (filterMode.value != 'nearby') {
        final dist = u.distanceMeters;
        if (dist != null && dist > filterDistance.value * 1000) return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      // ⚡ Boost en cours : toujours en tête
      if (a.estBooste != b.estBooste) return a.estBooste ? -1 : 1;
      final da = a.distanceMeters;
      final db = b.distanceMeters;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return list;
  }

  static String formatDistance(double? meters) {
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  // ✅ Ouvre le profil dans un carrousel (swipe pour passer
  // au profil suivant, façon Grindr). On retrouve l'index du profil
  // cliqué dans la liste actuellement affichée (filteredUsers) et on
  // transmet toute la liste + cet index à l'écran de détail.
  bool openProfile(UserModel user) {
    final list = filteredUsers;
    final idx = list.indexWhere((u) => u.id == user.id);
    if (idx == -1) return false;

    // ✅ Même découpage verrouillé/déverrouillé que la grille
    // (_UsersGridScrollable) : pour un non-premium, seul le sous-ensemble
    // déverrouillé est transmis au carrousel — sinon un simple swipe
    // permettait de consulter les profils au-delà de la limite gratuite.
    final isPremium = ControleurProfil.estPremiumMaintenant();
    final unlockedCount = unlockedProfileCount;
    final hasLockedSection = !isPremium && list.length > unlockedCount;
    if (hasLockedSection && idx >= unlockedCount) return true; // bloqué
    final visibles = hasLockedSection ? list.sublist(0, unlockedCount) : list;

    Get.toNamed('/profile/view', arguments: {
      'profiles': visibles,
      'initialIndex': idx,
    });
    return false;
  }

  void openLocationSettings() => Geolocator.openLocationSettings();

  // ═══════════════════════════════════════════════════════════════
  // LIKES REÇUS
  // ═══════════════════════════════════════════════════════════════

  Future<void> loadLikedMe() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('likes')
          .select('from_user_id')
          .eq('to_user_id', uid);

      likedMeIds.assignAll(
          (data as List).map((r) => r['from_user_id'] as String));
    } catch (e) {
      debugPrint('loadLikedMe error: $e');
    }
  }

  void _subscribeToLikes() {
    final uid = _myUid;
    if (uid == null) return;
    _likesChannel = Supabase.instance.client
        .channel('likes:received')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'likes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'to_user_id',
            value: uid,
          ),
          callback: (payload) {
            final fromId = payload.newRecord['from_user_id'] as String?;
            if (fromId != null) likedMeIds.add(fromId);
          },
        )
        .subscribe();
  }

  bool userLikedMe(String userId) => likedMeIds.contains(userId);

  // ═══════════════════════════════════════════════════════════════
  // STORIES
  // ═══════════════════════════════════════════════════════════════

  Future<void> loadStories() async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      final data = await Supabase.instance.client
          .from('stories')
          .select(
              '*, profiles(name, photo_url, latitude, longitude, is_premium, '
              'is_online, last_seen, show_distance)')
          // ✅ UTC : une date locale "naïve" est lue comme UTC par Postgres
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);

      final stories = <StoryModel>[];
      for (final row in (data as List)) {
        if (_hiddenStoryIds.contains(row['id']?.toString())) continue;
        final profile = row['profiles'] as Map<String, dynamic>?;
        stories.add(_rowToStory(row, profile, hasChatted: true));
      }
      _allStories.value = stories;
      _buildDiscoverOrder();

      // ✅ Précharge la première story "à découvrir" pendant que
      // l'utilisateur est encore sur l'écran d'accueil, pour un
      // affichage instantané dès qu'il ouvre le viewer.
      if (discoverStories.isNotEmpty) {
        unawaited(preloadStoryMedia(discoverStories.first));
      }
      // ✅ Idem pour les premiers cercles de la rangée de l'accueil : avant,
      // le viewer ouvert depuis l'accueil téléchargeait tout au moment du
      // tap (alors que l'onglet Story, monté dès le lancement, était prêt).
      for (final s in stories.take(3)) {
        final premiere = storiesForUser(s.userId).firstOrNull;
        if (premiere != null) unawaited(preloadStoryMedia(premiere));
      }
    } catch (e) {
      debugPrint('loadStories error: $e');
    }
  }

  // ✅ NOUVEAU — précharge le média (image ou vidéo) d'une story donnée
  // sans l'afficher. Appelable depuis l'écran d'accueil (ex: onTapDown
  // sur un cercle de story) pour rendre l'ouverture du viewer instantanée.
  Future<void> preloadStoryMedia(StoryModel story) async {
    // Story texte : aucun média à précharger.
    if (story.isTextStory) return;
    if (story.isVideo) {
      if (storyVideoCache.containsKey(story.id)) return;
      try {
        final ctrl =
            VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl));
        storyVideoCache[story.id] = ctrl;
        _videoCacheOrder.add(story.id);
        _evictOldVideosIfNeeded();
        await initialiserUneFois(ctrl);
      } catch (e) {
        debugPrint('preloadStoryMedia video error: $e');
      }
    } else {
      if (_precachedImageIds.contains(story.id)) return;
      final ctx = Get.context;
      if (ctx == null) return;
      _precachedImageIds.add(story.id);
      try {
        await precacheImage(CachedNetworkImageProvider(story.mediaUrl), ctx);
      } catch (e) {
        debugPrint('preloadStoryMedia image error: $e');
      }
    }
  }

  void _evictOldVideosIfNeeded() {
    while (_videoCacheOrder.length > _maxCachedVideos) {
      final oldestId = _videoCacheOrder.removeAt(0);
      storyVideoCache.remove(oldestId)?.dispose();
    }
  }

  // ✅ Le viewer "récupère" un contrôleur préchargé : il est retiré du
  // cache partagé (pour que ce soit désormais le viewer qui gère son
  // cycle de vie/dispose) et renvoyé tel quel, initialisé ou non.
  VideoPlayerController? takeCachedVideoController(String storyId) {
    final ctrl = storyVideoCache.remove(storyId);
    if (ctrl != null) _videoCacheOrder.remove(storyId);
    return ctrl;
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // rayon de la Terre en km
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final lat1Rad = _deg2rad(lat1);
    final lat2Rad = _deg2rad(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return r * c;
  }

  double _deg2rad(double deg) => deg * pi / 180;

  StoryModel _rowToStory(
      Map<String, dynamic> row, Map<String, dynamic>? profile,
      {bool hasChatted = false}) {
    final viewedBy = List<String>.from(row['viewed_by'] ?? []);
    final uid = _myUid ?? '';
    double? distanceKm;
    final refLat = _latRecherche, refLng = _lngRecherche;
    if (refLat != null && refLng != null) {
      final lat = profile?['latitude']?.toDouble();
      final lng = profile?['longitude']?.toDouble();
      if (lat != null && lng != null) {
        distanceKm = _distanceKm(refLat, refLng, lat, lng);
      }
    }
    return StoryModel(
      id: row['id'] ?? '',
      userId: row['user_id'] ?? '',
      userName: profile?['name'] ?? 'Utilisateur',
      userPhotoUrl: profile?['photo_url'],
      mediaUrl: row['media_url'] ?? '',
      caption: row['caption'],
      legendeX: (row['legende_x'] as num?)?.toDouble(),
      legendeY: (row['legende_y'] as num?)?.toDouble(),
      legendeEchelle: (row['legende_echelle'] as num?)?.toDouble(),
      videoDebutMs: (row['video_debut_ms'] as num?)?.toInt(),
      videoFinMs: (row['video_fin_ms'] as num?)?.toInt(),
      isVideo: row['is_video'] ?? false,
      isSeen: viewedBy.contains(uid) || _viewedStoryIds.contains(row['id']),
      // ✅ Parse tolérant au fuseau (voir StoryModel.parseDbTimestamp)
      createdAt: StoryModel.parseDbTimestamp(row['created_at']),
      expiresAt: StoryModel.parseDbTimestamp(row['expires_at']),
      viewedBy: viewedBy,
      distanceKm: distanceKm,
      hasChatted: hasChatted,
      isPinned: row['is_pinned'] ?? false,
      isPremium: profile?['is_premium'] ?? false,
      visibility: row['visibility'] ?? 'public',
      isOnline: SupabaseService.isReallyOnline(
          profile?['is_online'], profile?['last_seen']),
      showDistance: profile?['show_distance'] ?? true,
      textContent: row['text_content'],
      bgColor: row['bg_color'],
    );
  }

  void markStoryAsSeen(String storyId) {
    // ✅ Évite les appels RPC en double pour une même story (viewer,
    // barre de stories et fil Découvrir peuvent la marquer).
    if (!_viewedStoryIds.add(storyId)) return;
    final idx = _allStories.indexWhere((s) => s.id == storyId);
    if (idx >= 0) _allStories[idx] = _allStories[idx].copyWith(isSeen: true);
    _markStorySeenInDb(storyId);
  }

  Future<void> _markStorySeenInDb(String storyId) async {
    final uid = _myUid;
    if (uid == null) return;
    try {
      await Supabase.instance.client.rpc('mark_story_seen', params: {
        'story_id_input': storyId,
        'viewer_id_input': uid,
      });
    } catch (e) {
      debugPrint('_markStorySeenInDb error: $e');
    }
  }

  bool userHasActiveStory(String userId) =>
      _allStories.any((s) => s.userId == userId && s.isActive);

  bool userStoryIsSeen(String userId) {
    final userStories =
        _allStories.where((s) => s.userId == userId && s.isActive);
    if (userStories.isEmpty) return true;
    return userStories.every((s) => s.isSeen || _viewedStoryIds.contains(s.id));
  }

  List<StoryModel> storiesForUser(String userId) =>
      _allStories.where((s) => s.userId == userId && s.isActive).toList();

  Future<void> setOnline(bool online) async => await _service.setOnline(online);

  // ✅ NOUVEAU — construit la chaîne complète de profils à parcourir
  // dans le viewer (comme WhatsApp/Telegram) : "Ma story" en premier
  // si elle existe, puis chaque profil de `stories`, dans l'ordre.
  // Centralisé ici pour que la barre d'accueil ET l'avatar dans le
  // chat utilisent exactement la même logique de navigation.
  ({List<StoryModel> stories, int startIndex}) buildStoryChain(
      String startUserId) {
    final combined = <StoryModel>[];
    int startIndex = 0;

    final my = myActiveStory;
    if (my != null) {
      final mine = storiesForUser(my.userId);
      final toAdd = mine.isNotEmpty ? mine : [my];
      if (startUserId == my.userId) startIndex = combined.length;
      combined.addAll(toAdd);
    }

    for (final s in stories) {
      final userStories = storiesForUser(s.userId);
      if (userStories.isEmpty) continue;
      if (s.userId == startUserId && s.userId != my?.userId) {
        startIndex = combined.length;
      }
      combined.addAll(userStories);
    }

    return (stories: combined, startIndex: startIndex);
  }

  // ═══════════════════════════════════════════════════════════════
  // ✅ NOUVEAU — PUBLICATION DE STORY FAÇON SNAPCHAT/TIKTOK
  // Le HomeController est persistant (permanent: true), donc l'upload
  // continue même si AddStoryScreen a déjà été fermé et détruit.
  // ═══════════════════════════════════════════════════════════════

  Future<void> publishStory({
    required File file,
    required bool isVideo,
    String? caption,
    required double durationHours,
    required String visibility,
    // Éditeur façon Snap (colonnes du script 20261003000023)
    Map<String, dynamic> edition = const {},
  }) async {
    final uid = _myUid;
    if (uid == null) return;

    isUploadingStory.value = true;
    storyUploadProgress.value = 0.0;
    storyUploadPreviewPath.value = file.path;
    storyUploadIsVideo.value = isVideo;

    try {
      final ext = file.path.split('.').last.toLowerCase();
      final fileName = '${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final storagePath = 'stories/$uid/$fileName';

      storyUploadProgress.value = 0.2;
      await Supabase.instance.client.storage.from('stories').upload(
            storagePath,
            file,
            fileOptions: const FileOptions(upsert: true),
          );
      storyUploadProgress.value = 0.65;

      final mediaUrl = Supabase.instance.client.storage
          .from('stories')
          .getPublicUrl(storagePath);

      final expiresAt =
          DateTime.now().add(Duration(minutes: (durationHours * 60).round()));

      final ligne = {
        'user_id': uid,
        'media_url': mediaUrl,
        'is_video': isVideo,
        'caption': caption,
        // ✅ UTC explicite (sinon décalage du fuseau côté Postgres)
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'viewed_by': [],
        'visibility': visibility,
      };
      Map<String, dynamic> inserted;
      try {
        inserted = await Supabase.instance.client
            .from('stories')
            .insert({...ligne, ...edition})
            .select('id')
            .single();
      } on PostgrestException catch (e) {
        // Colonnes de l'éditeur absentes (script pas encore exécuté) :
        // on publie quand même, sans position de légende ni découpe.
        if (edition.isEmpty || (e.code != 'PGRST204' && e.code != '42703')) {
          rethrow;
        }
        inserted = await Supabase.instance.client
            .from('stories')
            .insert(ligne)
            .select('id')
            .single();
      }
      storyUploadProgress.value = 0.8;

      // ✅ Modération : une story explicite est supprimée par le
      // serveur, une story douteuse reste cachée jusqu'à validation.
      final result =
          await ModerationService.story(inserted['id'].toString());

      storyUploadProgress.value = 1.0;
      await loadStories();

      final (titre, message) = switch (result) {
        ModerationResult.rejected => (
            'Story refusée',
            'Elle ne respecte pas nos règles (nudité ou contenu explicite).'
          ),
        ModerationResult.pending => (
            'Story en vérification',
            "Elle sera visible par les autres dès qu'elle sera validée."
          ),
        _ => (
            'Story publiée ✓',
            'Visible pendant ${_formatDurationLabel(durationHours)}'
          ),
      };
      Get.snackbar(
        titre,
        message,
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: Colors.white,
        duration: Duration(
            seconds: result == ModerationResult.approved ? 2 : 4),
      );
    } catch (e) {
      debugPrint('publishStory error: $e');
      Get.snackbar(
        'Erreur',
        "Impossible de publier la story",
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: Colors.white,
      );
    } finally {
      isUploadingStory.value = false;
      storyUploadPreviewPath.value = null;
      storyUploadProgress.value = 0.0;
    }
  }

  Future<void> publishTextStory({
    required String text,
    required String bgColorHex,
    required double durationHours,
    required String visibility,
  }) async {
    final uid = _myUid;
    if (uid == null) return;
    if (text.trim().isEmpty) return;

    isUploadingStory.value = true;
    try {
      final expiresAt =
          DateTime.now().add(Duration(minutes: (durationHours * 60).round()));

      await Supabase.instance.client.from('stories').insert({
        'user_id': uid,
        'media_url': null,
        'is_video': false,
        'text_content': text.trim(),
        'bg_color': bgColorHex,
        // ✅ UTC explicite (sinon décalage du fuseau côté Postgres)
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'viewed_by': [],
        'visibility': visibility,
      });

      await loadStories();

      Get.snackbar(
        'Story publiée ✓',
        'Visible pendant ${_formatDurationLabel(durationHours)}',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('publishTextStory error: $e');
      Get.snackbar(
        'Erreur',
        "Impossible de publier la story",
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.surface,
        colorText: Colors.white,
      );
    } finally {
      isUploadingStory.value = false;
    }
  }

  String _formatDurationLabel(double hours) {
    if (hours < 1) return '${(hours * 60).round()} min';
    if (hours < 24) return '${hours.round()}h';
    final days = hours / 24;
    if (days == days.roundToDouble()) return '${days.round()}j';
    return '${hours.round()}h';
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _offlineTimer?.cancel();
    _storiesReloadDebounce?.cancel();
    _onlineChannel?.unsubscribe();
    _likesChannel?.unsubscribe();
    _storiesChannel?.unsubscribe();
    for (final c in storyVideoCache.values) {
      c.dispose();
    }
    storyVideoCache.clear();
    _positionStreamSub?.cancel();
    super.onClose();
  }
}
