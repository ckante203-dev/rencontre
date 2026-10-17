import 'package:flutter/material.dart';
import 'package:get_storage/get_storage.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/stories_une.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stories officielles « Zamu » (comme le compte WhatsApp qui annonce ses
/// nouveautés) : publiées depuis le panneau admin (SQL 062), montrées en
/// premier dans l'onglet Stories de tout le monde.
class RondZamuOfficiel extends StatefulWidget {
  const RondZamuOfficiel({super.key});

  @override
  State<RondZamuOfficiel> createState() => _RondZamuOfficielState();
}

class _RondZamuOfficielState extends State<RondZamuOfficiel> {
  static const _cleVues = 'stories_officielles_vues';
  List<StoryUne> _stories = const [];
  Set<String> _vues = {};

  @override
  void initState() {
    super.initState();
    try {
      _vues = {
        ...(GetStorage().read<List>(_cleVues) ?? const []).map((e) => '$e')
      };
    } catch (_) {}
    _charger();
  }

  Future<void> _charger() async {
    try {
      final rows = await Supabase.instance.client
          .from('stories_officielles')
          .select()
          .gt('expire_le', DateTime.now().toUtc().toIso8601String())
          .order('cree_le');
      final liste = [
        for (final r in rows as List)
          StoryUne(
            id: r['id'] as String,
            userId: '',
            mediaUrl: (r['media_url'] as String?) ?? '',
            isVideo: r['is_video'] == true,
            texte: r['texte'] as String?,
            fond: r['fond'] as String?,
            legende: r['legende'] as String?,
          )
      ];
      if (mounted) setState(() => _stories = liste);
    } catch (_) {} // table absente (SQL 062 pas encore passé)
  }

  Future<void> _ouvrir() async {
    final premiere = _stories.indexWhere((s) => !_vues.contains(s.id));
    await ouvrirVueStories(_stories, premiere < 0 ? 0 : premiere,
        // Vue comptée sur le serveur : le panneau admin affiche le total
        onVue: (s) => Supabase.instance.client
            .rpc('vue_story_officielle', params: {'p_story': s.id})
            .catchError((_) => null)); // SQL 076 pas encore passé
    setState(() => _vues.addAll(_stories.map((s) => s.id)));
    try {
      GetStorage().write(_cleVues, _vues.toList());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) return const SizedBox.shrink();
    final aVoir = _stories.any((s) => !_vues.contains(s.id));
    return GestureDetector(
      onTap: _ouvrir,
      child: SizedBox(
        width: 92,
        child: Column(children: [
          Container(
            width: 84,
            height: 84,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: aVoir ? AppColors.anneauStory : null,
              color: aVoir ? null : AppColors.border,
            ),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: AppColors.bg),
              child: ClipOval(
                child: Image.asset('assets/images/logo.png', fit: BoxFit.cover),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('Zamu',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: aVoir ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 3),
            const Icon(Icons.verified_rounded,
                size: 14, color: Color(0xFF2E9BFF)),
          ]),
        ]),
      ),
    );
  }
}
