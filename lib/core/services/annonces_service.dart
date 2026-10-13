import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/i18n/traductions.dart';
import 'package:rencontre/core/services/avis_service.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fenêtres créées depuis le panneau admin (SQL 061) : annonce de l'équipe,
/// sondage à choix, ou note de satisfaction « Tu aimes Zamu ? ».
/// Une seule par lancement, et chaque fenêtre une seule fois par personne.
class AnnoncesService {
  AnnoncesService._();
  static bool _dejaVerifie = false;
  static SupabaseClient get _sb => Supabase.instance.client;

  /// À appeler une fois l'écran principal affiché.
  static Future<void> verifier() async {
    if (_dejaVerifie) return;
    _dejaVerifie = true;
    // Laisse l'app se charger avant d'afficher quoi que ce soit
    await Future.delayed(const Duration(seconds: 6));
    Map<String, dynamic>? a;
    try {
      final r = await _sb
          .rpc('annonce_a_afficher', params: {'p_langue': Langue.code});
      if (r is List && r.isNotEmpty) a = Map<String, dynamic>.from(r.first);
    } catch (_) {
      return; // SQL 061 pas encore passé
    }
    // Seulement sur l'écran principal (pas par-dessus la visite guidée,
    // une conversation…) ; sinon ce sera au prochain lancement.
    if (a == null || Get.isDialogOpen == true || Get.currentRoute != '/main') {
      return;
    }
    await Get.dialog(_FenetreAnnonce(annonce: a), barrierDismissible: false);
  }

  static Future<void> _repondre(String id,
      {int? choix, int? note, String? commentaire, bool ignoree = false}) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _sb.from('reponses_annonces').insert({
        'annonce_id': id,
        'user_id': uid,
        if (choix != null) 'choix': choix,
        if (note != null) 'note': note,
        if ((commentaire ?? '').trim().isNotEmpty)
          'commentaire': commentaire!.trim().substring(
              0, commentaire.trim().length.clamp(0, 1000)),
        'ignoree': ignoree,
      });
    } catch (e) {
      debugPrint('Réponse non enregistrée : $e');
    }
  }
}

class _FenetreAnnonce extends StatefulWidget {
  final Map<String, dynamic> annonce;
  const _FenetreAnnonce({required this.annonce});

  @override
  State<_FenetreAnnonce> createState() => _FenetreAnnonceState();
}

class _FenetreAnnonceState extends State<_FenetreAnnonce> {
  int? _choix;
  int _note = 0;
  final _commentaire = TextEditingController();

  String get _id => widget.annonce['id'] as String;
  String get _type => widget.annonce['type'] as String;

  List<String> get _options => [
        for (final c in (widget.annonce['choix'] as List? ?? const [])) '$c'
      ];

  bool get _peutValider => switch (_type) {
        'sondage' => _choix != null,
        'note' => _note > 0,
        _ => true,
      };

  Future<void> _valider() async {
    await AnnoncesService._repondre(_id,
        choix: _choix,
        note: _type == 'note' ? _note : null,
        commentaire: _commentaire.text);
    Get.back();
    if (_type == 'note' && _note >= 4) {
      // Très satisfait : bon moment pour une note sur le Play Store
      AvisService.momentPositif();
    } else if (_type != 'annonce') {
      Get.snackbar('🙏', 'Merci, ton avis nous aide à améliorer Zamu !'.tr,
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.surface,
          colorText: AppColors.textPrimary);
    }
  }

  @override
  void dispose() {
    _commentaire.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final texte = (widget.annonce['texte'] ?? '').toString();
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              switch (_type) { 'sondage' => '📊', 'note' => '💬', _ => '📣' },
              style: const TextStyle(fontSize: 38)),
          const SizedBox(height: 8),
          Text('${widget.annonce['titre']}',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          if (texte.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(texte,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: AppColors.textMuted, height: 1.45)),
          ],
          const SizedBox(height: 16),
          if (_type == 'sondage')
            for (var i = 0; i < _options.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _choix = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _choix == i
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _choix == i ? AppColors.accent : AppColors.border,
                          width: _choix == i ? 2 : 1),
                    ),
                    child: Text(_options[i],
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                ),
              ),
          if (_type == 'note')
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  iconSize: 38,
                  onPressed: () => setState(() => _note = i),
                  icon: Icon(
                      i <= _note ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFFFC83D)),
                ),
            ]),
          if (_type != 'annonce') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _commentaire,
              maxLines: 3,
              minLines: 1,
              maxLength: 1000,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: _type == 'note'
                    ? 'Qu\'est-ce qu\'on peut améliorer ? (facultatif)'.tr
                    : 'Un commentaire ? (facultatif)'.tr,
                hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 13),
                counterText: '',
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                disabledBackgroundColor: AppColors.surface2,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _peutValider ? _valider : null,
              child: Text(_type == 'annonce' ? 'OK'.tr : 'Envoyer'.tr,
                  style: const TextStyle(
                      color: AppColors.surAccent, fontWeight: FontWeight.w700)),
            ),
          ),
          if (_type != 'annonce')
            TextButton(
              onPressed: () {
                AnnoncesService._repondre(_id, ignoree: true);
                Get.back();
              },
              child: Text('Plus tard'.tr,
                  style: TextStyle(color: AppColors.textMuted)),
            ),
        ]),
      ),
    );
  }
}
