// FORGOT.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ⬇️ Navigation to the reset screen (still allowed, but unused now)
import 'package:smart_finder/LANDLORD/FORGOT2.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final _email = TextEditingController();
  final _sb = Supabase.instance.client;

  bool _sending = false;
  bool _canResend = true;
  Timer? _resendTimer;
  int _resendSeconds = 0;

  static const String _redirectUri = 'smartfinder://reset/';

  @override
  void dispose() {
    _email.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  bool _looksLikeEmail(String v) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

  void _startCooldown([int s = 60]) {
    setState(() {
      _canResend = false;
      _resendSeconds = s;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() {
          _canResend = true;
          _resendSeconds = 0;
        });
      } else {
        setState(() => _resendSeconds -= 1);
      }
    });
  }

  // 🔥 UPDATED: Use Supabase built-in OTP reset, not your Edge Function
  Future<void> _sendResetEmailViaEdge() async {
    final email = _email.text.trim();

    if (!_looksLikeEmail(email)) {
      _snack('Please enter a valid email address.');
      return;
    }

    setState(() => _sending = true);

    try {
      await _sb.auth.resetPasswordForEmail(email, redirectTo: _redirectUri);

      _snack("If that email exists, a reset link was sent.");
      _startCooldown(60);
    } catch (e) {
      _snack("Reset failed: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 NO changes made in UI below
    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B5C),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "FORGOT PASSWORD",
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 60),
              SizedBox(
                height: 150,
                child: Image.asset("assets/images/SMARTFINDER3.png"),
              ),
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
                          color: Colors.black87,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    const Text(
                      "Enter your registered email. We'll send you a reset link.",
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email_outlined),
                        hintText: "Email Address",
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Colors.black54,
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(
                            color: Colors.black,
                            width: 2,
                          ),
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
                          onPressed: _sending ? null : _sendResetEmailViaEdge,
                          child: _sending
                              ? const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                )
                              : const Text("Submit"),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 10),

                    const Center(
                      child: Text(
                        "Didn’t get it? Check spam or resend.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Center(
                      child: ElevatedButton.icon(
                        onPressed: (!_canResend || _sending)
                            ? null
                            : _sendResetEmailViaEdge,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey.shade100,
                          foregroundColor: Colors.black,
                        ),
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _canResend
                              ? "Resend Link"
                              : "Resend in $_resendSeconds s",
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
