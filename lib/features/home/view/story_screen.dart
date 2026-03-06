import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/theme/app_theme.dart';
import 'package:rencontre/features/home/controller/home_controller.dart';
import 'package:rencontre/features/home/view/custom_camera_screen.dart';
import 'package:rencontre/shared/models/story_model.dart';

class AddStoryScreen extends StatefulWidget {
  const AddStoryScreen({super.key});
  @override
  State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen> {
  File? _media;
  bool _isVideo = false;
  bool _isUploading = false;
  final _captionCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPicker());
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source, maxWidth: 1080, maxHeight: 1920, imageQuality: 85);
    if (picked != null) setState(() { _media = File(picked.path); _isVideo = false; });
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picked = await _picker.pickVideo(
      source: source, maxDuration: const Duration(seconds: 30));
    if (picked != null) setState(() { _media = File(picked.path); _isVideo = true; });
  }

  void _showPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF13131A),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppColors.border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border,
              borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          ShaderMask(
            shaderCallback: (b) => AppColors.gradientPink.createShader(b),
            child: const Text('Ma Story', style: TextStyle(
              fontFamily: 'Syne', fontSize: 20,
              fontWeight: FontWeight.w900, color: Colors.white))),
          const SizedBox(height: 24),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _PickerBtn(icon: Icons.camera_alt_rounded, label: 'Camera',
              color: AppColors.accent,
              onTap: () async {
                Navigator.pop(context);
                final result = await Get.to(() => const CustomCameraScreen(),
                  transition: Transition.fadeIn);
                if (result is File) {
                  setState(() { _media = result; _isVideo = false; });
                } else if (result == 'gallery') {
                  _pickImage(ImageSource.gallery);
                }
              }),
            _PickerBtn(icon: Icons.photo_library_rounded, label: 'Galerie',
              color: AppColors.accent2,
              onTap: () { Navigator.pop(context); _pickImage(ImageSource.gallery); }),
            _PickerBtn(icon: Icons.videocam_rounded, label: 'Video',
              color: AppColors.accent3,
              onTap: () { Navigator.pop(context); _pickVideo(ImageSource.camera); }),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _upload() async {
    if (_media == null) return;
    setState(() => _isUploading = true);
    try {
      final supabase = Supabase.instance.client;
      final uid = supabase.auth.currentUser!.id;
      final ext = _isVideo ? 'mp4' : 'jpg';
      final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await _media!.readAsBytes();

      await supabase.storage.from('stories').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(
          contentType: _isVideo ? 'video/mp4' : 'image/jpeg',
          upsert: true));

      final url = supabase.storage.from('stories').getPublicUrl(path);

      await supabase.from('stories').insert({
        'user_id': uid,
        'media_url': url,
        'is_video': _isVideo,
        'caption': _captionCtrl.text.trim().isEmpty
          ? null : _captionCtrl.text.trim(),
        'expires_at': DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'viewed_by': [],
      });

      Get.back(result: true);
      Get.snackbar('Story publiee !', '',
        snackPosition: SnackPosition.TOP,
        backgroundColor: const Color(0xFF1A1A2E),
        colorText: Colors.white,
        duration: const Duration(seconds: 2));
    } catch (e) {
      debugPrint('STORY ERROR: $e');
      Get.snackbar('Erreur upload', e.toString().length > 100
        ? e.toString().substring(0, 100) : e.toString(),
        snackPosition: SnackPosition.TOP,
        backgroundColor: Colors.red.shade900,
        colorText: Colors.white,
        duration: const Duration(seconds: 6));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: GestureDetector(
          onTap: () => Get.back(),
          child: Container(margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black54,
              shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
            child: const Icon(Icons.close_rounded, color: Colors.white, size: 20))),
        title: ShaderMask(
          shaderCallback: (b) => AppColors.gradientPink.createShader(b),
          child: const Text('Ma Story', style: TextStyle(
            fontFamily: 'Syne', fontSize: 18,
            fontWeight: FontWeight.w900, color: Colors.white))),
        centerTitle: true,
        actions: [
          if (_media != null)
            GestureDetector(
              onTap: _showPicker,
              child: Container(margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black54,
                  shape: BoxShape.circle, border: Border.all(color: Colors.white24)),
                child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20))),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        // Fond
        _media == null
          ? _buildEmpty()
          : _isVideo
            ? _buildVideoPreview()
            : Image.file(_media!, fit: BoxFit.cover,
                width: double.infinity, height: double.infinity),

        // Gradient bas
        if (_media != null)
          Positioned(bottom: 0, left: 0, right: 0,
            child: Container(height: 260,
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black])))),

        // Controles
        Positioned(bottom: 0, left: 0, right: 0,
          child: SafeArea(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_media != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24)),
                  child: TextField(
                    controller: _captionCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLength: 100,
                    decoration: const InputDecoration(
                      hintText: 'Legende...',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                      counterStyle: TextStyle(color: Colors.white30, fontSize: 10)))),

              GestureDetector(
                onTap: _isUploading ? null
                  : _media == null ? _showPicker : _upload,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 17),
                  decoration: BoxDecoration(
                    gradient: AppColors.gradientPink,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.35),
                      blurRadius: 20, offset: const Offset(0, 6))]),
                  child: _isUploading
                    ? const Center(child: SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_media == null
                          ? Icons.add_photo_alternate_rounded
                          : Icons.send_rounded,
                          color: Colors.white, size: 20),
                        const SizedBox(width: 10),
                        Text(_media == null
                          ? 'Choisir une photo / video'
                          : 'Publier ma story',
                          style: const TextStyle(fontSize: 16,
                            fontWeight: FontWeight.w800, color: Colors.white)),
                      ])),
              ),
            ]),
          ))),
      ]),
    );
  }

  Widget _buildEmpty() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF0D0D1A), Color(0xFF1A0A2E), Color(0xFF0A1628)],
        begin: Alignment.topCenter, end: Alignment.bottomCenter)),
    child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 100, height: 100,
          decoration: BoxDecoration(
            gradient: AppColors.gradientPink,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.4), blurRadius: 30)]),
          child: const Icon(Icons.add_photo_alternate_rounded,
            color: Colors.white, size: 48)),
        const SizedBox(height: 24),
        const Text('Ta Story', style: TextStyle(
          fontFamily: 'Syne', fontSize: 24,
          fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 8),
        const Text('Partage un moment de ta journee',
          style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
      ])));

  Widget _buildVideoPreview() => Container(
    color: Colors.black,
    child: Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 80, height: 80,
          decoration: BoxDecoration(color: Colors.white12,
            shape: BoxShape.circle),
          child: const Icon(Icons.play_circle_outline_rounded,
            color: Colors.white, size: 48)),
        const SizedBox(height: 12),
        const Text('Video selectionnee',
          style: TextStyle(color: Colors.white70, fontSize: 14)),
      ])));
}

