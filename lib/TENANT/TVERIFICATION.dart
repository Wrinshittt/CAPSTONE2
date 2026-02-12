// TENANT/TVERIFICATION.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_finder/TENANT/TLOGIN.dart';

class TenantVerification extends StatefulWidget {
  final String email;
  final String userId;
  final String? fullName;

  const TenantVerification({
    super.key,
    required this.email,
    required this.userId,
    this.fullName,
  });

  @override
  State<TenantVerification> createState() => _TenantVerificationState();
}

class _TenantVerificationState extends State<TenantVerification> {
  final supabase = Supabase.instance.client;

  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());

  String get _enteredCode => _controllers.map((c) => c.text.trim()).join();

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _resendCode() async {
    try {
      final res = await supabase.functions.invoke(
        'send_otp',
        body: {
          'email': widget.email,
          'user_id': widget.userId,
          'full_name': widget.fullName,
        },
      );
      if (res.status >= 400) {
        _msg('Resend failed: ${res.data}');
        return;
      }
      _msg('A new code was sent to ${widget.email}.');
    } catch (e) {
      _msg('Resend error: $e');
    }
  }

  Future<void> _confirmCode() async {
    final code = _enteredCode;
    if (code.length != 6) {
      _msg('Please enter the 6-digit code.');
      return;
    }

    try {
      final res = await supabase.functions.invoke(
        'verify_otp',
        body: {'email': widget.email, 'code': code},
      );
      if (res.status >= 400) {
        _msg('Verification failed: ${res.data}');
        return;
      }

      _msg('Verified! You can now log in.');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginT()),
        (_) => false,
      );
    } catch (e) {
      _msg('Error: $e');
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
          // ---- Full background (gradient) ----
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
          // ---- Subtle background image ----
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

                  // ---------- Main card (copied layout from CODE 2) ----------
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
                            Text(
                              "Enter the 6-digit code sent to ${widget.email}",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // ---------- OTP fields (responsive like CODE 2, logic same as CODE 1) ----------
                            LayoutBuilder(
                              builder: (context, constraints) {
                                const int boxes = 6;
                                const double spacing = 8.0;

                                final double totalSpacing =
                                    spacing * (boxes - 1);
                                final double maxWidthForFields =
                                    constraints.maxWidth - totalSpacing;

                                final double fieldWidth =
                                    (maxWidthForFields / boxes)
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
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        maxLength: 1,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          counterText: "",
                                          filled: true,
                                          fillColor: const Color(0xFFF3F4F6),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: BorderSide.none,
                                          ),
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
                                        onChanged: (val) {
                                          // 🔁 keep original CODE 1 OTP logic
                                          if (val.isNotEmpty && index < 5) {
                                            FocusScope.of(context).nextFocus();
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
                                onPressed: _confirmCode,
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
                                child: const Text(
                                  "Confirm",
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
                                  "Didn’t receive? ",
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 13,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _resendCode,
                                  child: const Text(
                                    "Resend code",
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
