// ------------------ Tenant Forgot Password (tforgot.dart) ------------------

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantForgotPassword extends StatefulWidget {
  const TenantForgotPassword({super.key});

  @override
  State<TenantForgotPassword> createState() => _TenantForgotPasswordState();
}

class _TenantForgotPasswordState extends State<TenantForgotPassword> {
  final TextEditingController _emailController = TextEditingController();
  final _sb = Supabase.instance.client;

  bool _sending = false;
  bool _canResend = true;
  Timer? _timer;
  int _resendSeconds = 0;

  static const String _redirectUri = "smartfinder://reset";

  @override
  void dispose() {
    _emailController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  bool _looksLikeEmail(String email) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);

  void _startCooldown([int seconds = 60]) {
    setState(() {
      _canResend = false;
      _resendSeconds = seconds;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() {
          _canResend = true;
          _resendSeconds = 0;
        });
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  /// 🔥 REAL Supabase reset—no Edge function needed
  Future<void> _sendResetEmail() async {
    final email = _emailController.text.trim();
    if (!_looksLikeEmail(email)) {
      _snack("Please enter a valid email.");
      return;
    }

    setState(() => _sending = true);

    try {
      await _sb.auth.resetPasswordForEmail(email, redirectTo: _redirectUri);

      _snack("If that email exists, a reset link has been sent.");
      _startCooldown();
    } catch (e) {
      _snack("Reset failed: $e");
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B5C),
        centerTitle: true,
        title: const Text(
          "FORGOT PASSWORD",
          style: TextStyle(color: Colors.white, fontSize: 25),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Image.asset("assets/images/SMARTFINDER3.png", height: 150),
              const SizedBox(height: 30),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        "Find your account",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      "Enter your registered email. A reset link will be sent.",
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        hintText: "Email address",
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ElevatedButton(
                          onPressed: _sending
                              ? null
                              : () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade300,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text("Cancel"),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _sending || !_canResend
                              ? null
                              : _sendResetEmail,
                          child: _sending
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                )
                              : Text(
                                  _canResend
                                      ? "Submit"
                                      : "Wait $_resendSeconds s",
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
