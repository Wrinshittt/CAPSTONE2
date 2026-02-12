// ----- FORGOT PASSWORD 2 (LANDLORD) -----

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPassword2 extends StatefulWidget {
  const ForgotPassword2({super.key});

  @override
  State<ForgotPassword2> createState() => _ForgotPassword2State();
}

class _ForgotPassword2State extends State<ForgotPassword2> {
  final _newPw = TextEditingController();
  final _confirmPw = TextEditingController();
  final _sb = Supabase.instance.client;

  bool _obscNew = true;
  bool _obscConfirm = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ensureSessionReady();
  }

  Future<void> _ensureSessionReady() async {
    await Future.delayed(const Duration(milliseconds: 200));

    if (_sb.auth.currentSession == null || _sb.auth.currentUser == null) {
      _snack("Reset link expired. Please request again.");
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  bool _strong(String p) =>
      RegExp(r'^(?=.*[A-Za-z])(?=.*\d).{8,}$').hasMatch(p);

  Future<void> _submit() async {
    final p1 = _newPw.text.trim();
    final p2 = _confirmPw.text.trim();

    if (!_strong(p1)) {
      _snack("Password must be 8+ characters with letters & numbers.");
      return;
    }
    if (p1 != p2) {
      _snack("Passwords do not match.");
      return;
    }

    setState(() => _submitting = true);

    try {
      await _sb.auth.updateUser(UserAttributes(password: p1));

      _snack("Password updated successfully. Please log in again.");

      await _sb.auth.signOut();

      if (!mounted) return;

      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      _snack("Error updating password: $e");
    }

    if (mounted) setState(() => _submitting = false);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final userEmail = _sb.auth.currentUser?.email ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B5C),
        title: const Text(
          "FORGOT PASSWORD",
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 35),
            Image.asset("assets/images/SMARTFINDER3.png", height: 140),

            const SizedBox(height: 30),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Text(
                    "Set a new password",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  if (userEmail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        userEmail,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ),

                  const SizedBox(height: 20),

                  _buildPasswordField(
                    controller: _newPw,
                    obscure: _obscNew,
                    onToggle: () => setState(() => _obscNew = !_obscNew),
                    label: "New Password",
                  ),

                  const SizedBox(height: 16),

                  _buildPasswordField(
                    controller: _confirmPw,
                    obscure: _obscConfirm,
                    onToggle: () =>
                        setState(() => _obscConfirm = !_obscConfirm),
                    label: "Confirm Password",
                  ),

                  const SizedBox(height: 25),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.pop(context),
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

  Widget _buildPasswordField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    required String label,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.lock_outline),
        hintText: label,
        filled: true,
        fillColor: Colors.white,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
      ),
    );
  }
}
