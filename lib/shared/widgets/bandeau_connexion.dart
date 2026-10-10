import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Petit bandeau « Pas de connexion internet » en haut de toute l'appli.
/// Vérifie la connexion toutes les 15 s (et dès qu'on revient dans l'app),
/// puis toutes les 4 s tant qu'elle est coupée.
class BandeauConnexion extends StatefulWidget {
  final Widget child;
  const BandeauConnexion({super.key, required this.child});

  @override
  State<BandeauConnexion> createState() => _BandeauConnexionState();
}

class _BandeauConnexionState extends State<BandeauConnexion>
    with WidgetsBindingObserver {
  bool _horsLigne = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _planifier();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verifier();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  void _planifier() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _horsLigne ? 4 : 15), _verifier);
  }

  Future<void> _verifier() async {
    bool enLigne;
    try {
      final r = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 5));
      enLigne = r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) {
      enLigne = false;
    }
    if (!mounted) return;
    if (enLigne == _horsLigne) setState(() => _horsLigne = !enLigne);
    _planifier();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      widget.child,
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: IgnorePointer(
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            offset: _horsLigne ? Offset.zero : const Offset(0, -1),
            child: Material(
              color: const Color(0xFFE5304A),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Pas de connexion internet'.tr,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                      ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
