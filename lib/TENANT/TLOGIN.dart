// lib/TENANT/tlogin.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'TAPARTMENT.dart';
import 'TFORGOT.dart';
import 'TREGISTER.dart';
import 'package:smart_finder/USER.dart' as role_screen; // 👈 alias to avoid `User` name clash

class LoginT extends StatefulWidget {
  const LoginT({super.key});

  @override
  State<LoginT> createState() => _LoginTState();
}

class _LoginTState extends State<LoginT> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _remember = false;
  bool _loading = false;
  bool _obscurePass = true; // 👁️ password visibility toggle

  // error flags for red highlights
  bool _emailError = false;
  bool _passwordError = false;

  final _sb = Supabase.instance.client;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // SnackBar -> Modal dialog
  void _toast(String m) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notice'),
        content: Text(m),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    final pass = _password.text;

    // set error flags based on emptiness
    setState(() {
      _emailError = email.isEmpty;
      _passwordError = pass.isEmpty;
    });

    if (email.isEmpty || pass.isEmpty) {
      _toast('Please enter email and password.');
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await _sb.auth.signInWithPassword(
        email: email,
        password: pass,
      );
      final authUser = res.user;
      if (authUser == null) throw const AuthException('Invalid credentials.');

      final u = await _sb
          .from('users')
          .select('id, role, is_verified')
          .eq('id', authUser.id)
          .maybeSingle();

      if (u == null) {
        await _sb.auth.signOut();
        _toast('Account not found.');
        return;
      }

      if ((u['role'] as String?)?.toLowerCase() != 'tenant') {
        final hasTenant = await _sb
            .from('user_roles')
            .select('role')
            .eq('user_id', authUser.id)
            .eq('role', 'tenant')
            .maybeSingle();

        if (hasTenant == null) {
          await _sb.auth.signOut();
          _toast('This account is not a tenant.');
          return;
        }
      }

      if (u['is_verified'] != true) {
        await _sb.auth.signOut();
        _toast('Please verify your email first.');
        return;
      }

      // clear error flags on successful login
      setState(() {
        _emailError = false;
        _passwordError = false;
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantApartment()),
      );
    } on AuthException catch (e) {
      _toast('Login failed: ${e.message}');
    } on PostgrestException catch (e) {
      _toast('Database error: ${e.message ?? 'Unknown'}');
    } catch (e) {
      _toast('Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // SWITCH ROLE WITH CONFIRMATION (same pattern as landlord login)
  Future<void> _attemptSwitchRole() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Switch Role?"),
        content: const Text("Are you sure you want to switch?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _switchRole();
    }
  }

  void _switchRole() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const role_screen.User(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // helper for conditional red border
    OutlineInputBorder _borderFor(bool isError) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: isError
            ? const BorderSide(color: Color(0xFFDC2626), width: 1.5)
            : BorderSide.none,
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        height: MediaQuery.of(context).size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00324E), Color(0xFF005B96)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                Image.asset('assets/images/SMARTFINDER3.png', height: 200),
                const SizedBox(height: 16),

                // Tenant login pill
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.18),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.login_rounded,
                          size: 14,
                          color: Colors.white.withOpacity(0.9),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Tenant login',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11.5,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Switch Role Icon row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.sync_alt, color: Colors.white),
                      tooltip: 'Switch Role',
                      onPressed: _attemptSwitchRole,
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // EMAIL INPUT
                TextField(
                  controller: _email,
                  style: const TextStyle(color: Colors.black, height: 2),
                  onChanged: (value) {
                    if (_emailError) {
                      setState(() => _emailError = false);
                    }
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[300],
                    prefixIcon: const Icon(Icons.email_outlined),
                    hintText: 'Email Address',
                    border: _borderFor(_emailError),
                    enabledBorder: _borderFor(_emailError),
                    focusedBorder: _borderFor(_emailError),
                  ),
                ),
                const SizedBox(height: 12),

                // PASSWORD INPUT + EYE ICON
                TextField(
                  controller: _password,
                  obscureText: _obscurePass,
                  style: const TextStyle(color: Colors.black, height: 2),
                  onChanged: (value) {
                    if (_passwordError) {
                      setState(() => _passwordError = false);
                    }
                  },
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.grey[300],
                    prefixIcon: const Icon(Icons.lock_outline),
                    hintText: 'Password',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.black,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePass = !_obscurePass;
                        });
                      },
                    ),
                    border: _borderFor(_passwordError),
                    enabledBorder: _borderFor(_passwordError),
                    focusedBorder: _borderFor(_passwordError),
                  ),
                ),

                const SizedBox(height: 10),

                // REMEMBER + FORGOT
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _remember,
                          onChanged: (v) =>
                              setState(() => _remember = v ?? false),
                        ),
                        const Text(
                          'Remember me',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TenantForgotPassword(),
                          ),
                        );
                      },
                      child: const Text(
                        'Forgot Password',
                        style: TextStyle(color: Colors.lightBlueAccent),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // LOGIN BUTTON
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text(
                            'LOGIN',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 14),

                // REGISTER LINK
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      "Don’t have account? ",
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const RegisterT()),
                        );
                      },
                      child: const Text(
                        "Register",
                        style: TextStyle(color: Colors.lightBlueAccent),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
