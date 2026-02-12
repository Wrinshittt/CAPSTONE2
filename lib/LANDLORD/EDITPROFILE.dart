// lib/LANDLORD/editprofile.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class LandlordEditProfile extends StatefulWidget {
  final String name;
  final String email;
  final String phone;
  final String address;
  final String? currentAvatarUrl;

  // legacy (still supported)
  final String? apartmentName;
  final String? apartmentName2;

  const LandlordEditProfile({
    super.key,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    this.currentAvatarUrl,
    this.apartmentName,
    this.apartmentName2,
  });

  @override
  State<LandlordEditProfile> createState() => _LandlordEditProfileState();
}

/// Toast modal
class InfoToastModal {
  static void show(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: const Color.fromARGB(255, 57, 57, 57).withOpacity(0.10),
        builder: (ctx) {
          Future.delayed(const Duration(seconds: 1), () {
            if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          });

          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.80),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                  decorationColor: Colors.transparent,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class _LandlordEditProfileState extends State<LandlordEditProfile> {
  final _sb = Supabase.instance.client;
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  // ✅ Landlord “home/contact address”
  final _addressCtrl = TextEditingController();

  // ✅ Apartment branches (Apartment name + Location per branch)
  final List<TextEditingController> _branchNameCtrls = [];
  final List<TextEditingController> _branchLocCtrls = [];

  String _defaultAptName = '';
  String _defaultAptLoc = '';

  File? _pickedImage;
  bool _saving = false;

  // document picks
  PlatformFile? _barangayClearance;
  PlatformFile? _businessPermit;
  PlatformFile? _validId1;
  PlatformFile? _validId2;

  @override
  void initState() {
    super.initState();

    _nameCtrl.text = widget.name;
    _emailCtrl.text = widget.email;
    _phoneCtrl.text = widget.phone;
    _addressCtrl.text = widget.address;

    _attachMainFieldListeners();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBranches();
      if (!mounted) return;
      setState(() {});
    });
  }

  void _attachMainFieldListeners() {
    _nameCtrl.addListener(_rebuild);
    _emailCtrl.addListener(_rebuild);
    _phoneCtrl.addListener(_rebuild);
    _addressCtrl.addListener(_rebuild);
  }

