// splash_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Your pages
import 'package:smart_finder/WELCOME.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/TENANT/TLOGIN.dart';
import 'package:smart_finder/USER.dart'; // ← role selection screen

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

    // Give the animation a moment, then decide where to go
    Future.delayed(const Duration(milliseconds: 1200), _decideNext);
  }

  Future<void> _decideNext() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenWelcome = prefs.getBool('has_seen_welcome') ?? false;
    final selectedRole = prefs.getString('selected_role'); // 'tenant' | 'landlord' | null

    // 1) First-ever open → go to Welcome, mark seen
    if (!hasSeenWelcome) {
      if (!mounted) return;
      await prefs.setBool('has_seen_welcome', true);
      _go(const Welcome());
      return;
    }

    // 2) Not first open → if role is known, route to the right Login
    if (selectedRole == 'tenant') {
      _go(const LoginT());
      return;
    }
    if (selectedRole == 'landlord') {
      _go(const Login());
      return;
    }

    // 3) No role chosen yet → ask them to choose
    _go(const User());
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // Your gradient
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00324E), Color(0xFF005B96)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FadeTransition(
          opacity: _fade,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/SMARTFINDER3.png', // your logo
                  width: 160,
                  fit: BoxFit.contain,
                ),

                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