// ─── STORY VIEWER ─────────────────────────────────────────────────

class StoryViewerScreen extends StatefulWidget {
  final List<StoryModel> stories;
  final int initialIndex;
  const StoryViewerScreen({
    super.key, required this.stories, this.initialIndex = 0});
  @override
  State<StoryViewerScreen> createState() => _StoryViewerState();
}

class _StoryViewerState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late int _i;
  late AnimationController _prog;
  final _replyCtrl = TextEditingController();
  bool _showReply = false;

  @override
  void initState() {
    super.initState();
    _i = widget.initialIndex;
    _prog = AnimationController(
      vsync: this, duration: const Duration(seconds: 5))
      ..addStatusListener((s) { if (s == AnimationStatus.completed) _next(); })
      ..forward();
    _markSeen();
  }

  void _next() {
    if (_i < widget.stories.length - 1) {
      setState(() => _i++);
      _prog.reset(); _prog.forward(); _markSeen();
    } else { Get.back(); }
  }

  void _prev() {
    if (_i > 0) { setState(() => _i--); _prog.reset(); _prog.forward(); }
  }

  void _markSeen() async {
    try {
      final story = widget.stories[_i];
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null || story.viewedBy.contains(uid)) return;
      await Supabase.instance.client.from('stories')
        .update({'viewed_by': [...story.viewedBy, uid]})
        .eq('id', story.id);
    } catch (_) {}
  }

  @override
  void dispose() { _prog.dispose(); _replyCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.stories[_i];
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          if (d.localPosition.dx < MediaQuery.of(context).size.width / 2.5)
            _prev(); else _next();
        },
        child: Stack(fit: StackFit.expand, children: [
          CachedNetworkImage(imageUrl: s.mediaUrl, fit: BoxFit.cover,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: AppColors.accent)),
            errorWidget: (_, __, ___) => Container(
              color: const Color(0xFF1A1A2E),
              child: const Center(child: Icon(Icons.broken_image_rounded,
                color: Colors.white38, size: 60)))),

          Positioned(top: 0, left: 0, right: 0,
            child: Container(height: 160,
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent])))),

          SafeArea(
            child: Column(children: [
              // Progress bars
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: List.generate(widget.stories.length, (i) =>
                    Expanded(
                      child: Container(
                        height: 2.5,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2)),
                        child: i < _i
                          ? Container(decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2)))
                          : i == _i
                            ? AnimatedBuilder(
                                animation: _prog,
                                builder: (_, __) => FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _prog.value,
                                  child: Container(decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2)))))
                            : const SizedBox(),
                      ),
                    )),
                ),
              ),
              // User info
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Row(children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2)),
                    child: ClipOval(
                      child: s.userPhotoUrl != null
                        ? CachedNetworkImage(imageUrl: s.userPhotoUrl!, fit: BoxFit.cover)
                        : Container(color: AppColors.accent,
                            child: Center(child: Text(s.userName[0].toUpperCase(),
                              style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w800)))))),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.userName, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white)),
                    Text(_ago(s.createdAt), style: const TextStyle(
                      fontSize: 11, color: Colors.white60)),
                  ]),
                  const Spacer(),
                  // Menu 3 points
                  GestureDetector(
                    onTap: () {
                      final uid = Supabase.instance.client.auth.currentUser?.id;
                      final isOwner = uid == s.userId;
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => Container(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                          decoration: BoxDecoration(
                            color: const Color(0xFF13131A),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24)),
                            border: Border.all(color: const Color(0xFF2A2A3A))),
                          child: Column(mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 40, height: 4,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A2A3A),
                                  borderRadius: BorderRadius.circular(2))),
                              const SizedBox(height: 20),
                              if (isOwner) ...[
                                _MenuOption(
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Supprimer cette story',
                                  color: Colors.red,
                                  onTap: () {
                                    Navigator.pop(context);
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        backgroundColor: const Color(0xFF1A1A2E),
                                        title: const Text('Supprimer ?',
                                          style: TextStyle(color: Colors.white)),
                                        content: const Text(
                                          'Cette story sera supprimée définitivement.',
                                          style: TextStyle(color: Colors.white70)),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Annuler',
                                              style: TextStyle(color: Colors.white54))),
                                          TextButton(
                                            onPressed: () async {
                                              Navigator.pop(context);
                                              final ctrl = Get.find<HomeController>();
                                              await ctrl.deleteStory(s.id);
                                              Get.back();
                                            },
                                            child: const Text('Supprimer',
                                              style: TextStyle(color: Colors.red))),
                                        ],
                                      ));
                                  }),
                                const SizedBox(height: 4),
                              ],
                              _MenuOption(
                                icon: Icons.flag_outlined,
                                label: 'Signaler',
                                color: Colors.orange,
                                onTap: () {
                                  Navigator.pop(context);
                                  Get.snackbar('Signalement envoyé', '',
                                    snackPosition: SnackPosition.TOP,
                                    backgroundColor: const Color(0xFF1A1A2E),
                                    colorText: Colors.white);
                                }),
                              const SizedBox(height: 4),
                              _MenuOption(
                                icon: Icons.close_rounded,
                                label: 'Fermer',
                                color: Colors.white54,
                                onTap: () => Navigator.pop(context)),
                            ]),
                        ));
                    },
                    child: Container(width: 34, height: 34,
                      decoration: const BoxDecoration(
                        color: Colors.black38, shape: BoxShape.circle),
                      child: const Icon(Icons.more_vert_rounded,
                        color: Colors.white, size: 18))),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(width: 34, height: 34,
                      decoration: const BoxDecoration(
                        color: Colors.black38, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 17))),
                ]),
              ),
            ]),
          ),

          Positioned(bottom: 0, left: 0, right: 0,
            child: SafeArea(child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16,
                MediaQuery.of(context).viewInsets.bottom + 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Légende
                  if (s.caption != null && s.caption!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12)),
                      child: Text(s.caption!,
                        style: const TextStyle(
                          color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w500))),

                  Row(children: [
                    // Vues
                    const Icon(Icons.remove_red_eye_rounded,
                      color: Colors.white60, size: 15),
                    const SizedBox(width: 5),
                    Text('\${s.viewedBy.length} vues',
                      style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
                    const Spacer(),
                  ]),
                  const SizedBox(height: 10),

                  // Barre de réponse (cachée pour sa propre story)
                  Builder(builder: (ctx) {
                    final uid = Supabase.instance.client.auth.currentUser?.id;
                    if (uid == s.userId) return const SizedBox.shrink();
                    return Row(children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _showReply = true);
                            _prog.stop();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white30)),
                            child: _showReply
                              ? TextField(
                                  controller: _replyCtrl,
                                  autofocus: true,
                                  style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                  decoration: const InputDecoration(
                                    hintText: 'Répondre...',
                                    hintStyle: TextStyle(color: Colors.white38),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero),
                                )
                              : const Text('Répondre à cette story...',
                                  style: TextStyle(
                                    color: Colors.white54, fontSize: 14)),
                          ),
                        ),
                      ),
                      if (_showReply) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            final msg = _replyCtrl.text.trim();
                            if (msg.isEmpty) return;
                            _replyCtrl.clear();
                            setState(() => _showReply = false);
                            _prog.forward();
                            // Envoie via le chat controller
                            try {
                              final myId = Supabase.instance.client
                                .auth.currentUser!.id;
                              // Cherche ou crée la conversation
                              final convRes = await Supabase.instance.client
                                .from('conversations')
                                .select('id')
                                .or('user1_id.eq.\$myId,user2_id.eq.\$myId')
                                .or('user1_id.eq.\${s.userId},user2_id.eq.\${s.userId}')
                                .maybeSingle();
                              String convId;
                              if (convRes != null) {
                                convId = convRes['id'];
                              } else {
                                final newConv = await Supabase.instance.client
                                  .from('conversations')
                                  .insert({
                                    'user1_id': myId,
                                    'user2_id': s.userId,
                                  }).select('id').single();
                                convId = newConv['id'];
                              }
                              await Supabase.instance.client
                                .from('messages')
                                .insert({
                                  'conversation_id': convId,
                                  'sender_id': myId,
                                  'text': '📸 Story : \$msg',
                                  'created_at': DateTime.now().toIso8601String(),
                                });
                              Get.snackbar('Réponse envoyée ✅', '',
                                snackPosition: SnackPosition.TOP,
                                backgroundColor: const Color(0xFF1A1A2E),
                                colorText: Colors.white,
                                duration: const Duration(seconds: 2));
                            } catch (e) {
                              debugPrint('reply error: \$e');
                            }
                          },
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              gradient: AppColors.gradientPink,
                              shape: BoxShape.circle),
                            child: const Icon(Icons.send_rounded,
                              color: Colors.white, size: 18))),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() => _showReply = false);
                            _replyCtrl.clear();
                            _prog.forward();
                          },
                          child: Container(
                            width: 36, height: 36,
                            decoration: const BoxDecoration(
                              color: Colors.black38, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded,
                              color: Colors.white54, size: 16))),
                      ] else ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() => _showReply = true);
                            _prog.stop();
                          },
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white24)),
                            child: const Icon(Icons.reply_rounded,
                              color: Colors.white, size: 20))),
                      ],
                    ]);
                  }),
                ],
              ),
            ))),
        ]),
      ),
    );
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inHours > 0) return 'il y a ${d.inHours}h';
    if (d.inMinutes > 0) return 'il y a ${d.inMinutes}min';
    return "a l'instant";
  }
}

// ─── HELPER ───────────────────────────────────────────────────────

class _PickerBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _PickerBtn({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(children: [
      Container(width: 64, height: 64,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12), shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5)),
        child: Icon(icon, color: color, size: 28)),
      const SizedBox(height: 8),
      Text(label, style: TextStyle(fontSize: 12,
        color: color, fontWeight: FontWeight.w700)),
    ]));
}

// ─── MENU OPTION ──────────────────────────────────────────────────

class _MenuOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _MenuOption({required this.icon, required this.label,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(
          color: color, fontSize: 15, fontWeight: FontWeight.w600)),
      ])));
}