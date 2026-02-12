// lib/LANDLORD/profile.dart

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_finder/LANDLORD/register.dart';

class Adminprofile extends StatefulWidget {
  /// If landlordId is null, this screen shows the current logged-in landlord's own profile.
  /// If landlordId is provided, this is a tenant view of the specified landlord profile.
  final String? landlordId;

  const Adminprofile(
    this.landlordId, {
    Key? key,
  }) : super(key: key);

  @override
  State<Adminprofile> createState() => _AdminprofileState();
}

class _AdminprofileState extends State<Adminprofile> {
  final supabase = Supabase.instance.client;

  // Basic identity
  String? _firstName;
  String? _lastName;
  String? _email;

  // Extra profile fields from landlord_profile / users
  String? _birthday;
  String? _gender;

  // ✅ Landlord "home/contact address" (not per-branch)
  String? _address;

  String? _phoneNumber;

  // ✅ Branches (dynamic, from landlord_branches)
  List<Map<String, String>> _branches = []; // [{name, location}]
  final List<TextEditingController> _branchNameCtrls = [];
  final List<TextEditingController> _branchLocCtrls = [];

  bool _isEditing = false;
  bool _savingProfile = false;

  // Document preview URLs
  String? _barangayUrl;
  String? _businessPermitUrl;
  String? _validId1Url;
  String? _validId2Url;

  // Avatar
  String? _avatarUrl;
  bool _uploadingAvatar = false;

  bool _isLandlordApproved = false;
  bool _isLandlordRejected = false;
  bool _isPendingReview = false;
  bool _loadingProfile = true;

  bool get _isTenantView => widget.landlordId != null;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    for (final c in _branchNameCtrls) {
      c.dispose();
    }
    for (final c in _branchLocCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // -------------------- BRANCH EDIT HELPERS --------------------

  void _resetBranchControllersFromBranches() {
    for (final c in _branchNameCtrls) {
      c.dispose();
    }
    for (final c in _branchLocCtrls) {
      c.dispose();
    }
    _branchNameCtrls.clear();
    _branchLocCtrls.clear();

    for (final b in _branches) {
      _branchNameCtrls.add(TextEditingController(text: b['name'] ?? ''));
      _branchLocCtrls.add(TextEditingController(text: b['location'] ?? ''));
    }

    // Ensure at least 1 row exists for editing self
    if (!_isTenantView && _branchNameCtrls.isEmpty) {
      _branchNameCtrls.add(TextEditingController());
      _branchLocCtrls.add(TextEditingController());
    }
  }

  void _addBranchRow() {
    setState(() {
      _branchNameCtrls.add(TextEditingController());
      _branchLocCtrls.add(TextEditingController());
    });
  }

  Future<void> _removeBranchRow(int index) async {
    if (index < 0 || index >= _branchNameCtrls.length) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete branch?'),
        content: const Text('This will remove this apartment branch.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      _branchNameCtrls[index].dispose();
      _branchLocCtrls[index].dispose();
      _branchNameCtrls.removeAt(index);
      _branchLocCtrls.removeAt(index);
    });

    // keep at least 1 row for self editing
    if (!_isTenantView && _branchNameCtrls.isEmpty) {
      _addBranchRow();
    }
  }

  List<Map<String, String>> _collectBranchesFromControllers() {
    final out = <Map<String, String>>[];
    for (var i = 0; i < _branchNameCtrls.length; i++) {
      final name = _branchNameCtrls[i].text.trim();
      final loc = _branchLocCtrls[i].text.trim();
      if (name.isEmpty && loc.isEmpty) continue;
      if (name.isEmpty) continue; // require name
      out.add({'name': name, 'location': loc});
    }
    return out;
  }

  // -------------------- LOAD PROFILE --------------------

