import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/services/supabase_service.dart';
import 'package:rencontre/core/services/revenue_cat_service.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/main_navigation.dart';

/// Une personne qui m'a liké ou qui a vu mon profil (onglet ❤️).
/// [id] vide = carte « mystère » (on connaît seulement le nombre).
class PersonneInsight {
  final String id;
  final String name;
  final String? photoUrl;
  final int? age;
  final bool enLigne;
  final DateTime? date;

  const PersonneInsight({
    required this.id,
    required this.name,
    this.photoUrl,
    this.age,
    this.enLigne = false,
    this.date,
  });
}

class ProfileInsightsController extends GetxController {
  final _sb = Supabase.instance.client;
  final _box = GetStorage();

  static const _cleVuJusqua = 'likes_vus_jusqua';
  static const _cleMasques = 'likes_masques';
  static const _limite = 100;

  final RxInt viewersCount = 0.obs;
  final RxInt likersCount = 0.obs;
  final RxInt matchesCount = 0.obs;
  final RxBool isLoading = false.obs;

  final RxList<PersonneInsight> likers = <PersonneInsight>[].obs;
  final RxList<PersonneInsight> viewers = <PersonneInsight>[].obs;

  /// Dernière visite de l'onglet ❤️ : ce qui est arrivé après est « Nouveau ».
  final Rxn<DateTime> vuJusqua = Rxn<DateTime>();

  /// Seuil utilisé pour les pastilles « Nouveau » pendant la visite en cours
  /// (vuJusqua est remis à maintenant dès l'ouverture pour vider le badge).
  final Rxn<DateTime> seuilNouveau = Rxn<DateTime>();

  final Set<String> _masques = {};
  Timer? _debounce;

  String? get _myId => _sb.auth.currentUser?.id;

  /// Premium = profil (webhook RevenueCat) OU RevenueCat en direct : juste
  /// après un achat, le profil n'est pas encore à jour.
  static bool isPremiumNow() => ControleurProfil.estPremiumMaintenant();

  bool estNouveau(PersonneInsight p) {
    final seuil = seuilNouveau.value;
    if (p.id.isEmpty || p.date == null) return false;
    return seuil == null || p.date!.isAfter(seuil);
  }

  int _nouveauxDepuis(List<PersonneInsight> l) {
    final seuil = vuJusqua.value;
    return l
        .where((p) =>
            p.id.isNotEmpty &&
            p.date != null &&
            (seuil == null || p.date!.isAfter(seuil)))
        .length;
  }

  /// Badge de l'icône ❤️ de la barre du bas.
  int get badgeNouveaux => _nouveauxDepuis(likers) + _nouveauxDepuis(viewers);

  @override
  void onInit() {
    super.onInit();
    final s = _box.read<String>(_cleVuJusqua);
    vuJusqua.value = s == null ? null : DateTime.tryParse(s);
    seuilNouveau.value = vuJusqua.value;
    _masques.addAll(List<String>.from(_box.read<List>(_cleMasques) ?? []));
    loadCounts();
  }

  @override
  void onReady() {
    super.onReady();
    // Nouveau like reçu (Realtime dans HomeController) → on recharge.
    if (Get.isRegistered<HomeController>()) {
      ever(Get.find<HomeController>().likedMeIds, (_) => _rechargerBientot());
    }
    // Ouverture de l'onglet ❤️ → le badge est vidé.
    if (Get.isRegistered<NavigationController>()) {
      final nav = Get.find<NavigationController>();
      ever(nav.currentIndex, (int i) {
        if (i == NavigationController.likesIndex) marquerVu();
      });
      // Ouverture directe sur l'onglet ❤️ (clic sur une notification)
      if (nav.currentIndex.value == NavigationController.likesIndex ||
          NavigationController.pendingIndex ==
              NavigationController.likesIndex) {
        marquerVu();
      }
    }
    // Premium activé → on recharge (vraies infos au lieu des cartes floues).
    if (Get.isRegistered<RevenueCatService>()) {
      ever(Get.find<RevenueCatService>().isPremium, (_) => _rechargerBientot());
    }
    // ⚡ Début / fin d'un Boost (droits Premium pendant le Boost)
    if (Get.isRegistered<HomeController>()) {
      ever(Get.find<HomeController>().boostActif, (_) => _rechargerBientot());
    }
  }

  @override
  void onClose() {
    _debounce?.cancel();
    super.onClose();
  }

