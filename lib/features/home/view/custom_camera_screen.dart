import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:rencontre/core/theme/app_theme.dart';

class CustomCameraScreen extends StatefulWidget {
  const CustomCameraScreen({super.key});
  @override
  State<CustomCameraScreen> createState() => _CustomCameraScreenState();
}

class _CustomCameraScreenState extends State<CustomCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cameras = [];
  int _camIdx = 1; // 1 = front camera
  bool _isReady = false;
  bool _isTakingPhoto = false;
  int _filterIdx = 0;
  bool _flashOn = false;

  // Filtres beauté (ColorFilter matrices)
  final List<Map<String, dynamic>> _filters = [
    {
      'name': 'Normal',
      'icon': '✨',
      'matrix': <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Doux',
      'icon': '🌸',
      'matrix': <double>[
        1.1, 0, 0, 0, 10,
        0, 1.0, 0, 0, 5,
        0, 0, 0.9, 0, 5,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Glam',
      'icon': '💜',
      'matrix': <double>[
        1.2, 0, 0, 0, 15,
        0, 0.9, 0, 0, 0,
        0, 0, 1.1, 0, 20,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Soleil',
      'icon': '☀️',
      'matrix': <double>[
        1.3, 0, 0, 0, 20,
        0, 1.1, 0, 0, 10,
        0, 0, 0.8, 0, 0,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Nuit',
      'icon': '🌙',
      'matrix': <double>[
        0.8, 0, 0, 0, 0,
        0, 0.8, 0, 0, 0,
        0, 0, 1.2, 0, 30,
        0, 0, 0, 1, 0,
      ],
    },
    {
      'name': 'Rose',
      'icon': '🌺',
      'matrix': <double>[
        1.2, 0, 0, 0, 20,
        0, 0.9, 0, 0, 0,
        0, 0, 0.9, 0, 10,
        0, 0, 0, 1, 0,
      ],
    },
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    final idx = _camIdx < _cameras.length ? _camIdx : 0;
    _ctrl = CameraController(
      _cameras[idx],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await _ctrl!.initialize();
    if (mounted) setState(() => _isReady = true);
  }

  Future<void> _switchCamera() async {
    _camIdx = (_camIdx + 1) % _cameras.length;
    await _ctrl?.dispose();
    setState(() => _isReady = false);
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    setState(() => _flashOn = !_flashOn);
    await _ctrl?.setFlashMode(
      _flashOn ? FlashMode.torch : FlashMode.off);
  }

  Future<void> _takePhoto() async {
    if (_ctrl == null || !_ctrl!.value.isInitialized || _isTakingPhoto) return;
    setState(() => _isTakingPhoto = true);
    try {
      final file = await _ctrl!.takePicture();
      Get.back(result: File(file.path));
    } catch (e) {
      Get.snackbar('Erreur', 'Photo impossible',
        backgroundColor: Colors.red.shade900,
        colorText: Colors.white);
    } finally {
      setState(() => _isTakingPhoto = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_ctrl == null || !_ctrl!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _ctrl?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // ── Preview caméra avec filtre ──
        if (_isReady && _ctrl != null)
          ColorFiltered(
            colorFilter: ColorFilter.matrix(
              (_filters[_filterIdx]['matrix'] as List<double>)),
            child: ClipRect(
              child: SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _ctrl!.value.previewSize!.height,
                    height: _ctrl!.value.previewSize!.width,
                    child: CameraPreview(_ctrl!))))))
        else
          Container(color: Colors.black,
            child: const Center(child: CircularProgressIndicator(
              color: AppColors.accent))),

        // ── Gradient top ──
        Positioned(top: 0, left: 0, right: 0,
          child: Container(height: 120,
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent])))),

        // ── Gradient bas ──
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(height: 280,
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black, Colors.transparent])))),

        // ── Header ──
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              GestureDetector(
                onTap: () => Get.back(),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 20))),
              const Spacer(),
              // Flash
              GestureDetector(
                onTap: _toggleFlash,
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _flashOn
                      ? AppColors.accent.withValues(alpha: 0.3)
                      : Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                  child: Icon(
                    _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _flashOn ? AppColors.accent : Colors.white,
                    size: 20))),
              const SizedBox(width: 12),
              // Retourner caméra
              GestureDetector(
                onTap: _switchCamera,
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.flip_camera_android_rounded,
                    color: Colors.white, size: 20))),
            ])),
        ),

        // ── Filtres ──
        Positioned(bottom: 130, left: 0, right: 0,
          child: SizedBox(height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              itemBuilder: (_, i) {
                final isSelected = i == _filterIdx;
                return GestureDetector(
                  onTap: () => setState(() => _filterIdx = i),
                  child: Container(
                    width: 60, height: 60,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: isSelected ? AppColors.gradientPink : null,
                      color: isSelected ? null : Colors.black45,
                      border: Border.all(
                        color: isSelected ? Colors.transparent : Colors.white24,
                        width: isSelected ? 0 : 1)),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_filters[i]['icon'] as String,
                          style: const TextStyle(fontSize: 22)),
                        Text(_filters[i]['name'] as String,
                          style: TextStyle(
                            fontSize: 8,
                            color: isSelected ? Colors.white : Colors.white60,
                            fontWeight: isSelected
                              ? FontWeight.w800 : FontWeight.w400)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // ── Bouton photo ──
        Positioned(bottom: 36, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Galerie
              GestureDetector(
                onTap: () => Get.back(result: 'gallery'),
                child: Container(width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.photo_library_rounded,
                    color: Colors.white, size: 24))),
              const SizedBox(width: 40),
              // Bouton capture
              GestureDetector(
                onTap: _takePhoto,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: _isTakingPhoto ? 70 : 78,
                  height: _isTakingPhoto ? 70 : 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppColors.gradientPink,
                    boxShadow: [BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.5),
                      blurRadius: 20, spreadRadius: 2)]),
                  child: _isTakingPhoto
                    ? const Center(child: SizedBox(width: 28, height: 28,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5)))
                    : const Icon(Icons.camera_alt_rounded,
                        color: Colors.white, size: 32))),
              const SizedBox(width: 40),
              // Retourner
              GestureDetector(
                onTap: _switchCamera,
                child: Container(width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24)),
                  child: const Icon(Icons.flip_camera_android_rounded,
                    color: Colors.white, size: 24))),
            ])),
      ]),
    );
  }
}