  Future<void> _loadProfile() async {
    try {
      final authUser = supabase.auth.currentUser;

      final viewingUserId = widget.landlordId ?? authUser?.id;
      if (viewingUserId == null) {
        setState(() => _loadingProfile = false);
        return;
      }

      String? firstName;
      String? lastName;
      String? email;
      String? birthday;
      String? gender;
      String? address;
      String? phoneNumber;

      // legacy fallback branches (if landlord_branches is empty)
      String? legacyApt1;
      String? legacyApt2;

      Map<String, dynamic>? landlordProfileRow;

      // ---------- Avatar ----------
      String? avatarUrl;
      try {
        if (_isTenantView) {
          avatarUrl = supabase.storage.from('avatars').getPublicUrl('$viewingUserId.jpg');
        } else {
          final meta = authUser?.userMetadata ?? {};
          avatarUrl = meta['avatar_url'] as String?;
        }
      } catch (e) {
        debugPrint('avatar resolve error: $e');
      }

      // ---------- landlord_profile ----------
      try {
        final landlordProfile = await supabase
            .from('landlord_profile')
            .select(
              'first_name, last_name, birthday, gender, address, apartment_name, apartment_name_2, contact_number, is_approved',
            )
            .eq('user_id', viewingUserId)
            .maybeSingle();

        landlordProfileRow = landlordProfile;

        if (landlordProfile != null) {
          firstName = landlordProfile['first_name'] as String?;
          lastName = landlordProfile['last_name'] as String?;
          birthday = landlordProfile['birthday'] as String?;
          gender = landlordProfile['gender'] as String?;
          address = landlordProfile['address'] as String?;
          legacyApt1 = landlordProfile['apartment_name'] as String?;
          legacyApt2 = landlordProfile['apartment_name_2'] as String?;
          phoneNumber = landlordProfile['contact_number'] as String?;
        }
      } catch (e) {
        debugPrint('landlord_profile fetch error: $e');
      }

      // ---------- users table fallbacks ----------
      try {
        final usersRow = await supabase
            .from('users')
            .select(
              'first_name, last_name, full_name, email, address, phone, apartment_name, apartment_name_2',
            )
            .eq('id', viewingUserId)
            .maybeSingle();

        if (usersRow != null) {
          email = usersRow['email'] as String? ?? email;

          firstName ??= usersRow['first_name'] as String?;
          lastName ??= usersRow['last_name'] as String?;

          if ((firstName == null || firstName.trim().isEmpty) &&
              (lastName == null || lastName.trim().isEmpty)) {
            final fullName = usersRow['full_name'] as String?;
            if (fullName != null && fullName.trim().isNotEmpty) {
              final parts = fullName.trim().split(' ');
              firstName = parts.first;
              if (parts.length > 1) lastName = parts.sublist(1).join(' ');
            }
          }

          if (address == null || address.trim().isEmpty) {
            final a = usersRow['address'] as String?;
            if (a != null && a.trim().isNotEmpty) address = a;
          }

          if (phoneNumber == null || phoneNumber.trim().isEmpty) {
            final p = usersRow['phone'] as String?;
            if (p != null && p.trim().isNotEmpty) phoneNumber = p;
          }

          // legacy fallbacks if landlord_profile missing
          legacyApt1 ??= usersRow['apartment_name'] as String?;
          legacyApt2 ??= usersRow['apartment_name_2'] as String?;
        }
      } catch (e) {
        debugPrint('users fetch error: $e');
      }

      // ---------- auth metadata fallback for self view ----------
      try {
        if (!_isTenantView &&
            (firstName == null || firstName.trim().isEmpty) &&
            (lastName == null || lastName.trim().isEmpty)) {
          final meta = authUser?.userMetadata ?? {};
          final metaFullName = meta['full_name'] as String?;
          if (metaFullName != null && metaFullName.trim().isNotEmpty) {
            final parts = metaFullName.trim().split(' ');
            firstName = parts.first;
            if (parts.length > 1) lastName = parts.sublist(1).join(' ');
          }
        }
      } catch (_) {}

      if (!_isTenantView) {
        email ??= authUser?.email;
      }

      // ---------- ✅ LOAD BRANCHES FROM landlord_branches ----------
      final branches = <Map<String, String>>[];
      try {
        final rows = await supabase
            .from('landlord_branches')
            .select('branch_name, branch_location, created_at')
            .eq('landlord_id', viewingUserId)
            .order('created_at', ascending: true) as List;

        for (final r in rows) {
          final name = (r['branch_name'] ?? '').toString().trim();
          final loc = (r['branch_location'] ?? '').toString().trim();
          if (name.isEmpty && loc.isEmpty) continue;
          if (name.isEmpty) continue;
          branches.add({'name': name, 'location': loc});
        }
      } catch (e) {
        debugPrint('landlord_branches fetch error: $e');
      }

      // ---------- fallback to legacy if no branches ----------
      if (branches.isEmpty) {
        final a1 = (legacyApt1 ?? '').trim();
        final a2 = (legacyApt2 ?? '').trim();
        final addr = (address ?? '').trim();

        if (a1.isNotEmpty) branches.add({'name': a1, 'location': addr});
        if (a2.isNotEmpty && a2 != a1) branches.add({'name': a2, 'location': addr});
      }

      // ---------- documents ----------
      bool hasBarangay = false;
      bool hasBusiness = false;

      try {
        _barangayUrl = null;
        _businessPermitUrl = null;
        _validId1Url = null;
        _validId2Url = null;

        final docs = await supabase
            .from('landlord_documents')
            .select('doc_type, storage_path')
            .eq('user_id', viewingUserId);

        for (final row in docs as List<dynamic>) {
          final docType = row['doc_type'] as String?;
          final path = row['storage_path'] as String?;
          if (docType == null || path == null) continue;

          final url = supabase.storage.from('landlord-docs').getPublicUrl(path);

          switch (docType) {
            case 'barangay_clearance':
              _barangayUrl = url;
              hasBarangay = true;
              break;
            case 'business_permit':
              _businessPermitUrl = url;
              hasBusiness = true;
              break;
            case 'valid_id':
              if (!_isTenantView) _validId1Url = url;
              break;
            case 'valid_id_2':
              if (!_isTenantView) _validId2Url = url;
              break;
          }
        }
      } catch (e) {
        debugPrint('landlord_documents fetch error: $e');
      }

      // ---------- status ----------
      bool isApproved = false;
      bool isRejected = false;
      bool isPending = false;

      final dynamic rawIsApproved = landlordProfileRow?['is_approved'];

      String? normalizedStatus;
      if (rawIsApproved is bool) {
        normalizedStatus = rawIsApproved ? 'approved' : 'rejected';
      } else if (rawIsApproved is num) {
        normalizedStatus = rawIsApproved == 1 ? 'approved' : 'rejected';
      } else if (rawIsApproved is String) {
        normalizedStatus = rawIsApproved.toLowerCase().trim();
      }

      if (normalizedStatus == 'approved' || normalizedStatus == 'true') {
        isApproved = true;
      } else if (normalizedStatus == 'rejected' || normalizedStatus == 'false') {
        isRejected = true;
      } else if (normalizedStatus == 'pending') {
        isPending = true;
      }

      try {
        final decision = await supabase
            .from('notifications')
            .select('type, created_at')
            .eq('user_id', viewingUserId)
            .inFilter('type', [
              'landlord_approved',
              'landlord_rejected',
              'landlord_reapplied',
            ])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (decision != null) {
          final type = decision['type'] as String?;
          if (type == 'landlord_approved') {
            isApproved = true;
            isRejected = false;
            isPending = false;
          } else if (type == 'landlord_rejected') {
            isRejected = true;
            if (!(normalizedStatus == 'approved' || normalizedStatus == 'true')) {
              isApproved = false;
            }
            isPending = false;
          } else if (type == 'landlord_reapplied') {
            isPending = true;
          }
        }
      } catch (e) {
        debugPrint('landlord decision fetch error: $e');
      }

      if (_isTenantView && !isApproved && !isRejected && !isPending) {
        if (hasBarangay && hasBusiness) isApproved = true;
      }

      if (!mounted) return;
      setState(() {
        _firstName = firstName;
        _lastName = lastName;
        _email = email;

        _birthday = birthday;
        _gender = gender;

        _address = address;
        _phoneNumber = phoneNumber;

        _branches = branches;

        _avatarUrl = (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null;

        _isLandlordApproved = isApproved;
        _isLandlordRejected = isRejected;
        _isPendingReview = isPending;
        _loadingProfile = false;
      });

      // keep edit controllers synced after load
      _resetBranchControllersFromBranches();
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _loadingProfile = false);
    }
  }