  void _rechargerBientot() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), loadCounts);
  }

  void marquerVu() {
    seuilNouveau.value = vuJusqua.value;
    final now = DateTime.now().toUtc();
    vuJusqua.value = now;
    _box.write(_cleVuJusqua, now.toIso8601String());
  }

  /// ✕ sur une carte : on ne la montre plus (mémorisé sur le téléphone).
  void masquer(String id) {
    if (id.isEmpty) return;
    _masques.add(id);
    _box.write(_cleMasques, _masques.toList());
    likers.removeWhere((p) => p.id == id);
    likersCount.value = likers.length;
  }

  /// Après un like en retour devenu match : la personne quitte la grille.
  void retirerLiker(String id) {
    likers.removeWhere((p) => p.id == id);
    likersCount.value = likers.length;
    matchesCount.value++;
  }

  Future<void> loadCounts() async {
    final myId = _myId;
    if (myId == null) return;
    isLoading.value = true;
    try {
      final premium = isPremiumNow();
      final res = await Future.wait([
        _lignes(myId, likes: true, premium: premium),
        _lignes(myId, likes: false, premium: premium),
        _matchs(myId),
        _bloques(myId),
      ]);
      final rowsLikes = res[0] as List<Map<String, dynamic>>?;
      final rowsVues = res[1] as List<Map<String, dynamic>>?;
      final matchs = res[2] as Set<String>;
      final bloques = res[3] as Set<String>;
      matchesCount.value = matchs.length;

      // Un seul passage par personne (la plus récente), sans bloqués ni moi.
      List<Map<String, dynamic>> filtrer(List<Map<String, dynamic>> rows,
          {required bool sansMatchs}) {
        final vus = <String>{};
        return rows.where((r) {
          final id = r['id'] as String;
          if (id == myId || bloques.contains(id) || !vus.add(id)) return false;
          if (sansMatchs && (matchs.contains(id) || _masques.contains(id))) {
            return false;
          }
          return true;
        }).toList();
      }

      final l = rowsLikes == null ? null : filtrer(rowsLikes, sansMatchs: true);
      final v = rowsVues == null ? null : filtrer(rowsVues, sansMatchs: false);

      final profils = await _profils({
        ...?l?.map((r) => r['id'] as String),
        ...?v?.map((r) => r['id'] as String),
      });

      List<PersonneInsight> construire(List<Map<String, dynamic>> rows) => rows
          .map((r) {
            final p = profils[r['id']];
            return PersonneInsight(
              id: r['id'] as String,
              name: (p?['name'] as String?) ?? 'Utilisateur',
              photoUrl: p?['photo_url'] as String?,
              age: _age(p?['birthdate']),
              enLigne: SupabaseService.isReallyOnline(
                  p?['is_online'], p?['last_seen']),
              date: DateTime.tryParse(r['created_at']?.toString() ?? ''),
            );
          })
          .toList();

      if (l != null) {
        likers.assignAll(construire(l));
        likersCount.value = likers.length;
      } else {
        // Lecture directe refusée : on ne connaît que le nombre.
        likersCount.value = await _compter('compter_likes_recus');
        likers.assignAll(_mysteres(likersCount.value));
      }
      if (v != null) {
        viewers.assignAll(construire(v));
        viewersCount.value = viewers.length;
      } else {
        viewersCount.value = await _compter('compter_vues');
        viewers.assignAll(_mysteres(viewersCount.value));
      }
    } catch (_) {
      // ✅ Sans catch, une erreur réseau devenait une exception non gérée.
    } finally {
      isLoading.value = false;
    }
  }

  List<PersonneInsight> _mysteres(int n) => List.generate(
      n.clamp(0, 6), (_) => const PersonneInsight(id: '', name: ''));

  Future<int> _compter(String rpc) async {
    try {
      final n = await _sb.rpc(rpc);
      if (n is int) return n;
    } catch (_) {}
    return 0;
  }

  /// Lignes {id, created_at} les plus récentes d'abord.
  /// Premium → RPC (vérifiée côté serveur) ; sinon (ou si la RPC refuse,
  /// ex. juste après l'achat) → lecture directe, affichée floutée.
  /// null = lecture impossible.
  Future<List<Map<String, dynamic>>?> _lignes(String myId,
      {required bool likes, required bool premium}) async {
    if (premium) {
      try {
        final res = await _sb.rpc(likes ? 'qui_m_a_like' : 'qui_m_a_vu',
            params: {'p_limit': _limite});
        return (res as List)
            .map((r) => {'id': r['id'] as String, 'created_at': r['created_at']})
            .toList();
      } catch (_) {}
    }
    try {
      final idKey = likes ? 'from_user_id' : 'viewer_id';
      final rows = await _sb
          .from(likes ? 'likes' : 'profile_views')
          .select('$idKey, created_at')
          .eq(likes ? 'to_user_id' : 'viewed_id', myId)
          .order('created_at', ascending: false)
          .limit(_limite);
      return (rows as List)
          .map((r) => {'id': r[idKey] as String, 'created_at': r['created_at']})
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _matchs(String myId) async {
    try {
      final rows = await _sb
          .from('matches')
          .select('user1_id, user2_id')
          .or('user1_id.eq.$myId,user2_id.eq.$myId');
      return (rows as List).map((r) {
        final u1 = r['user1_id'] as String;
        return u1 == myId ? r['user2_id'] as String : u1;
      }).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<Set<String>> _bloques(String myId) async {
    try {
      final me = await _sb
          .from('profiles')
          .select('blocked_users')
          .eq('id', myId)
          .maybeSingle();
      return Set<String>.from(me?['blocked_users'] ?? []);
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, Map<String, dynamic>>> _profils(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _sb
        .from('profiles')
        .select('id, name, photo_url, birthdate, is_online, last_seen')
        .inFilter('id', ids.toList());
    return {
      for (final p in (rows as List))
        p['id'] as String: Map<String, dynamic>.from(p as Map)
    };
  }

  /// null si la date de naissance est absente (plus de « 18 ans » inventé).
  int? _age(dynamic birthdate) {
    final birth = DateTime.tryParse(birthdate?.toString() ?? '');
    if (birth == null) return null;
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }
}
