// lib/TENANT/tregister.dart
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'TLOGIN.dart';
import 'TVERIFICATION.dart';

class RegisterT extends StatefulWidget {
  const RegisterT({super.key});

  @override
  State<RegisterT> createState() => _RegisterTState();
}

class _RegisterTState extends State<RegisterT> {
  // ---------------------------------------------------------------------------
  // CONTROLLERS & STATE
  // ---------------------------------------------------------------------------

  final TextEditingController _fullName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;

  // NEW: tracking for validation & red highlights
  bool _submitted = false;
  bool _fullNameError = false;
  bool _emailError = false;
  bool _passwordError = false;
  bool _confirmError = false;

  final SupabaseClient _sb = Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  // use dialog instead of SnackBar, but keep same name/signature.
  void _toast(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Notice'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Validate input fields; returns `null` if valid, otherwise error message.
  String? _validateInputs() {
    final fullName = _fullName.text.trim();
    final email = _email.text.trim().toLowerCase();
    final pass = _password.text;
    final pass2 = _confirm.text;

    if (fullName.isEmpty || email.isEmpty || pass.isEmpty) {
      return 'Full name, email and password are required.';
    }

    if (!email.contains('@')) {
      return 'Please enter a valid email.';
    }

    if (pass.length < 6) {
      return 'Password must be at least 6 characters.';
    }

    if (pass != pass2) {
      return 'Passwords do not match.';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // REGISTER LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _register() async {
    final String? errorMsg = _validateInputs();

    // NEW: mark as submitted and set error flags for highlighting
    setState(() {
      _submitted = true;

      final fullName = _fullName.text.trim();
      final email = _email.text.trim().toLowerCase();
      final pass = _password.text;
      final pass2 = _confirm.text;

      _fullNameError = fullName.isEmpty;
      _emailError = email.isEmpty || !email.contains('@');
      _passwordError = pass.isEmpty || pass.length < 6;
      _confirmError = pass2.isEmpty || pass2 != pass;
    });

    if (errorMsg != null) {
      _toast(errorMsg);
      return;
    }

    final String fullName = _fullName.text.trim();
    final String email = _email.text.trim().toLowerCase();
    final String phone = _phone.text.trim();
    final String pass = _password.text;

    setState(() => _loading = true);

    try {
      // 1) Check if user already exists in public.users
      final existingUser = await _sb
          .from('users')
          .select('id, is_verified')
          .eq('email', email)
          .maybeSingle();

      String userId;

      if (existingUser == null) {
        // -------------------------------------------------------------------
        // NEW TENANT: CREATE AUTH USER
        // -------------------------------------------------------------------
        final signUp = await _sb.auth.signUp(
          email: email,
          password: pass,
          data: {
            'full_name': fullName,
            'role': 'tenant',
          },
        );

        final authUser = signUp.user;
        if (authUser == null) {
          throw const AuthException(
            'Sign-up created but no user returned. Check auth settings.',
          );
        }

        userId = authUser.id;

        // Mirror into public.users
        final String hashed = sha256.convert(utf8.encode(pass)).toString();
        await _sb.from('users').insert({
          'id': userId,
          'full_name': fullName,
          'email': email,
          'phone': phone.isEmpty ? null : phone,
          'password': hashed,
          'role': 'tenant',
          'is_verified': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        // -------------------------------------------------------------------
        // EXISTING EMAIL: SIGN IN WITH SAME PASSWORD
        // -------------------------------------------------------------------
        final signIn = await _sb.auth.signInWithPassword(
          email: email,
          password: pass,
        );

        final authUser = signIn.user;
        if (authUser == null) {
          _toast(
            'Email already exists. Enter the same password used for this email.',
          );
          return;
        }

        userId = authUser.id;
      }

      // ---------------------------------------------------------------------
      // ENSURE user_roles ROW (TENANT) – IGNORE DUPLICATE
      // ---------------------------------------------------------------------
      try {
        await _sb.from('user_roles').insert({
          'user_id': userId,
          'role': 'tenant',
        });
      } catch (_) {
        // non-fatal (duplicate role, etc.)
      }

      // ---------------------------------------------------------------------
      // ENSURE tenant_profile EXISTS FOR THIS USER
      // ---------------------------------------------------------------------
      await _sb.from('tenant_profile').upsert({
        'user_id': userId,
        'full_name': fullName,
        'phone': phone.isEmpty ? null : phone,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // ---------------------------------------------------------------------
      // SEND OTP VIA EDGE FUNCTION
      // ---------------------------------------------------------------------
      final fnRes = await _sb.functions.invoke(
        'send_otp',
        body: {
          'email': email,
          'user_id': userId,
          'full_name': fullName,
        },
      );

      if (fnRes.data is Map && (fnRes.data as Map)['ok'] == true) {
        _toast('Verification code sent to $email');
      } else {
        _toast(
          'Failed to send code. You can try resending from the next screen.',
        );
      }

      if (!mounted) return;

      // Navigate to verification screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TenantVerification(
            email: email,
            userId: userId,
            fullName: fullName,
          ),
        ),
      );
    } on FunctionException catch (e) {
      _toast('Function error: $e');
    } on PostgrestException catch (e) {
      _toast('Database error: ${e.message}');
    } on AuthException catch (e) {
      _toast('Auth error: ${e.message}');
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PASSWORD UI HELPERS (UI ONLY, NO LOGIC CHANGES)
  // ---------------------------------------------------------------------------

  String _passwordStrengthLabel(String password) {
    if (password.isEmpty) return '';
    final length = password.length;
    final hasUpper = password.contains(RegExp(r'[A-Z]'));
    final hasLower = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'[0-9]'));
    final hasSymbol =
        password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-=+]'));

    int score = 0;
    if (length >= 8) score++;
    if (length >= 12) score++;
    if (hasUpper && hasLower) score++;
    if (hasDigit) score++;
    if (hasSymbol) score++;

    if (score <= 2) return 'Weak password';
    if (score == 3 || score == 4) return 'Medium strength password';
    return 'Strong password';
  }

  Color _passwordStrengthColor(String password) {
    if (password.isEmpty) return Colors.transparent;
    final label = _passwordStrengthLabel(password);
    if (label.startsWith('Weak')) {
      return const Color(0xFFDC2626); // red
    } else if (label.startsWith('Medium')) {
      return const Color(0xFFF97316); // orange
    } else {
      return const Color(0xFF16A34A); // green
    }
  }

  bool get _passwordsMismatch {
    final p = _password.text;
    final c = _confirm.text;
    if (p.isEmpty || c.isEmpty) return false;
    return p != c;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final passwordText = _password.text;

    return Scaffold(
      // 🔹 Match TLOGIN primary background color
      backgroundColor: const Color(0xFF00324E),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          // 🔹 Gradient copied from TLOGIN.dart
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Top app shell row (similar to landlord)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white70,
                                size: 18,
                              ),
                              tooltip: 'Back',
                            ),
                            Row(
                              children: [
                                Image.asset(
                                  'assets/images/SMARTFINDER3.png',
                                  height: 42,
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Smart Finder',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Tenant onboarding',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(width: 40),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Mode pill
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
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
                                  Icons.person_add_alt_1_rounded,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'New tenant registration',
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

                        const SizedBox(height: 16),

                        // Title
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Create your tenant account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // Form sections (no card, same style as landlord)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // SECTION 1: PERSONAL INFO
                              const _SectionHeader(
                                icon: Icons.person_outline,
                                title: 'Personal information',
                                subtitle:
                                    'We’ll use these details to personalize your experience.',
                              ),
                              const SizedBox(height: 12),

                              _buildTextField(
                                controller: _fullName,
                                hint: 'Full Name',
                                icon: Icons.person_outline,
                              ),

                              const SizedBox(height: 18),
                              Divider(
                                color: Colors.white.withOpacity(0.14),
                                height: 28,
                              ),

                              // SECTION 2: CONTACT & ACCOUNT
                              const _SectionHeader(
                                icon: Icons.mail_outline,
                                title: 'Contact & account',
                                subtitle:
                                    'Your login details and how we can reach you.',
                              ),
                              const SizedBox(height: 12),

                              _buildTextField(
                                controller: _email,
                                hint: 'Email Address',
                                icon: Icons.email_outlined,
                                inputType: TextInputType.emailAddress,
                              ),
                              const SizedBox(height: 10),

                              _buildTextField(
                                controller: _phone,
                                hint: 'Phone Number (optional)',
                                icon: Icons.phone_outlined,
                                inputType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Password
                              _buildTextField(
                                controller: _password,
                                hint: 'Password',
                                icon: Icons.lock_outline,
                                obscure: _obscure1,
                                trailing: IconButton(
                                  icon: Icon(
                                    _obscure1
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6B7280),
                                  ),
                                  onPressed: () {
                                    setState(() => _obscure1 = !_obscure1);
                                  },
                                ),
                                onChanged: (_) {
                                  // keep existing UI behavior
                                  setState(() {});
                                },
                              ),
                              const SizedBox(height: 4),

                              // Password strength
                              if (passwordText.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: _passwordStrengthColor(
                                            passwordText),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        _passwordStrengthLabel(passwordText),
                                        style: TextStyle(
                                          color: _passwordStrengthColor(
                                              passwordText),
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 10),

                              // Confirm password
                              _buildTextField(
                                controller: _confirm,
                                hint: 'Confirm Password',
                                icon: Icons.lock_outline,
                                obscure: _obscure2,
                                trailing: IconButton(
                                  icon: Icon(
                                    _obscure2
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6B7280),
                                  ),
                                  onPressed: () {
                                    setState(() => _obscure2 = !_obscure2);
                                  },
                                ),
                                onChanged: (_) {
                                  // keep existing UI behavior
                                  setState(() {});
                                },
                              ),

                              if (_passwordsMismatch) ...[
                                const SizedBox(height: 4),
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Passwords do not match.',
                                    style: TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 22),

                              // SUBMIT BUTTON
                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _register,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF111827),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _loading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const Text(
                                          'REGISTER',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // LOGIN LINK (bottom)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Already have an account? ',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                              ),
                            ),
                            GestureDetector(
                              onTap: _loading
                                  ? null
                                  : () {
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => const LoginT(),
                                        ),
                                      );
                                    },
                              child: const Text(
                                'Login',
                                style: TextStyle(
                                  color: Color(0xFF7DD3FC),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
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

  // ---------------------------------------------------------------------------
  // REUSABLE TEXT FIELD (NOW HANDLES RED HIGHLIGHT PER FIELD)
  // ---------------------------------------------------------------------------

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    Widget? trailing,
    ValueChanged<String>? onChanged,
  }) {
    // Decide which field is in error based on its controller.
    bool isError = false;
    if (controller == _fullName) {
      isError = _fullNameError;
    } else if (controller == _email) {
      isError = _emailError;
    } else if (controller == _password) {
      isError = _passwordError;
    } else if (controller == _confirm) {
      isError = _confirmError;
    }

    final Color borderColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB);
    final Color focusedBorderColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFF2563EB);

    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: inputType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.black),
        onChanged: (value) {
          // Clear the specific field's error when user types again after submit
          if (_submitted) {
            setState(() {
              if (controller == _fullName) {
                _fullNameError = false;
              } else if (controller == _email) {
                _emailError = false;
              } else if (controller == _password) {
                _passwordError = false;
              } else if (controller == _confirm) {
                _confirmError = false;
              }
            });
          }
          // Preserve any original onChanged behavior passed in
          if (onChanged != null) {
            onChanged(value);
          }
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          prefixIcon: Icon(icon, color: const Color(0xFF6B7280)),
          suffixIcon: trailing,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                BorderSide(color: focusedBorderColor, width: 1.3),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SECTION HEADER (same style as landlord version, adjusted text color)
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.78),
                  fontSize: 11.5,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