  String get _displayName {
    final f = (_firstName ?? '').trim();
    final l = (_lastName ?? '').trim();
    if (f.isNotEmpty && l.isNotEmpty) return '$f $l';
    if (f.isNotEmpty) return f;
    if (_isTenantView) return 'Landlord';
    return 'Your Name';
  }

  String get _displayEmail {
    if (_email != null && _email!.isNotEmpty) return _email!;
    return 'Not available';
  }

  // ✅ Save ALL branches to landlord_branches (and keep legacy fields synced)
  Future<void> _saveBranches() async {
    if (_isTenantView) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final newBranches = _collectBranchesFromControllers();
    if (newBranches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 1 apartment branch name.')),
      );
      return;
    }

    setState(() => _savingProfile = true);
    try {
      // Replace all branches
      await supabase.from('landlord_branches').delete().eq('landlord_id', user.id);

      await supabase.from('landlord_branches').insert(
            newBranches.map((b) {
              return {
                'landlord_id': user.id,
                'branch_name': b['name'],
                'branch_location': b['location'] ?? '',
              };
            }).toList(),
          );

      // Backward compatibility: update first 2 to landlord_profile + users
      final apt1 = newBranches.isNotEmpty ? newBranches[0]['name']! : '';
      final apt2 = newBranches.length > 1 ? newBranches[1]['name'] : null;

      await supabase.from('landlord_profile').upsert({
        'user_id': user.id,
        'apartment_name': apt1,
        'apartment_name_2': apt2,
      });

      try {
        await supabase.from('users').update({
          'apartment_name': apt1,
          'apartment_name_2': apt2,
        }).eq('id', user.id);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _branches = newBranches;
        _isEditing = false;
        _savingProfile = false;
      });

