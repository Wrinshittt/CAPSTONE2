// lib/LANDLORD/REGISTER.dart
// ✅ FIXED: Prevents "Invalid login credentials" popup during REGISTER
// - Registration no longer tries to signIn when email already exists
// - If email is already registered, user is told to LOGIN / reset password instead

import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:typed_data';

import 'package:geolocator/geolocator.dart' as geo;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/LANDLORD/VERIFICATION.dart';

/// ✅ Allows typing decimals, AND also allows the formatted suffix once applied:
///   150
///   150.0
///   150.00
///   150.00 /head
///   150.00 /watts
class SuffixNumberFormatter extends TextInputFormatter {
  final String suffixWord; // "head" or "watts"
  SuffixNumberFormatter(this.suffixWord);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final regex = RegExp(
      r'^\d*\.?\d{0,2}(\s\/' + RegExp.escape(suffixWord) + r')?$',
    );

    if (regex.hasMatch(text)) return newValue;
    return oldValue;
  }
}

class RegisterL extends StatefulWidget {
  /// If true, this acts as a "Reapply" form for an already-registered landlord.
  final bool isReapply;

  const RegisterL({super.key, this.isReapply = false});

  @override
  State<RegisterL> createState() => _RegisterState();
}

class _RegisterState extends State<RegisterL> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _addressController = TextEditingController();
  final _apartmentNameController = TextEditingController();

  // ✅ Branch 2 controller
  final _apartmentName2Controller = TextEditingController();

  // ✅ controls visibility of Branch 2 field
  bool _showBranch2 = false;

  final _contactNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // ✅ pricing fields
  final _waterPerHeadController = TextEditingController();
  final _perWattPriceController = TextEditingController();

  // ✅ focus nodes so we can detect "leave field"
  final FocusNode _waterFocus = FocusNode();
  final FocusNode _wattFocus = FocusNode();

  String _selectedGender = 'Male';
  bool _loading = false;

  bool _locating = false; // spinner flag

  // password visibility toggles
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // flag to know when submit was pressed (to start showing red highlights)
  bool _submitted = false;

  // per-field error flags for red highlight
  bool _firstNameError = false;
  bool _lastNameError = false;
  bool _birthdayError = false;
  bool _addressError = false;
  bool _apartmentError = false;

  bool _contactError = false;
  bool _emailError = false;
  bool _passwordError = false;
  bool _confirmPasswordError = false;

  // pricing error flags
  bool _waterPerHeadError = false;
  bool _perWattPriceError = false;

  PlatformFile? _barangayClearance;
  PlatformFile? _businessPermit;
  PlatformFile? _validId1;
  PlatformFile? _validId2;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    // ✅ When user leaves water field => append " /head"
    _waterFocus.addListener(() {
      if (!_waterFocus.hasFocus) {
        _applySuffixFormat(
          controller: _waterPerHeadController,
          suffix: ' /head',
        );
      }
    });

    // ✅ When user leaves watt field => append " /watts"
    _wattFocus.addListener(() {
      if (!_wattFocus.hasFocus) {
        _applySuffixFormat(
          controller: _perWattPriceController,
          suffix: ' /watts',
        );
      }
    });

    if (widget.isReapply) {
      _prefillExistingData();
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _birthdayController.dispose();
    _addressController.dispose();
    _apartmentNameController.dispose();
    _apartmentName2Controller.dispose();

    _contactNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();

    _waterPerHeadController.dispose();
    _perWattPriceController.dispose();

    _waterFocus.dispose();
    _wattFocus.dispose();

    super.dispose();
  }

  // dialog helper
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

  /// Extract just the numeric part from text like "12.50 /head"
  double? _toDoubleOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;

    // keep digits and dot only
    final cleaned = t.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;

    return double.tryParse(cleaned);
  }

  /// When leaving field, normalize value to: "<number with 2 decimals><suffix>"
  void _applySuffixFormat({
    required TextEditingController controller,
    required String suffix,
  }) {
    final v = _toDoubleOrNull(controller.text);
    if (v == null) return;

    final formatted = '${v.toStringAsFixed(2)}$suffix';

    if (controller.text.trim() == formatted) return;

    controller.text = formatted;
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );
    if (mounted) setState(() {});
  }

  void _toggleBranch2() {
    setState(() {
      if (_showBranch2) {
        _apartmentName2Controller.clear();
        _showBranch2 = false;
      } else {
        _showBranch2 = true;
      }
    });
  }

  /// Load existing landlord info (for reapply mode only).
  Future<void> _prefillExistingData() async {
    setState(() => _loading = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _msg('You must be logged in to reapply.');
        return;
      }

      final userId = user.id;

      // Fetch from users table
      Map<String, dynamic>? usersRow;
      try {
        usersRow = await supabase
            .from('users')
            .select('first_name,last_name,full_name,email,phone')
            .eq('id', userId)
            .maybeSingle();
      } catch (e) {
        debugPrint('prefill users error: $e');
      }

      // Fetch landlord_profile
      Map<String, dynamic>? landlordProfile;
      try {
        landlordProfile = await supabase
            .from('landlord_profile')
            .select(
              'first_name,last_name,birthday,gender,address,apartment_name,apartment_name_2,contact_number,water_per_head,per_watt_price',
            )
            .eq('user_id', userId)
            .maybeSingle();
      } catch (e) {
        debugPrint('prefill landlord_profile error: $e');
      }

      String? firstName = landlordProfile?['first_name'] as String? ??
          usersRow?['first_name'] as String?;
      String? lastName = landlordProfile?['last_name'] as String? ??
          usersRow?['last_name'] as String?;
      String? fullName = usersRow?['full_name'] as String?;
      final email = (usersRow?['email'] as String?) ?? user.email;

      // If first/last are missing, split from full_name
      if ((firstName == null || firstName.trim().isEmpty) &&
          fullName != null &&
          fullName.trim().isNotEmpty) {
        final parts = fullName.trim().split(' ');
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }

      _firstNameController.text = firstName ?? '';
      _lastNameController.text = lastName ?? '';
      _emailController.text = email ?? '';

      _birthdayController.text = (landlordProfile?['birthday'] as String?) ?? '';
      _selectedGender =
          (landlordProfile?['gender'] as String?)?.trim().isNotEmpty == true
              ? landlordProfile!['gender'] as String
              : _selectedGender;
      _addressController.text = (landlordProfile?['address'] as String?) ?? '';
      _apartmentNameController.text =
          (landlordProfile?['apartment_name'] as String?) ?? '';

      final branch2 = (landlordProfile?['apartment_name_2'] as String?) ?? '';
      _apartmentName2Controller.text = branch2;

      // ✅ show Branch 2 field if existing
      _showBranch2 = branch2.trim().isNotEmpty;

      _contactNumberController.text =
          (landlordProfile?['contact_number'] as String?) ??
              (usersRow?['phone'] as String? ?? '');

      // ✅ prefill pricing WITH suffixes
      final water = landlordProfile?['water_per_head'];
      final watt = landlordProfile?['per_watt_price'];

      _waterPerHeadController.text =
          water == null ? '' : '${water.toString()} /head';
      _perWattPriceController.text =
          watt == null ? '' : '${watt.toString()} /watts';
    } catch (e) {
      debugPrint('prefill error: $e');
      _msg('Could not load your existing information.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      if (!mounted) return;
      setState(() {
        _birthdayController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  // Build a readable single-line address from a placemark
  String _formatPlacemark(geocoding.Placemark p) {
    final parts = <String?>[
      p.street,
      p.subLocality,
      p.locality,
      p.administrativeArea,
      p.postalCode,
      p.country,
    ]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  Future<geo.Position?> _getBestPosition() async {
    try {
      return await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // continue
    } on PlatformException catch (e) {
      debugPrint('getCurrentPosition PlatformException: ${e.message}');
    } catch (_) {}

    try {
      final last = await geo.Geolocator.getLastKnownPosition();
      if (last != null) return last;
    } catch (_) {}

    try {
      final stream = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );
      return await stream.first.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('getPositionStream PlatformException: ${e.message}');
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _detectLocationAndFillAddress() async {
    FocusScope.of(context).unfocus();
    if (!mounted) return;
    setState(() => _locating = true);

    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _msg('Location services are disabled.');
        return;
      }

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
        if (permission == geo.LocationPermission.denied) {
          _msg('Location permissions are denied.');
          return;
        }
      }
      if (permission == geo.LocationPermission.deniedForever) {
        _msg('Location permissions are permanently denied.');
        return;
      }

      final pos = await _getBestPosition();
      if (pos == null) {
        _msg('Couldn’t get a GPS fix. Try again near a window or outdoors.');
        return;
      }

      final placemarks = await geocoding.placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isEmpty) {
        _msg('Unable to detect address from current location.');
        return;
      }

      final formatted = _formatPlacemark(placemarks.first);
      if (!mounted) return;
      setState(() => _addressController.text = formatted);
      _msg('Address automatically detected!');
    } on geo.PermissionDefinitionsNotFoundException {
      _msg('Missing location permission declarations in AndroidManifest.xml.');
    } on geo.LocationServiceDisabledException {
      _msg('Please enable Location Services.');
    } on PlatformException {
      _msg('Location provider had a hiccup. Please try again in a few seconds.');
    } on TimeoutException {
      _msg('Getting location timed out. Try again near a window or outdoors.');
    } catch (e) {
      _msg('Could not get location.');
      debugPrint('Location error: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _sendOtp({
    required String email,
    required String userId,
    required String fullName,
  }) async {
    final res = await supabase.functions.invoke(
      'send_otp',
      body: {'email': email, 'user_id': userId, 'full_name': fullName},
    );
    if (res.status >= 400) {
      throw Exception("Failed to send code: ${res.data}");
    }
  }

  Future<void> _ensureLandlordRole(String userId) async {
    try {
      await supabase.from('user_roles').upsert({
        'user_id': userId,
        'role': 'landlord',
      }, onConflict: 'user_id,role');
    } catch (_) {
      try {
        await supabase.from('user_roles').insert({
          'user_id': userId,
          'role': 'landlord',
        });
      } catch (_) {}
    }
  }

  Future<void> _pickDoc(void Function(PlatformFile?) assign) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf', 'heic', 'webp'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      if (file.bytes == null) {
        _msg('Failed to read file bytes.');
        return;
      }
      assign(file);
      if (mounted) setState(() {});
    }
  }

  Future<void> _uploadOneDoc({
    required String userId,
    required PlatformFile file,
    required String docType,
  }) async {
    final bytes = file.bytes!;
    String clean(String s) => s.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');

    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = '$userId/${ts}_${clean(docType)}_${clean(file.name)}';

    await supabase.storage.from('landlord-docs').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );

    await supabase.from('landlord_documents').insert({
      'user_id': userId,
      'doc_type': docType,
      'storage_path': path,
      'original_filename': file.name,
    });
  }

  Future<void> _uploadAllDocs(String userId) async {
    if (_barangayClearance != null) {
      await _uploadOneDoc(
        userId: userId,
        file: _barangayClearance!,
        docType: 'barangay_clearance',
      );
    }
    if (_businessPermit != null) {
      await _uploadOneDoc(
        userId: userId,
        file: _businessPermit!,
        docType: 'business_permit',
      );
    }
    if (_validId1 != null) {
      await _uploadOneDoc(
        userId: userId,
        file: _validId1!,
        docType: 'valid_id',
      );
    }
    if (_validId2 != null) {
      await _uploadOneDoc(
        userId: userId,
        file: _validId2!,
        docType: 'valid_id_2',
      );
    }
  }

  // ✅ FIXED REGISTER FLOW
  Future<void> _registerLandlord() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final birthday = _birthdayController.text.trim();
    final address = _addressController.text.trim();
    final aptName = _apartmentNameController.text.trim();
    final aptName2 = _apartmentName2Controller.text.trim();

    final phone = _contactNumberController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    final waterPerHead = _toDoubleOrNull(_waterPerHeadController.text);
    final perWattPrice = _toDoubleOrNull(_perWattPriceController.text);

    setState(() {
      _submitted = true;
      _firstNameError = firstName.isEmpty;
      _lastNameError = lastName.isEmpty;
      _birthdayError = birthday.isEmpty;
      _addressError = address.isEmpty;
      _apartmentError = aptName.isEmpty;

      _contactError = phone.isEmpty;
      _emailError = email.isEmpty || !email.contains('@');
      _passwordError = !widget.isReapply && password.isEmpty;
      _confirmPasswordError = !widget.isReapply &&
          (confirmPassword.isEmpty || password != confirmPassword);

      _waterPerHeadError = waterPerHead == null;
      _perWattPriceError = perWattPrice == null;
    });

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        (!widget.isReapply && password.isEmpty)) {
      _msg('All required fields must be filled.');
      return;
    }
    if (!email.contains('@')) {
      _msg('Please enter a valid email.');
      return;
    }
    if (!widget.isReapply && password != confirmPassword) {
      _msg('Passwords do not match.');
      return;
    }
    if (waterPerHead == null || perWattPrice == null) {
      _msg('Please enter valid numbers for Water per head and Per watt price.');
      return;
    }

    setState(() => _loading = true);

    try {
      // =======================
      // REAPPLY MODE (logged-in)
      // =======================
      if (widget.isReapply) {
        final authUser = supabase.auth.currentUser;
        if (authUser == null) {
          _msg('You must be logged in to reapply.');
          return;
        }
        final userId = authUser.id;

        await supabase.from('users').update({
          'full_name': '$firstName $lastName',
          'first_name': firstName,
          'last_name': lastName,
          'phone': phone.isEmpty ? null : phone,
        }).eq('id', userId);

        try {
          await supabase.auth.updateUser(
            UserAttributes(data: {'full_name': '$firstName $lastName'}),
          );
        } catch (e) {
          debugPrint('updateUser metadata error: $e');
        }

        await supabase.from('landlord_profile').upsert({
          'user_id': userId,
          'first_name': firstName,
          'last_name': lastName,
          'birthday': birthday,
          'gender': _selectedGender,
          'address': address,
          'apartment_name': aptName,
          'apartment_name_2':
              (_showBranch2 && aptName2.isNotEmpty) ? aptName2 : null,
          'contact_number': phone,
          'water_per_head': waterPerHead,
          'per_watt_price': perWattPrice,
        });

        await _uploadAllDocs(userId);

        await supabase.from('notifications').insert({
          'user_id': userId,
          'title': 'Landlord reapplied',
          'body':
              'Landlord has updated their details and documents for re-evaluation.',
          'type': 'landlord_reapplied',
          'is_read': false,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });

        if (!mounted) return;
        _msg('Your details have been submitted for re-evaluation.');
        Navigator.pop(context, true);
        return;
      }

      // =======================
      // NEW REGISTRATION MODE
      // =======================
      late final String userId;

      // ✅ IMPORTANT FIX:
      // Do NOT signInWithPassword during REGISTER.
      // If email is already registered, show message to login instead.
      try {
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {'full_name': '$firstName $lastName', 'role': 'landlord'},
        );

        final authUser = res.user;
        if (authUser == null) {
          throw Exception('Sign-up failed. Please try again.');
        }
        userId = authUser.id;
      } on AuthException catch (e) {
        final msg = e.message.toLowerCase();
        if (msg.contains('already') || msg.contains('registered')) {
          _msg(
            "This email is already registered.\n\n"
            "Please go to Login, or use Forgot Password to reset your password.",
          );
          return;
        }
        _msg('Auth error: ${e.message}');
        return;
      }

      // ✅ Save to your tables
      final hashed = sha256.convert(utf8.encode(password)).toString();

      await supabase.from('users').upsert({
        'id': userId,
        'full_name': '$firstName $lastName',
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone': phone.isEmpty ? null : phone,

        // ⚠️ Optional: you don't need this if Supabase Auth is your only login system.
        'password': hashed,

        'role': 'landlord',
        'is_verified': false,
      });

      await _ensureLandlordRole(userId);

      await supabase.from('landlord_profile').upsert({
        'user_id': userId,
        'first_name': firstName,
        'last_name': lastName,
        'birthday': birthday,
        'gender': _selectedGender,
        'address': address,
        'apartment_name': aptName,
        'apartment_name_2':
            (_showBranch2 && aptName2.isNotEmpty) ? aptName2 : null,
        'contact_number': phone,
        'water_per_head': waterPerHead,
        'per_watt_price': perWattPrice,
      });

      await _uploadAllDocs(userId);

      await _sendOtp(
        email: email,
        userId: userId,
        fullName: '$firstName $lastName',
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => Verification(email: email, userId: userId),
        ),
      );
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Password strength helpers ----------
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
      return const Color(0xFFDC2626);
    } else if (label.startsWith('Medium')) {
      return const Color(0xFFF97316);
    } else {
      return const Color(0xFF16A34A);
    }
  }

  bool get _passwordsMismatch {
    final p = _passwordController.text;
    final c = _confirmPasswordController.text;
    if (p.isEmpty || c.isEmpty) return false;
    return p != c;
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.isReapply
        ? 'Update your landlord profile'
        : 'Create your landlord account';
    final subtitleText = widget.isReapply
        ? 'Review and update your information so we can re-evaluate your account.'
        : 'Provide a few details so we can verify your identity and apartment.';
    final buttonLabel = widget.isReapply ? 'SUBMIT FOR REVIEW' : 'REGISTER';

    final passwordText = _passwordController.text;

    final firstNameError = _firstNameError;
    final lastNameError = _lastNameError;
    final birthdayError = _birthdayError;
    final addressError = _addressError;
    final apartmentError = _apartmentError;
    final contactError = _contactError;
    final emailError = _emailError;
    final passwordError = _passwordError;
    final confirmPasswordError = _confirmPasswordError;

    final waterError = _waterPerHeadError;
    final wattError = _perWattPriceError;

    return Scaffold(
      backgroundColor: const Color(0xFF021623),
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
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
                                      'Landlord onboarding',
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
                                  widget.isReapply
                                      ? Icons.refresh_rounded
                                      : Icons.app_registration_rounded,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  widget.isReapply
                                      ? 'Re-application in review'
                                      : 'New landlord registration',
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
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titleText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitleText,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.78),
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.person_outline,
                                title: 'Personal information',
                                subtitle:
                                    'Basic details about you as the property owner.',
                              ),
                              const SizedBox(height: 12),

                              _buildTextField(
                                _firstNameController,
                                'First Name',
                                Icons.person_outline,
                                isError: firstNameError,
                                onChanged: (_) {
                                  if (_submitted && _firstNameError) {
                                    setState(() => _firstNameError = false);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              _buildTextField(
                                _lastNameController,
                                'Last Name',
                                Icons.person_outline,
                                isError: lastNameError,
                                onChanged: (_) {
                                  if (_submitted && _lastNameError) {
                                    setState(() => _lastNameError = false);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),

                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: _selectDate,
                                      child: AbsorbPointer(
                                        child: _buildTextField(
                                          _birthdayController,
                                          'Birthday',
                                          Icons.calendar_today_outlined,
                                          isError: birthdayError,
                                          onChanged: (_) {
                                            if (_submitted && _birthdayError) {
                                              setState(() =>
                                                  _birthdayError = false);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildDropdownField(
                                      'Gender',
                                      _selectedGender,
                                      Icons.male,
                                      (v) => setState(
                                          () => _selectedGender = v ?? 'Male'),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 18),
                              Divider(
                                color: Colors.white.withOpacity(0.14),
                                height: 28,
                              ),

                              const _SectionHeader(
                                icon: Icons.home_work_outlined,
                                title: 'Property & contact',
                                subtitle:
                                    'Where is your apartment and how can we reach you?',
                              ),
                              const SizedBox(height: 12),

                              _addressField(isError: addressError),
                              const SizedBox(height: 10),

                              _buildTextField(
                                _apartmentNameController,
                                'Apartment Name',
                                Icons.apartment,
                                isError: apartmentError,
                                onChanged: (_) {
                                  if (_submitted && _apartmentError) {
                                    setState(() => _apartmentError = false);
                                  }
                                },
                                suffixIcon: IconButton(
                                  tooltip: _showBranch2
                                      ? 'Remove Branch 2'
                                      : 'Add Branch 2',
                                  icon: Icon(
                                    _showBranch2
                                        ? Icons.close_rounded
                                        : Icons.add_rounded,
                                    color: const Color(0xFF6B7280),
                                    size: 18,
                                  ),
                                  onPressed: _toggleBranch2,
                                ),
                              ),

                              if (_showBranch2) ...[
                                const SizedBox(height: 10),
                                _buildTextField(
                                  _apartmentName2Controller,
                                  'Apartment Name (Branch 2)',
                                  Icons.apartment_outlined,
                                ),
                              ],

                              const SizedBox(height: 10),

                              _buildTextField(
                                _waterPerHeadController,
                                'Water per head (₱)',
                                Icons.water_drop_outlined,
                                focusNode: _waterFocus,
                                inputType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [SuffixNumberFormatter('head')],
                                isError: waterError,
                                onChanged: (_) {
                                  if (_submitted && _waterPerHeadError) {
                                    setState(() => _waterPerHeadError = false);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),

                              _buildTextField(
                                _perWattPriceController,
                                'Per watt price (₱)',
                                Icons.bolt_outlined,
                                focusNode: _wattFocus,
                                inputType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [SuffixNumberFormatter('watts')],
                                isError: wattError,
                                onChanged: (_) {
                                  if (_submitted && _perWattPriceError) {
                                    setState(() => _perWattPriceError = false);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),

                              _buildTextField(
                                _contactNumberController,
                                'Contact Number',
                                Icons.phone_outlined,
                                inputType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(11),
                                ],
                                isError: contactError,
                                onChanged: (_) {
                                  if (_submitted && _contactError) {
                                    setState(() => _contactError = false);
                                  }
                                },
                              ),

                              const SizedBox(height: 18),
                              Divider(
                                color: Colors.white.withOpacity(0.14),
                                height: 28,
                              ),

                              _SectionHeader(
                                icon: Icons.lock_outline,
                                title: 'Account details',
                                subtitle: widget.isReapply
                                    ? 'Email is fixed. You can update your profile data below.'
                                    : 'We’ll use this email for login and verification.',
                              ),
                              const SizedBox(height: 12),

                              _buildTextField(
                                _emailController,
                                'Email',
                                Icons.email_outlined,
                                inputType: TextInputType.emailAddress,
                                readOnly: widget.isReapply,
                                enabled: !widget.isReapply,
                                isError: emailError,
                                onChanged: (_) {
                                  if (_submitted && _emailError) {
                                    setState(() => _emailError = false);
                                  }
                                },
                              ),

                              if (!widget.isReapply) ...[
                                const SizedBox(height: 10),
                                _buildTextField(
                                  _passwordController,
                                  'Password',
                                  Icons.lock_outline,
                                  obscureText: _obscurePassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: const Color(0xFF6B7280),
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  onChanged: (_) {
                                    if (_submitted && _passwordError) {
                                      setState(() => _passwordError = false);
                                    }
                                    setState(() {});
                                  },
                                  isError: passwordError,
                                ),
                                if (passwordText.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color:
                                              _passwordStrengthColor(passwordText),
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

                                _buildTextField(
                                  _confirmPasswordController,
                                  'Confirm Password',
                                  Icons.lock_outline,
                                  obscureText: _obscureConfirmPassword,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      color: const Color(0xFF6B7280),
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword;
                                      });
                                    },
                                  ),
                                  onChanged: (_) {
                                    if (_submitted && _confirmPasswordError) {
                                      setState(() =>
                                          _confirmPasswordError = false);
                                    }
                                    setState(() {});
                                  },
                                  isError: confirmPasswordError,
                                ),

                                if (_passwordsMismatch) ...[
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Passwords do not match.',
                                    style: TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ],
                              ],

                              const SizedBox(height: 18),
                              Divider(
                                color: Colors.white.withOpacity(0.14),
                                height: 28,
                              ),

                              const _SectionHeader(
                                icon: Icons.file_copy_outlined,
                                title: 'Supporting documents',
                                subtitle:
                                    'Upload clear scans or photos of your documents for verification.',
                              ),
                              const SizedBox(height: 12),

                              _uploadSection(),

                              const SizedBox(height: 22),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _registerLandlord,
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
                                      : Text(
                                          buttonLabel,
                                          style: const TextStyle(
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

                        if (!widget.isReapply)
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
                                onTap: () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const Login()),
                                ),
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
                        if (!widget.isReapply) const SizedBox(height: 10),
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

  Widget _addressField({bool isError = false}) {
    final borderColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB);
    final focusedBorderColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFF2563EB);

    return SizedBox(
      height: 52,
      child: TextField(
        controller: _addressController,
        style: const TextStyle(color: Colors.black),
        maxLines: 1,
        onChanged: (_) {
          if (_submitted && _addressError) {
            setState(() => _addressError = false);
          }
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          prefixIcon: const Icon(Icons.location_on_outlined,
              color: Color(0xFF6B7280)),
          hintText: 'Address',
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
            borderSide: BorderSide(color: focusedBorderColor, width: 1.3),
          ),
          suffixIcon: _locating
              ? const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  tooltip: 'Use my current location',
                  icon: const Icon(Icons.my_location,
                      color: Color(0xFF6B7280)),
                  onPressed: _detectLocationAndFillAddress,
                ),
        ),
      ),
    );
  }

  Widget _uploadSection() => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _uploadButton(
                  'Barangay Clearance',
                  _barangayClearance,
                  () => _pickDoc((f) => _barangayClearance = f),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _uploadButton(
                  'Business Permit',
                  _businessPermit,
                  () => _pickDoc((f) => _businessPermit = f),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _uploadButton(
                  'Valid ID',
                  _validId1,
                  () => _pickDoc((f) => _validId1 = f),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _uploadButton(
                  'Valid ID 2',
                  _validId2,
                  () => _pickDoc((f) => _validId2 = f),
                ),
              ),
            ],
          ),
        ],
      );

  Widget _uploadButton(
    String label,
    PlatformFile? picked,
    VoidCallback onPick,
  ) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPick,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          backgroundColor: const Color(0xFFF9FAFB),
          foregroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.upload_file, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            picked == null ? label : '$label • ${picked.name}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ),
    );
  }

  // ✅ UPDATED: added optional focusNode parameter
  Widget _buildTextField(
    TextEditingController c,
    String h,
    IconData i, {
    FocusNode? focusNode,
    bool obscureText = false,
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    bool enabled = true,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
    bool isError = false,
  }) {
    final borderColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFFE5E7EB);
    final focusedBorderColor =
        isError ? const Color(0xFFDC2626) : const Color(0xFF2563EB);

    return SizedBox(
      height: 52,
      child: TextField(
        controller: c,
        focusNode: focusNode,
        obscureText: obscureText,
        keyboardType: inputType,
        inputFormatters: inputFormatters,
        style: const TextStyle(color: Colors.black),
        readOnly: readOnly,
        enabled: enabled,
        onChanged: onChanged,
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          prefixIcon: Icon(i, color: const Color(0xFF6B7280)),
          hintText: h,
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
            borderSide: BorderSide(color: focusedBorderColor, width: 1.3),
          ),
          suffixIcon: suffixIcon,
        ),
      ),
    );
  }

  Widget _buildDropdownField(
    String hint,
    String currentValue,
    IconData icon,
    ValueChanged<String?> onChanged,
  ) {
    return SizedBox(
      height: 52,
      child: DropdownButtonFormField<String>(
        value: currentValue,
        isDense: true,
        style: const TextStyle(color: Colors.black, fontSize: 14),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          prefixIcon: Icon(icon, color: const Color(0xFF6B7280)),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          contentPadding: const EdgeInsets.symmetric(vertical: 4.0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.3),
          ),
        ),
        onChanged: onChanged,
        items: const [
          DropdownMenuItem(value: 'Male', child: Text('Male')),
          DropdownMenuItem(value: 'Female', child: Text('Female')),
          DropdownMenuItem(value: 'Other', child: Text('Other')),
        ],
      ),
    );
  }
}

/// Small reusable section header widget
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
