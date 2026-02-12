// TENANT/TPROFILEEDIT.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantEditProfile extends StatefulWidget {
  const TenantEditProfile({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    this.currentAvatarUrl,
  });

  final String name;
  final String email;
  final String phone;
  final String address;
  final String? currentAvatarUrl;

  @override
  State<TenantEditProfile> createState() => _TenantEditProfileState();
}

class _TenantEditProfileState extends State<TenantEditProfile> {
  final _sb = Supabase.instance.client;
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // read-only
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  File? _pickedImage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.name;
    _emailCtrl.text = widget.email;
    _phoneCtrl.text = widget.phone;
    _addressCtrl.text = widget.address;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x != null) setState(() => _pickedImage = File(x.path));
  }

  Future<String?> _uploadAvatarIfNeeded(String uid) async {
    if (_pickedImage == null) return null;

    // Always store as <uid>.jpg (stable path, easy to protect with RLS)
    final storage = _sb.storage.from('avatars');
    final path = '$uid.jpg';

    await storage.upload(
      path,
      _pickedImage!,
      fileOptions: const FileOptions(
        upsert: true,
        contentType: 'image/jpeg',
        cacheControl: '1', // revalidate quickly
      ),
    );

    // Break CDN/browser cache after updates
    final base = storage.getPublicUrl(path);
    final v = DateTime.now().millisecondsSinceEpoch;
    return '$base?v=$v';
  }

  Future<void> _save() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Not logged in.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final avatarUrl = await _uploadAvatarIfNeeded(uid);

      final updates = <String, dynamic>{
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

      await _sb.from('users').update(updates).eq('id', uid);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 🔹 Confirmation modal before actually saving
  Future<void> _confirmAndSave() async {
    final shouldSave = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2563EB).withOpacity(0.1),
                      ),
                      child: const Icon(
                        Icons.save_outlined,
                        color: Color(0xFF2563EB),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Save profile changes?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your updated name, contact details, and address will be saved to your tenant profile.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;

    if (!shouldSave) return;

    // proceed with existing save logic
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    // Keep avatar logic for upload (no longer shown in UI as requested)
    final avatar = _pickedImage != null
        ? Image.file(_pickedImage!, fit: BoxFit.cover)
        : (widget.currentAvatarUrl != null &&
                widget.currentAvatarUrl!.isNotEmpty
            ? Image.network(widget.currentAvatarUrl!, fit: BoxFit.cover)
            : const Icon(Icons.person, size: 64, color: Colors.grey));

    return Scaffold(
      backgroundColor: const Color(0xFF00324E),
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
                        // Top "app shell" row (mirrors landlord layout)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () => Navigator.pop(context),
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
                                      'Tenant profile',
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
                                  Icons.edit_outlined,
                                  size: 14,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Edit tenant profile',
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

                        // Page title & subtitle
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Update your information',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Keep your tenant profile up to date so landlords and admins see accurate information.',
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

                        // FORM CONTENT (layout copied from landlord version)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.person_outline,
                                title: 'Profile details',
                                subtitle:
                                    'Update your name, contact information, and address.',
                              ),
                              const SizedBox(height: 14),

                              // NOTE: Upload profile UI removed as requested
                              // FULL NAME
                              _field(
                                Icons.person_outline,
                                'Full name',
                                controller: _nameCtrl,
                              ),
                              const SizedBox(height: 12),

                              // EMAIL (read-only)
                              _field(
                                Icons.email_outlined,
                                'Email',
                                controller: _emailCtrl,
                                enabled: false,
                              ),
                              const SizedBox(height: 12),

                              // PHONE
                              _field(
                                Icons.phone_outlined,
                                'Phone',
                                controller: _phoneCtrl,
                              ),
                              const SizedBox(height: 12),

                              // ADDRESS
                              _field(
                                Icons.location_on_outlined,
                                'Address',
                                controller: _addressCtrl,
                              ),

                              const SizedBox(height: 24),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed:
                                      _saving ? null : _confirmAndSave,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF111827),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          height: 22,
                                          width: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.black,
                                          ),
                                        )
                                      : const Text(
                                          'SAVE CHANGES',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your updates will reflect on your tenant profile once saved.',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 11.5,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
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

  Widget _field(
    IconData icon,
    String hint, {
    required TextEditingController controller,
    bool enabled = true,
  }) {
    return SizedBox(
      height: 52,
      child: TextField(
        controller: controller,
        enabled: enabled,
        style: const TextStyle(color: Colors.black),
        decoration: InputDecoration(
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          prefixIcon: Icon(icon, color: const Color(0xFF6B7280)),
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
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
            borderSide:
                const BorderSide(color: Color(0xFF2563EB), width: 1.3),
          ),
        ),
      ),
    );
  }
}

/// Small reusable section header widget (same style as landlord version)
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