      _resetBranchControllersFromBranches();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Apartment branches updated')),
      );
    } catch (e) {
      debugPrint('save branches error: $e');
      if (!mounted) return;
      setState(() => _savingProfile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update branches: $e')),
      );
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_isTenantView) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final picker = ImagePicker();

    try {
      final XFile? picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 80,
      );
      if (picked == null) return;

      setState(() => _uploadingAvatar = true);

      final bytes = await picked.readAsBytes();

      const ext = 'jpg';
      const contentType = 'image/jpeg';
      final path = '${user.id}.$ext';

      await supabase.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);

      await supabase.auth.updateUser(
        UserAttributes(data: {'avatar_url': publicUrl}),
      );

      if (!mounted) return;
      setState(() {
        _avatarUrl = publicUrl;
        _uploadingAvatar = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated')),
      );
    } catch (e) {
      debugPrint('avatar upload error: $e');
      if (!mounted) return;
      setState(() => _uploadingAvatar = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload profile picture: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0B3A5D);
    const backgroundColor = Color(0xFFF2F4F7);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isTenantView ? 'LANDLORD PROFILE' : 'PROFILE',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
      ),
      body: _loadingProfile
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(primaryColor),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildAllInfoCard(context),
                  ),
                ],
              ),
            ),
    );
  }

  // ----------------------------- HEADER -----------------------------
  Widget _buildHeader(Color primaryColor) {
    final ImageProvider? avatarImage =
        (_avatarUrl != null && _avatarUrl!.startsWith('http'))
            ? NetworkImage(_avatarUrl!)
            : null;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B3A5D), Color(0xFF1D628F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.white,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? const Icon(Icons.person, size: 40, color: Color(0xFF0B3A5D))
                      : null,
                ),
                if (!_isTenantView)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: InkWell(
                      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: _uploadingAvatar ? Colors.grey : const Color(0xFF0B3A5D),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _uploadingAvatar ? Icons.hourglass_top : Icons.camera_alt,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_isLandlordApproved) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withOpacity(0.8), width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _displayEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_isLandlordApproved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFFECFEFF)),
                              SizedBox(width: 4),
                              Text(
                                'Approved Landlord',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_isPendingReview) ...[
                        if (_isLandlordApproved || _isLandlordRejected) const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.hourglass_empty, size: 16, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Pending Review',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (!_isTenantView && _isLandlordRejected) ...[
                        OutlinedButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterL(isReapply: true)),
                            );
                            if (result == true) await _loadProfile();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text(
                            'Reapply',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                     
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

  // ----------------------- INFO CARD -----------------------
  Widget _buildAllInfoCard(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: screenHeight * 0.55),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 0.7),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title: 'Personal Details', icon: Icons.person_outline),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildFieldTile(label: 'Birthday', value: _birthday ?? 'Not set')),
              const SizedBox(width: 12),
              Expanded(child: _buildFieldTile(label: 'Gender', value: _gender ?? 'Not set')),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(thickness: 0.8, color: Color(0xFFE0E4EA)),
          const SizedBox(height: 16),

          _buildSectionHeader(title: 'Contact & Address', icon: Icons.location_on_outlined),
          const SizedBox(height: 8),
          _buildFieldTile(label: 'Home / Contact Address', value: _address ?? 'Not set', maxLines: 3),
          const SizedBox(height: 12),
          _buildFieldTile(label: 'Phone Number', value: _phoneNumber ?? 'Not set'),

          const SizedBox(height: 16),
          const Divider(thickness: 0.8, color: Color(0xFFE0E4EA)),
          const SizedBox(height: 16),

          // ✅ MULTI-BRANCH DISPLAY (unlimited)
          _buildSectionHeader(title: 'Apartment Branches', icon: Icons.apartment_outlined),
          const SizedBox(height: 10),

          if (_isTenantView || !_isEditing) ...[
            _buildBranchesReadOnly(),
          ] else ...[
            _buildBranchesEditor(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _savingProfile ? null : _saveBranches,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF005B96),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _savingProfile
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  _savingProfile ? 'Saving...' : 'Save Branches',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(thickness: 0.8, color: Color(0xFFE0E4EA)),
          const SizedBox(height: 16),

          _buildSectionHeader(title: 'Documents', icon: Icons.folder_open_outlined),
          const SizedBox(height: 8),
          _buildDocumentTile(
            label: 'Barangay Clearance',
            fileName: _barangayUrl != null ? 'BarangayClearance.png' : 'Not uploaded',
            url: _barangayUrl,
          ),
          const SizedBox(height: 12),
          _buildDocumentTile(
            label: 'Business Permit',
            fileName: _businessPermitUrl != null ? 'BusinessPermit.png' : 'Not uploaded',
            url: _businessPermitUrl,
          ),
          if (!_isTenantView) ...[
            const SizedBox(height: 12),
            _buildDocumentTile(
              label: 'Valid ID',
              fileName: _validId1Url != null ? 'ValidID.png' : 'Not uploaded',
              url: _validId1Url,
              showPrivateNote: true,
            ),
            const SizedBox(height: 12),
            _buildDocumentTile(
              label: 'Valid ID 2',
              fileName: _validId2Url != null ? 'ValidID2.png' : 'Not uploaded',
              url: _validId2Url,
              showPrivateNote: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBranchesReadOnly() {
    if (_branches.isEmpty) {
      return _buildFieldTile(label: 'Branches', value: 'Not set', maxLines: 2);
    }

    return Column(
      children: [
        for (int i = 0; i < _branches.length; i++) ...[
          _buildBranchCard(
            index: i,
            name: _branches[i]['name'] ?? '',
            location: _branches[i]['location'] ?? '',
            showDelete: false,
          ),
          if (i != _branches.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildBranchesEditor() {
    return Column(
      children: [
        for (int i = 0; i < _branchNameCtrls.length; i++) ...[
          _buildBranchEditorRow(i),
          const SizedBox(height: 10),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _addBranchRow,
            icon: const Icon(Icons.add),
            label: const Text('Add another branch'),
          ),
        ),
      ],
    );
  }

  Widget _buildBranchCard({
    required int index,
    required String name,
    required String location,
    required bool showDelete,
  }) {
    final branchLabel = (index == 0) ? 'Default Branch' : 'Branch ${index + 1}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.apartment_outlined, color: Color(0xFF005B96)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? branchLabel : name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFF152332),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  location.isEmpty ? 'No location set' : location,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchEditorRow(int index) {
    final branchLabel = (index == 0) ? 'Default Branch' : 'Branch ${index + 1}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                branchLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7A8896),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Delete',
                onPressed: _savingProfile ? null : () => _removeBranchRow(index),
                icon: const Icon(Icons.delete_outline, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _branchNameCtrls[index],
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Apartment name (e.g., Sunrise Residences)',
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _branchLocCtrls[index],
            maxLines: 2,
            decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white,
              hintText: 'Branch location (e.g., Near UM, Davao City)',
              border: OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF005B96).withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF005B96)),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Color(0xFF061727),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldTile({
    required String label,
    required String value,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7A8896),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            maxLines: maxLines,
            overflow: maxLines == 1 ? TextOverflow.ellipsis : TextOverflow.visible,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF152332),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocumentTile({
    required String label,
    required String fileName,
    required String? url,
    bool showPrivateNote = false,
  }) {
    final hasFile = url != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7A8896),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD4D9DE), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: hasFile
              ? InkWell(
                  onTap: () => _showDocumentPreviewDialog(url!),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 20, color: Color(0xFF005B96)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          fileName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF005B96),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.open_in_new, size: 18, color: Color(0xFF7A8896)),
                    ],
                  ),
                )
              : Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFFB0BAC4),
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
        if (showPrivateNote)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              "🔒 Only viewable by landlord",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Color(0xFF9AA5B1),
              ),
            ),
          ),
      ],
    );
  }

  void _showDocumentPreviewDialog(String previewUrl) {
    final size = MediaQuery.of(context).size;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: size.height * 0.9,
            maxWidth: size.width * 0.95,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: InteractiveViewer(
                    child: Image.network(
                      previewUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('Cannot preview file'),
                      ),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF005B96),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}