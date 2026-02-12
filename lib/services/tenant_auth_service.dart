// lib/services/tenant_auth_service.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_finder/TENANT/TVERIFICATION.dart';

class TenantAuthService {
  static final _sb = Supabase.instance.client;

  static Future<void> registerTenant({
    required BuildContext context,
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    email = email.trim().toLowerCase();

    if (email.isEmpty || password.isEmpty || fullName.trim().isEmpty) {
      _toast(context, 'Please fill all required fields');
      return;
    }

    try {
      // If the email already exists in your `users` table, honor its role.
      final existing = await _sb
          .from('users')
          .select('id, role')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        final role = (existing['role'] as String?)?.toLowerCase();
        if (role != 'tenant') {
          _toast(
            context,
            'This email is already used by a $role account. '
            'Please use a different email for a tenant account.',
          );
          return;
        }

        // The email already belongs to a tenant user_id in your app table.
        // Do NOT create another tenant_profile for the same auth user if your
        // DB trigger forbids it. Let them log in instead.
        _toast(context, 'Email already registered as tenant. Please log in.');
        return;
      }

      // 1) Supabase Auth (creates auth.users row)
      final signUpRes = await _sb.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName, 'role': 'tenant'},
      );
      final authUser = signUpRes.user;
      if (authUser == null) {
        throw AuthException(
          'Sign-up created but no user returned. '
          'If Auth email confirmations are enabled, disable them for this OTP flow.',
        );
      }
      final userId = authUser.id;

      // 2) Mirror into app `users` with role=tenant
      final hash = sha256.convert(utf8.encode(password)).toString();
      await _sb.from('users').insert({
        'id': userId,
        'email': email,
        'full_name': fullName.trim(),
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
        'password': hash,
        'role': 'tenant',
        'is_verified': false,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 3) Double-check the role we just wrote (defensive)
      final u = await _sb
          .from('users')
          .select('role')
          .eq('id', userId)
          .single();
      if ((u['role'] as String?)?.toLowerCase() != 'tenant') {
        _toast(
          context,
          'Account was not created as tenant. Please contact support.',
        );
        return;
      }

      // 4) Create tenant_profile (will succeed because role is tenant)
      await _sb.from('tenant_profile').insert({
        'user_id': userId,
        'full_name': fullName.trim(),
        'phone': (phone ?? '').trim().isEmpty ? null : phone!.trim(),
      });

      // 5) Send OTP via Edge Function (keeps keys out of the app)
      await _sb.functions.invoke('send_otp', body: {
        'email': email,
        'user_id': userId,
        'full_name': fullName,
      });

      // 6) Navigate to verification (pass userId/fullName if your screen requires them)
      if (context.mounted) {
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
      }
    } on AuthException catch (e) {
      _toast(context, 'Auth error: ${e.message}');
    } on PostgrestException catch (e) {
      _toast(context, 'Database error: ${e.message}');
    } catch (e) {
      _toast(context, 'Error: $e');
    }
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
