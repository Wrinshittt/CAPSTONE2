// lib/LANDLORD/login.dart
import 'package:flutter/material.dart';
// HIDE Supabase's User type to avoid name conflict with your User widget
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/FORGOT.dart';
import 'package:smart_finder/LANDLORD/REGISTER.dart';
import 'package:smart_finder/LANDLORD/VERIFICATION.dart';
import 'package:smart_finder/USER.dart';

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _rememberMe = false;
  bool _loading = false;
  bool _obscurePass = true;

  // NEW: error flags for highlighting fields
  bool _emailError = false;
  bool _passwordError = false;

  final supabase = Supabase.instance.client;

  // ==============================================================
  // LOGIN HANDLER
  // ==============================================================
  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // NEW: set error flags for empty fields
    setState(() {
      _emailError = email.isEmpty;
      _passwordError = password.isEmpty;
    });

    if (email.isEmpty || password.isEmpty) {
      _msg("Please enter email and password.");
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final authUser = res.user;
      if (authUser == null) throw const AuthException("Wrong credentials.");

      final profile = await supabase
          .from('users')
          .select('id, role, full_name, is_verified, email')
          .eq('id', authUser.id)
          .maybeSingle();

      String? role = (profile?['role'] as String?)?.toLowerCase();
      role ??= (authUser.userMetadata?['role'] as String?)?.toLowerCase();

      if (role != 'landlord') {
        await supabase.auth.signOut();
        _msg("This account is not a landlord.");
        return;
      }

      if (profile?['is_verified'] == false) {
        await supabase.auth.signOut();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => Verification(
              email: (profile?['email'] as String?) ?? (authUser.email ?? ''),
              userId: authUser.id,
            ),
          ),
        );
        return;
      }

      // NEW: clear error flags on successful login
      setState(() {
        _emailError = false;
        _passwordError = false;
      });

      if (!mounted) return;

      // 🔹 PASS FLAG TO DASHBOARD TO SHOW SUCCESS MODAL ONCE
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const Dashboard(
            showLoginSuccess: true,
          ),
        ),
      );
    } on AuthException {
      // NEW: highlight both fields on auth error
      setState(() {
        _emailError = true;
        _passwordError = true;
      });
      _msg("Incorrect email or password.");
    } catch (_) {
      _msg("Login failed. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==============================================================
  // MESSAGE HELPERS (SnackBar -> Modal)
  // ==============================================================
  void _msg(String m) {
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

  // ==============================================================
  // SWITCH ROLE WITH CONFIRMATION
  // ==============================================================
  void _attemptSwitchRole() async {
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
      MaterialPageRoute(builder: (_) => const User()),
    );
  }

  // ==============================================================
  // UI
  // ==============================================================
  @override
  Widget build(BuildContext context) {
    // Small helper to compute border based on error flag
    OutlineInputBorder _borderFor(bool isError) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: isError
            ? const BorderSide(color: Color(0xFFDC2626), width: 1.5) // red
            : BorderSide.none,
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00324E), Color(0xFF005B96)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const SizedBox(height: 40),

                          Image.asset(
                            'assets/images/SMARTFINDER3.png',
                            height: 200,
                          ),

                          const SizedBox(height: 16),

                          // 🔹 Mode pill
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
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
                                    'Landlord login',
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

                          const SizedBox(height: 44),

                          // =====================================================
                          // SWITCH ROLE BUTTON ONLY
                          // =====================================================
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              IconButton(
                                onPressed: _attemptSwitchRole, // ⬅️ updated
                                icon: const Icon(
                                  Icons.sync_alt,
                                  color: Colors.white,
                                  size: 22,
                                ),
                                tooltip: "Switch Role",
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // EMAIL FIELD
                          TextField(
                            controller: _emailController,
                            style: const TextStyle(
                              color: Colors.black,
                              height: 2,
                            ),
                            onChanged: (value) {
                              // Clear red highlight when user types again
                              if (_emailError) {
                                setState(() {
                                  _emailError = false;
                                });
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

                          // PASSWORD FIELD
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePass,
                            style: const TextStyle(
                              color: Colors.black,
                              height: 2,
                            ),
                            onChanged: (value) {
                              // Clear red highlight when user types again
                              if (_passwordError) {
                                setState(() {
                                  _passwordError = false;
                                });
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

                          // REMEMBER ME + FORGOT PASSWORD
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) =>
                                        setState(() => _rememberMe = v ?? false),
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
                                      builder: (_) => const ForgotPassword(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  'Forgot Password',
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // LOGIN BUTTON
                          SizedBox(
                            width: double.infinity,
                            height: 55,
                            child: ElevatedButton(
                              onPressed: _loading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[300],
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator(
                                      color: Colors.black,
                                    )
                                  : const Text(
                                      'LOGIN',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 15),

                          // REGISTER LINK
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "Don’t have an account? ",
                                style: TextStyle(color: Colors.white),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterL(),
                                    ),
                                  );
                                },
                                child: const Text(
                                  "Register",
                                  style: TextStyle(
                                    color: Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