  void _attachCtrlListener(TextEditingController ctrl) {
    ctrl.removeListener(_rebuild);
    ctrl.addListener(_rebuild);
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {});
  }

  bool _isFormComplete() {
    final fullNameOk = _nameCtrl.text.trim().isNotEmpty;
    final emailOk = _emailCtrl.text.trim().isNotEmpty;
    final phoneOk = _phoneCtrl.text.trim().isNotEmpty;
    final addressOk = _addressCtrl.text.trim().isNotEmpty;

    final branchesOk = _branchNameCtrls.isNotEmpty &&
        _branchLocCtrls.isNotEmpty &&
        _branchNameCtrls.length == _branchLocCtrls.length &&
        _branchNameCtrls.every((c) => c.text.trim().isNotEmpty) &&
        _branchLocCtrls.every((c) => c.text.trim().isNotEmpty);

    return fullNameOk && emailOk && phoneOk && addressOk && branchesOk;
  }

  Future<void> _loadDefaultsFromDb(String uid) async {
    try {
      final lp = await _sb
          .from('landlord_profile')
          .select('apartment_name, address')
          .eq('user_id', uid)
          .maybeSingle();

      final dbApt = (lp?['apartment_name'] ?? '').toString().trim();
      final dbLoc = (lp?['address'] ?? '').toString().trim();

      _defaultAptName = dbApt.isNotEmpty ? dbApt : (widget.apartmentName ?? '').trim();
      _defaultAptLoc = dbLoc.isNotEmpty ? dbLoc : widget.address.trim();
    } catch (_) {
      _defaultAptName = (widget.apartmentName ?? '').trim();
      _defaultAptLoc = widget.address.trim();
    }
  }

  void _ensureDefaultRowExistsAtTop() {
    // align lengths
    while (_branchLocCtrls.length < _branchNameCtrls.length) {
      final locCtrl = TextEditingController(text: _defaultAptLoc);
      _attachCtrlListener(locCtrl);
      _branchLocCtrls.add(locCtrl);
    }
    while (_branchNameCtrls.length < _branchLocCtrls.length) {
      final nameCtrl = TextEditingController(text: _defaultAptName);
      _attachCtrlListener(nameCtrl);
      _branchNameCtrls.add(nameCtrl);
    }

    if (_branchNameCtrls.isEmpty) {
      final nameCtrl = TextEditingController(text: _defaultAptName);
      final locCtrl = TextEditingController(text: _defaultAptLoc);
      _attachCtrlListener(nameCtrl);
      _attachCtrlListener(locCtrl);
      _branchNameCtrls.add(nameCtrl);
      _branchLocCtrls.add(locCtrl);
      return;
    }

    // fill first row if empty
    if (_branchNameCtrls.first.text.trim().isEmpty && _defaultAptName.isNotEmpty) {
      _branchNameCtrls.first.text = _defaultAptName;
    }
    if (_branchLocCtrls.first.text.trim().isEmpty && _defaultAptLoc.isNotEmpty) {
      _branchLocCtrls.first.text = _defaultAptLoc;
    }
  }

  Future<void> _loadBranches() async {
    final uid = _sb.auth.currentUser?.id;

    for (final c in _branchNameCtrls) {
      c.dispose();
    }
    for (final c in _branchLocCtrls) {
      c.dispose();
    }
    _branchNameCtrls.clear();
    _branchLocCtrls.clear();

    if (uid == null) {
      _defaultAptName = (widget.apartmentName ?? '').trim();
      _defaultAptLoc = widget.address.trim();
      _ensureDefaultRowExistsAtTop();
      return;
    }

    await _loadDefaultsFromDb(uid);

    try {
      // ✅ REQUIRED columns: branch_name, branch_location
      final rows = await _sb
          .from('landlord_branches')
          .select('branch_name, branch_location, created_at')
          .eq('landlord_id', uid)
          .order('created_at', ascending: true) as List;

      for (final r in rows) {
        final n = (r['branch_name'] ?? '').toString().trim();
        final loc = (r['branch_location'] ?? '').toString().trim();
        if (n.isEmpty && loc.isEmpty) continue;

        final nameCtrl = TextEditingController(text: n);
        final locCtrl = TextEditingController(text: loc);
        _attachCtrlListener(nameCtrl);
        _attachCtrlListener(locCtrl);
        _branchNameCtrls.add(nameCtrl);
        _branchLocCtrls.add(locCtrl);
      }

      _ensureDefaultRowExistsAtTop();
    } catch (e) {
      debugPrint('Failed to load branches: $e');
      _ensureDefaultRowExistsAtTop();
    }
  }

  Future<bool> _confirmDelete({required String branchLabel}) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete apartment branch?'),
          content: Text(
            'Are you sure you want to delete "$branchLabel"?\n\nThis will remove this branch name + location.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<bool> _confirmAddBranch({
    required String branchLabel,
    required String branchName,
    required String branchLocation,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add new apartment branch?'),
          content: Text(
            'Confirm details for "$branchLabel":\n\n'
            'Apartment: "$branchName"\n'
            'Location: "$branchLocation"\n\n'
            'After confirming, we will add a new empty field for the next branch.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  bool _canAddBranch() {
    if (_branchNameCtrls.isEmpty || _branchLocCtrls.isEmpty) return false;
    if (_branchNameCtrls.length != _branchLocCtrls.length) return false;

    final lastName = _branchNameCtrls.last.text.trim();
    final lastLoc = _branchLocCtrls.last.text.trim();
    return lastName.isNotEmpty && lastLoc.isNotEmpty;
  }

  Future<void> _addBranchWithConfirmation() async {
    if (!_canAddBranch()) {
      InfoToastModal.show(context, 'Please enter apartment name and location first.');
      return;
    }

    final lastIndex = _branchNameCtrls.length - 1;
    final lastName = _branchNameCtrls.last.text.trim();
    final lastLoc = _branchLocCtrls.last.text.trim();

    final lastLabel = (lastIndex == 0) ? 'Default Apartment' : 'Apartment Branch ${lastIndex + 1}';

    final ok = await _confirmAddBranch(
      branchLabel: lastLabel,
      branchName: lastName,
      branchLocation: lastLoc,
    );
    if (!ok || !mounted) return;

    setState(() {
      final newNameCtrl = TextEditingController();
      final newLocCtrl = TextEditingController();
      _attachCtrlListener(newNameCtrl);
      _attachCtrlListener(newLocCtrl);
      _branchNameCtrls.add(newNameCtrl);
      _branchLocCtrls.add(newLocCtrl);
    });
  }

  Future<void> _removeBranch(int index) async {
    if (index == 0) {
      InfoToastModal.show(context, 'Default apartment cannot be deleted.');
      return;
    }
    if (index < 0 || index >= _branchNameCtrls.length) return;

    final label = 'Apartment Branch ${index + 1}';
    final ok = await _confirmDelete(branchLabel: label);
    if (!ok || !mounted) return;

    setState(() {
      final nameCtrl = _branchNameCtrls.removeAt(index);
      final locCtrl = _branchLocCtrls.removeAt(index);
      nameCtrl.dispose();
      locCtrl.dispose();
    });
  }

  Future<String?> _uploadAvatarIfNeeded(String uid) async {
    if (_pickedImage == null) return null;

    final storage = _sb.storage.from('avatars');
    final ext = p.extension(_pickedImage!.path).toLowerCase();
    final useExt = (ext == '.png' || ext == '.jpg' || ext == '.jpeg') ? ext : '.jpg';
    final contentType = (useExt == '.png') ? 'image/png' : 'image/jpeg';
    final objectName = '$uid$useExt';

    await storage.upload(
      objectName,
      _pickedImage!,
      fileOptions: FileOptions(upsert: true, contentType: contentType),
    );
    return storage.getPublicUrl(objectName);
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
        InfoToastModal.show(context, 'Failed to read file bytes.');
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

    await _sb.storage.from('landlord-docs').uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(upsert: true),
    );

    await _sb.from('landlord_documents').insert({
      'user_id': userId,
      'doc_type': docType,
      'storage_path': path,
      'original_filename': file.name,
    });
  }

  Future<void> _uploadAllDocs(String userId) async {
    if (_barangayClearance != null) {
      await _uploadOneDoc(userId: userId, file: _barangayClearance!, docType: 'barangay_clearance');
    }
    if (_businessPermit != null) {
      await _uploadOneDoc(userId: userId, file: _businessPermit!, docType: 'business_permit');
    }
    if (_validId1 != null) {
      await _uploadOneDoc(userId: userId, file: _validId1!, docType: 'valid_id');
    }
    if (_validId2 != null) {
      await _uploadOneDoc(userId: userId, file: _validId2!, docType: 'valid_id_2');
    }
  }

  Future<void> _save() async {
    if (!_isFormComplete()) {
      InfoToastModal.show(context, 'Please complete all required fields first.');
      return;
    }

    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      InfoToastModal.show(context, 'Not logged in.');
      return;
    }

    setState(() => _saving = true);
    try {
      final avatarUrl = await _uploadAvatarIfNeeded(uid);

      final fullName = _nameCtrl.text.trim();
      String? firstName;
      String? lastName;
      if (fullName.isNotEmpty) {
        final parts = fullName.split(' ');
        firstName = parts.first;
        if (parts.length > 1) lastName = parts.sublist(1).join(' ');
      }

      // users table update
      await _sb.from('users').update({
        'full_name': fullName,
        'first_name': firstName,
        'last_name': lastName,
        'phone': _phoneCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }).eq('id', uid);

      // keep auth metadata in sync
      try {
        await _sb.auth.updateUser(
          UserAttributes(
            data: {
              'full_name': fullName,
              if (avatarUrl != null) 'avatar_url': avatarUrl,
            },
          ),
        );
      } catch (_) {}

      // ✅ Collect branches
      final branchRows = <Map<String, dynamic>>[];
      for (var i = 0; i < _branchNameCtrls.length; i++) {
        final name = _branchNameCtrls[i].text.trim();
        final loc = _branchLocCtrls[i].text.trim();
        if (name.isEmpty) continue;

        branchRows.add({
          'landlord_id': uid,
          'branch_name': name,
          'branch_location': loc, // ✅ now exists in DB
        });
      }

      // ✅ Save branches
      await _sb.from('landlord_branches').delete().eq('landlord_id', uid);
      if (branchRows.isNotEmpty) {
        await _sb.from('landlord_branches').insert(branchRows);
      }

      // Backward compatibility
      final apt1 = branchRows.isNotEmpty ? (branchRows[0]['branch_name'] as String) : '';
      final apt2 = branchRows.length > 1 ? (branchRows[1]['branch_name'] as String) : null;

      await _sb.from('landlord_profile').upsert({
        'user_id': uid,
        'first_name': firstName,
        'last_name': lastName,
        'apartment_name': apt1,
        'apartment_name_2': apt2,
        'address': _addressCtrl.text.trim(),
        'contact_number': _phoneCtrl.text.trim(),
      });

      await _uploadAllDocs(uid);

      if (!mounted) return;
      InfoToastModal.show(context, 'Profile updated.');
      await Future.delayed(const Duration(milliseconds: 1100));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      InfoToastModal.show(context, 'Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ===================== UI HELPERS (NEW, UI ONLY) =====================

  static const Color _cardBg = Colors.white;
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _text = Color(0xFF111827);

  Widget _card({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          )
        ],
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _subSectionTitle(String title, {String? subtitle, IconData? icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null)
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF005B96).withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF005B96), size: 18),
          ),
        if (icon != null) const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 12, height: 1.35),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // Modern, consistent TextField
  Widget _modernField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    bool enabled = true,
    List<TextInputFormatter>? inputFormatters,
    String? hintText,
    Widget? suffixIcon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: inputType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: const TextStyle(color: _text, fontWeight: FontWeight.w600, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
        hintText: hintText,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        prefixIcon: Icon(icon, color: _muted),
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
      ),
    );
  }

  // ✅ BIG FIX for “messy branches”:
  // Turn the branch list into a clean Card + expansion tiles + scroll-safe layout.
  // Each branch becomes one compact tile showing Name + Location summary.
  Widget _branchesCard() {
    final count = _branchNameCtrls.length;

    return _card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF005B96).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.apartment, color: Color(0xFF005B96), size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Apartment branches',
                  style: TextStyle(
                    color: _text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Tip: Keep each branch name unique. Expand a branch to edit its name and location.',
            style: TextStyle(color: _muted, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),

          // Branch list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _branchNameCtrls.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final isLast = index == _branchNameCtrls.length - 1;
              final isDefault = index == 0;

              final branchLabel = isDefault ? 'Default Apartment' : 'Apartment Branch ${index + 1}';

              final enablePlusHere = isLast &&
                  _branchNameCtrls[index].text.trim().isNotEmpty &&
                  _branchLocCtrls[index].text.trim().isNotEmpty;

              final namePreview = _branchNameCtrls[index].text.trim();
              final locPreview = _branchLocCtrls[index].text.trim();

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Theme(
                  // remove default divider from ExpansionTile
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: const Color(0xFF005B96).withOpacity(0.10),
                      child: Icon(isDefault ? Icons.home_outlined : Icons.apartment_outlined,
                          color: const Color(0xFF005B96), size: 18),
                    ),
                    title: Text(
                      namePreview.isEmpty ? branchLabel : namePreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      locPreview.isEmpty ? 'Tap to add location' : locPreview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isDefault)
                          const Padding(
                            padding: EdgeInsets.only(right: 2),
                            child: Icon(Icons.lock_outline_rounded, color: Color(0xFF9CA3AF), size: 18),
                          )
                        else
                          IconButton(
                            tooltip: 'Delete this branch',
                            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFF6B7280), size: 18),
                            onPressed: () => _removeBranch(index),
                          ),
                        if (isLast)
                          IconButton(
                            tooltip: enablePlusHere ? 'Add another branch' : 'Fill name + location first',
                            icon: Icon(
                              Icons.add_rounded,
                              color: enablePlusHere ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF),
                              size: 18,
                            ),
                            onPressed: enablePlusHere ? _addBranchWithConfirmation : null,
                          ),
                        const Icon(Icons.expand_more_rounded, color: Color(0xFF6B7280)),
                      ],
                    ),
                  children: [
  Padding(
    padding: const EdgeInsets.only(top: 6), // extra safe space for floating label
    child: Column(
      children: [
        _modernField(
          controller: _branchNameCtrls[index],
          label: 'Apartment name ($branchLabel)',
          icon: Icons.apartment,
          hintText: 'e.g. Sunrise Residences',
        ),
        const SizedBox(height: 20),
        _modernField(
          controller: _branchLocCtrls[index],
          label: 'Apartment location ($branchLabel)',
          icon: Icons.location_on_outlined,
          hintText: 'e.g. Near UM, Davao City',
          maxLines: 2,
        ),
      ],
    ),
  ),
],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ===================== END UI HELPERS =====================

  @override
  Widget build(BuildContext context) {
    final canSaveNow = _isFormComplete();

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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Top bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () => Navigator.maybePop(context),
                              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 18),
                              tooltip: 'Back',
                            ),
                            Row(
                              children: [
                                Image.asset('assets/images/SMARTFINDER3.png', height: 42),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Smart Finder',
                                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      'Landlord profile',
                                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11.5),
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
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Update your information',
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Keep your profile and apartment details up to date so tenants and admins see accurate information.',
                                style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 13, height: 1.4),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // CONTENT
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionHeader(
                                icon: Icons.person_outline,
                                title: 'Profile details',
                                subtitle: 'Update your name, contact information, apartment and address.',
                              ),
                              const SizedBox(height: 14),

                              _card(
                                child: Column(
                                  children: [
                                    _modernField(
                                      controller: _nameCtrl,
                                      label: 'Full name',
                                      icon: Icons.person_outline,
                                      hintText: 'Your full name',
                                    ),
                                    const SizedBox(height: 12),
                                    _modernField(
                                      controller: _emailCtrl,
                                      label: 'Email',
                                      icon: Icons.email_outlined,
                                      enabled: false,
                                      hintText: 'Email address',
                                    ),
                                    const SizedBox(height: 12),
                                    _modernField(
                                      controller: _phoneCtrl,
                                      label: 'Phone',
                                      icon: Icons.phone_outlined,
                                      inputType: TextInputType.phone,
                                      hintText: 'e.g. 09xxxxxxxxx',
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 14),

                              // ✅ CLEAN branch UI (expandable tiles)
                              _branchesCard(),

                              const SizedBox(height: 14),

                              _card(
                                child: _modernField(
                                  controller: _addressCtrl,
                                  label: 'Home / Contact Address (landlord)',
                                  icon: Icons.home_outlined,
                                  hintText: 'Your personal address',
                                  maxLines: 2,
                                ),
                              ),

                              const SizedBox(height: 22),

                              const _SectionHeader(
                                icon: Icons.file_copy_outlined,
                                title: 'Supporting documents',
                                subtitle: 'Upload updated scans or photos of your landlord documents (optional).',
                              ),
                              const SizedBox(height: 12),

                              _card(
                                child: _uploadSection(),
                              ),

                              const SizedBox(height: 24),

                              SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: (_saving || !canSaveNow) ? null : _save,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF111827),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                                        )
                                      : const Text(
                                          'SAVE CHANGES',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                                        ),
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

  // ✅ Keep your upload section logic unchanged; only minor layout polish inside the card.
  Widget _uploadSection() => Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _uploadButton('Barangay Clearance', _barangayClearance, () => _pickDoc((f) => _barangayClearance = f)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _uploadButton('Business Permit', _businessPermit, () => _pickDoc((f) => _businessPermit = f)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _uploadButton('Valid ID', _validId1, () => _pickDoc((f) => _validId1 = f)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _uploadButton('Valid ID 2', _validId2, () => _pickDoc((f) => _validId2 = f)),
              ),
            ],
          ),
        ],
      );

  Widget _uploadButton(String label, PlatformFile? picked, VoidCallback onPick) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPick,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          backgroundColor: const Color(0xFFF9FAFB),
          foregroundColor: const Color(0xFF111827),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.upload_file, size: 18),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            picked == null ? label : '$label • ${picked.name}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

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
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white.withOpacity(0.78), fontSize: 11.5, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}