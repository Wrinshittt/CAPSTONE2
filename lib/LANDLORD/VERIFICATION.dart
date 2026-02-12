// verification.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/LANDLORD/LOGIN.dart';

class Verification extends StatefulWidget {
  final String email;
  final String userId;

  const Verification({super.key, required this.email, required this.userId});

  @override
  State<Verification> createState() => _VerificationState();
}

class _VerificationState extends State<Verification> {
  final supabase = Supabase.instance.client;

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());

  // 👉 For better OTP UX (auto-next, auto-backspace)
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _code() => _controllers.map((c) => c.text.trim()).join();

  Future<void> _resendCode() async {
    try {
      setState(() => _loading = true);

      final res = await supabase.functions.invoke(
        'send_otp',
        body: {
          'email': widget.email,
          'user_id': widget.userId,
          'full_name': '', // optional
        },
      );

      if (res.status >= 400) throw Exception('${res.data}');

      _msg('Verification code re-sent.');
    } catch (e) {
      _msg('Failed to resend: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmCode() async {
    final code = _code();

    if (code.length != 6) {
      _msg('Please enter the 6-digit code.');
      return;
    }

    try {
      setState(() => _loading = true);

      final res = await supabase.functions.invoke(
        'verify_otp',
        body: {'email': widget.email, 'code': code},
      );

      if (res.status >= 400) throw Exception('${res.data}');

      await supabase
          .from('users')
          .update({
            'is_verified': true,
            'verification_code': null,
            'verification_expires_at': null,
          })
          .eq('id', widget.userId);

      if (!mounted) return;

      _msg('Email verified! Please log in.');

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
        (_) => false,
      );
    } catch (e) {
      _msg('Verification failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF00324E);
    const Color cardBg = Colors.white;

    final media = MediaQuery.of(context);
    final double bottomInset = media.viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          // ---- Full background (gradient + subtle image) ----
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF02293C),
                    Color(0xFF00527A),
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.18,
              child: Image.asset(
                "assets/images/apartment.png",
                fit: BoxFit.cover,
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                24,
                20,
                bottomInset + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // ---------- Top branding ----------
                  Column(
                    children: [
                      SizedBox(
                        height: 84,
                        child: Image.asset(
                          "assets/images/SMARTFINDER3.png",
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Email Verification",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "For your security, we’ve sent a 6-digit code to:",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          widget.email,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ---------- Main card ----------
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE6F0F6),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.mark_email_unread_outlined,
                                size: 30,
                                color: primaryColor,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "Enter verification code",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Type the 6-digit code we sent to your email to verify your account.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // ---------- OTP fields (responsive, no overflow) ----------
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const int boxes = 6;
                                const double spacing = 8.0;

                                final double totalSpacing =
                                    spacing * (boxes - 1);
                                final double maxWidthForFields =
                                    constraints.maxWidth - totalSpacing;

                                // Clamp each field’s width to stay within reasonable bounds
                                final double fieldWidth = (maxWidthForFields /
                                        boxes)
                                    .clamp(40.0, 56.0);

                                return Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: List.generate(boxes, (index) {
                                    return SizedBox(
                                      width: fieldWidth,
                                      height: 56,
                                      child: TextField(
                                        controller: _controllers[index],
                                        focusNode: _focusNodes[index],
                                        autofocus: index == 0,
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 1.5,
                                        ),
                                        maxLength: 1,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          counterText: "",
                                          filled: true,
                                          fillColor: const Color(0xFFF3F4F6),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                              color: primaryColor,
                                              width: 1.4,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                              color: Color(0xFFD1D5DB),
                                              width: 1.0,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          // Keep only one character (handles paste)
                                          if (value.length > 1) {
                                            final last = value.characters.last;
                                            _controllers[index].text = last;
                                            _controllers[index].selection =
                                                const TextSelection.collapsed(
                                                    offset: 1);
                                          }

                                          if (value.isNotEmpty) {
                                            // Move forward when typing a digit
                                            if (index < boxes - 1) {
                                              FocusScope.of(context).requestFocus(
                                                  _focusNodes[index + 1]);
                                            } else {
                                              FocusScope.of(context).unfocus();
                                            }
                                          } else {
                                            // Move back when deleting and field becomes empty
                                            if (index > 0) {
                                              FocusScope.of(context).requestFocus(
                                                  _focusNodes[index - 1]);
                                              _controllers[index - 1]
                                                      .selection =
                                                  TextSelection.collapsed(
                                                offset: _controllers[index - 1]
                                                    .text
                                                    .length,
                                              );
                                            }
                                          }
                                        },
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),

                            const SizedBox(height: 26),

                            // ---------- Confirm button ----------
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _confirmCode,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 3,
                                ),
                                child: _loading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        "Verify Email",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  "Didn’t receive the code? ",
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 13,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loading ? null : _resendCode,
                                  child: const Text(
                                    "Resend",
                                    style: TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
