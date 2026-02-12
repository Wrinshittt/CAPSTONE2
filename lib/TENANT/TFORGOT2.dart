// ------------------ Tenant Forgot Password Step 2 (tforgot2.dart) ------------------

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantForgotPassword2 extends StatefulWidget {
  const TenantForgotPassword2({super.key});

  @override
  State<TenantForgotPassword2> createState() => _TenantForgotPassword2State();
}

class _TenantForgotPassword2State extends State<TenantForgotPassword2> {
  final TextEditingController _newPw = TextEditingController();
  final TextEditingController _confirmPw = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _submitting = false;

  final _sb = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _ensureValidSession();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _ensureValidSession() async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (_sb.auth.currentSession == null || _sb.auth.currentUser == null) {
      _snack("Reset link expired. Please request a new one.");
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  bool _strong(String p) =>
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,}$').hasMatch(p);

  Future<void> _submit() async {
    final p1 = _newPw.text.trim();
    final p2 = _confirmPw.text.trim();

    if (!_strong(p1)) {
      _snack("Password must be 8+ characters and include numbers & letters.");
      return;
    }
    if (p1 != p2) {
      _snack("Passwords do not match.");
      return;
    }

    setState(() => _submitting = true);

    try {
      await _sb.auth.updateUser(UserAttributes(password: p1));

      await _sb.auth.signOut();

      _snack("Password updated. Please login.");

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      _snack("Error: $e");
    }

    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final email = _sb.auth.currentUser?.email ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B5C),
        centerTitle: true,
        title: const Text(
          "RESET PASSWORD",
          style: TextStyle(fontSize: 22, color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Image.asset("assets/images/SMARTFINDER3.png", height: 130),
            const SizedBox(height: 15),

            if (email.isNotEmpty)
              Text(email, style: const TextStyle(color: Colors.white70)),

            const SizedBox(height: 25),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _newPw,
                    obscureText: _obscureNew,
                    decoration: InputDecoration(
                      hintText: "New Password",
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureNew ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 16),

                  TextField(
                    controller: _confirmPw,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      hintText: "Confirm Password",
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade400,
                          foregroundColor: Colors.black,
                        ),
                        child: const Text("Cancel"),
                      ),

                      const SizedBox(width: 12),

                      ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              )
                            : const Text("Submit"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
