import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/profil/controleur/controleur_profil.dart';
import 'package:rencontre/shared/widgets/badge_verifie.dart';

// ─── VÉRIFICATION DU PROFIL PAR SELFIE ──────────────────────────────
// La personne imite une pose tirée au hasard ; l'équipe compare le
// selfie à ses photos dans le panneau admin, puis le selfie est
// supprimé. Validé → badge bleu « Profil vérifié ».

const _poses = [
  ('✌️', 'Fais le signe V avec ta main, à côté de ton visage'),
  ('👍', 'Lève le pouce à côté de ton visage'),
  ('☝️', "Lève l'index à côté de ton visage"),
  ('🖐️', 'Montre ta main ouverte à côté de ton visage'),
  ('👌', 'Fais le signe OK à côté de ton visage'),
];

/// Dernière demande de vérification de l'utilisateur connecté
/// (statut : en_attente / validee / refusee), ou null.
Future<Map<String, dynamic>?> derniereVerification() async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return null;
  try {
    return await Supabase.instance.client
        .from('verifications')
        .select('statut, motif, created_at')
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  } catch (_) {
    return null; // script SQL 049 pas encore appliqué
  }
}

class EcranVerification extends StatefulWidget {
  const EcranVerification({super.key});

  @override
  State<EcranVerification> createState() => _EcranVerificationState();
}

class _EcranVerificationState extends State<EcranVerification> {
  final _pose = _poses[Random().nextInt(_poses.length)];
  bool _chargement = true;
  bool _envoi = false;
  bool _verifie = false;
  Map<String, dynamic>? _demande;
  File? _selfie;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final ctrl = Get.find<ControleurProfil>();
    final d = await derniereVerification();
    if (!mounted) return;
    setState(() {
      _verifie = ctrl.monProfil.value?.estVerifie == true ||
          d?['statut'] == 'validee';
      _demande = d;
      _chargement = false;
    });
  }

  Future<void> _prendreSelfie() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1080,
      maxHeight: 1440,
      imageQuality: 80,
    );
    if (photo == null || !mounted) return;
    setState(() => _selfie = File(photo.path));
  }

  Future<void> _envoyer() async {
    final selfie = _selfie;
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (selfie == null || uid == null) return;
    setState(() => _envoi = true);
    final chemin = '$uid/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await sb.storage.from('verifications').upload(chemin, selfie,
          fileOptions: const FileOptions(contentType: 'image/jpeg'));
      await sb.rpc('demander_verification',
          params: {'p_chemin': chemin, 'p_pose': '${_pose.$1} ${_pose.$2}'});
      if (!mounted) return;
      setState(() {
        _selfie = null;
        _demande = {'statut': 'en_attente'};
      });
    } catch (e) {
      final msg = e.toString();
      _snack(msg.contains('deja_en_attente')
          ? 'Une demande est déjà en cours de vérification'
          : msg.contains('trop_de_demandes')
              ? 'Trop de demandes aujourd\'hui, réessaie demain'
              : msg.contains('deja_verifie')
                  ? 'Ton profil est déjà vérifié'
                  : 'Envoi impossible, vérifie ta connexion');
    } finally {
      if (mounted) setState(() => _envoi = false);
    }
  }

  void _snack(String texte) => Get.snackbar('Vérification', texte,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.surface,
      colorText: AppColors.textPrimary);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: Text('Vérifier mon profil',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18)),
      ),
      body: _chargement
          ? Center(child: CircularProgressIndicator(color: AppColors.accent))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: _contenu(),
            ),
    );
  }

  List<Widget> _contenu() {
    if (_verifie) {
      return [
        const SizedBox(height: 40),
        const Center(child: BadgeVerifie(size: 72)),
        const SizedBox(height: 16),
        _titre('Ton profil est vérifié'),
        _texte('Le badge bleu apparaît à côté de ton nom : les autres '
            'savent que tu es bien la personne de tes photos.'),
      ];
    }
    final statut = _demande?['statut'];
    if (statut == 'en_attente') {
      return [
        const SizedBox(height: 40),
        Center(
            child: Icon(Icons.hourglass_top_rounded,
                size: 64, color: AppColors.textMuted)),
        const SizedBox(height: 16),
        _titre('Vérification en cours'),
        _texte("L'équipe Zamu compare ton selfie à tes photos, en général "
            'sous 24 h. Tu recevras une notification.'),
      ];
    }
    return [
      if (statut == 'refusee') ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
              'Ta dernière demande a été refusée'
              '${(_demande?['motif'] ?? '').toString().isNotEmpty ? ' : ${_demande!['motif']}' : '.'}'
              ' Tu peux réessayer.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        ),
        const SizedBox(height: 16),
      ],
      const Center(child: BadgeVerifie(size: 48)),
      const SizedBox(height: 12),
      _titre('Obtiens le badge « Profil vérifié »'),
      _texte('Prouve que tu es bien la personne de tes photos. Les profils '
          'vérifiés inspirent confiance et reçoivent plus de messages.'),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Text(_pose.$1, style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ta pose',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(_pose.$2,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (_selfie != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Image.file(_selfie!, fit: BoxFit.cover)),
        ),
        const SizedBox(height: 16),
        _bouton(
            _envoi ? 'Envoi…' : 'Envoyer pour vérification',
            Icons.send_rounded,
            _envoi ? null : _envoyer,
            plein: true),
        const SizedBox(height: 10),
        _bouton('Reprendre la photo', Icons.refresh_rounded,
            _envoi ? null : _prendreSelfie),
      ] else
        _bouton('Prendre mon selfie', Icons.camera_alt_rounded,
            _prendreSelfie,
            plein: true),
      const SizedBox(height: 16),
      _texte('Ton selfie est vu uniquement par l\'équipe Zamu, jamais '
          'affiché sur ton profil, et supprimé après la vérification.',
          petit: true),
    ];
  }

  Widget _titre(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
      );

  Widget _texte(String t, {bool petit = false}) => Text(t,
      textAlign: TextAlign.center,
      style: TextStyle(
          fontSize: petit ? 12 : 14,
          height: 1.45,
          color: AppColors.textMuted));

  Widget _bouton(String libelle, IconData icone, VoidCallback? onTap,
          {bool plein = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: plein ? AppColors.accent : AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icone,
                size: 20,
                color: plein ? AppColors.surAccent : AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(libelle,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color:
                        plein ? AppColors.surAccent : AppColors.textPrimary)),
          ]),
        ),
      );
}
