// splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Your pages
import 'package:smart_finder/WELCOME.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/TENANT/TLOGIN.dart';
import 'package:smart_finder/USER.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // ✅ Slower, more like your reference
  static const int kWhiteOnlyMs = 900;     // white screen only
  static const int kLogoAppearMs = 1300;   // logo appears while still white
  static const int kBlueStartMs = 1800;    // background starts turning blue
  static const int kNavigateMs = 3200;     // navigate after everything

  bool _showLogo = false;

  late final AnimationController _bgController;
  late final Animation<double> _blueBgFade; // 0 -> white, 1 -> blue bg
  late final Animation<double> _logoScale;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800), // ✅ slower bg fade
    );

    _blueBgFade = CurvedAnimation(
      parent: _bgController,
      curve: Curves.easeInOut,
    );

    _logoScale = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _bgController, curve: Curves.easeOutBack),
    );

    // 1) White only (no logo yet)
    Future.delayed(const Duration(milliseconds: kWhiteOnlyMs), () {
      // still white; do nothing (just holding)
    });

    // 2) Show logo on white
    Future.delayed(const Duration(milliseconds: kLogoAppearMs), () {
      if (!mounted) return;
      setState(() => _showLogo = true);
    });

    // 3) Start background transition to blue (original gradient)
    Future.delayed(const Duration(milliseconds: kBlueStartMs), () {
      if (!mounted) return;
      _bgController.forward();
    });

    // 4) Navigate
    Future.delayed(const Duration(milliseconds: kNavigateMs), _decideNext);
  }

  Future<void> _decideNext() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;
    final selectedRole = prefs.getString('selected_role'); // tenant | landlord | null

    if (!hasSeenWelcome) {
      _go(const Welcome());
      return;
    }

    if (selectedRole == 'tenant') {
      _go(const LoginT());
      return;
    }
    if (selectedRole == 'landlord') {
      _go(const Login());
      return;
    }

    _go(const User());
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _bgController,
        builder: (context, _) {
          return Stack(
            children: [
              // Base: WHITE screen
              Container(color: Colors.white),

              // Blue gradient layer fades in
              Opacity(
                opacity: _blueBgFade.value,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00324E), Color(0xFF005B96)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),

              // Logo appears on white first, then stays for blue
              Center(
                child: AnimatedOpacity(
                  opacity: _showLogo ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 400), // ✅ slower fade
                  curve: Curves.easeOut,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/SMARTFINDER3.png',
                          width: 170,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 22),

                        // Loader appears only once blue is showing
                        Opacity(
                          opacity: _blueBgFade.value,
                          child: const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}