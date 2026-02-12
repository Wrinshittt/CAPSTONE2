// TENANT/TPROFILE.dart
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'TAPARTMENT.dart';
import 'TCHAT2.dart';
import 'TSETTINGS.dart';
import 'TLOGIN.dart';
import 'TMYROOM.dart';
import 'TPROFILEEDIT.dart';

class TenantProfile extends StatefulWidget {
  const TenantProfile({super.key, this.userId}); // ✅ accepts userId

  // ✅ If null => show current logged-in user (original behavior)
  final String? userId;

  @override
  State<TenantProfile> createState() => _TenantProfileState();
}

class _TenantProfileState extends State<TenantProfile> {
  final _sb = Supabase.instance.client;
  int _selectedNavIndex = 2;

  Map<String, dynamic>? _userRow; // public.users

  // ✅ Persisted avatar (via auth metadata) + cache buster
  String? _avatarUrlBase;
  int _avatarVersion = 0;

  bool _loading = true;
  String? _error;

  bool _uploadingAvatar = false;

  // ✅ Housing details
  Map<String, dynamic>? _room; // rooms row (assigned active room)
  bool _loadingRoom = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String? _withCacheBuster(String? url) {
    if (url == null || url.isEmpty) return null;
    final sep = url.contains('?') ? '&' : '?';
    return '$url${sep}v=$_avatarVersion';
  }

  String _money(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '—';
    return '₱${n.toStringAsFixed(2)}';
  }

  bool get _viewingSelf {
    final currentUser = _sb.auth.currentUser;
    final uid = (widget.userId != null && widget.userId!.trim().isNotEmpty)
        ? widget.userId!.trim()
        : currentUser?.id;
    return (currentUser?.id != null && uid != null && currentUser!.id == uid);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final currentUser = _sb.auth.currentUser;

      // ✅ show specific tenant if provided, else show current logged-in
      final String? uid =
          (widget.userId != null && widget.userId!.trim().isNotEmpty)
              ? widget.userId!.trim()
              : currentUser?.id;

      if (uid == null) {
        setState(() {
          _loading = false;
          _error = 'Not logged in.';
        });
        return;
      }

      final row = await _sb
          .from('users')
          .select('id, full_name, email, phone, address, first_name, last_name')
          .eq('id', uid)
          .maybeSingle();

      // ✅ If viewing self, can use auth metadata.
      // If viewing another tenant, DO NOT use currentUser metadata.
      String? avatarUrl;
      final bool viewingSelf =
          (currentUser?.id != null && currentUser!.id == uid);

      if (viewingSelf) {
        avatarUrl = (currentUser.userMetadata?['avatar_url'] as String?)?.trim();
      }

      avatarUrl ??= _sb.storage.from('avatars').getPublicUrl('$uid.jpg');

      if (!mounted) return;
      setState(() {
        _userRow = row ?? {};
        _avatarUrlBase =
            (avatarUrl != null && avatarUrl.isNotEmpty) ? avatarUrl : null;
        _loading = false;
      });

      // ✅ Load assigned room details
      await _loadRoomForTenant(uid);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load profile: $e';
        _loading = false;
      });
    }
  }

  // ✅ Load active room mapping for this tenant + room fields
  Future<void> _loadRoomForTenant(String uid) async {
    if (!mounted) return;
    setState(() => _loadingRoom = true);

    try {
      // room_tenants mapping
      final mapping = await _sb
          .from('room_tenants')
          .select('room_id')
          .eq('tenant_user_id', uid)
          .eq('status', 'active')
          .maybeSingle();

      if (mapping == null || mapping['room_id'] == null) {
        if (!mounted) return;
        setState(() {
          _room = null;
          _loadingRoom = false;
        });
        return;
      }

      final roomId = mapping['room_id'].toString();

      // rooms details needed in profile card
      final room = await _sb
          .from('rooms')
          .select('monthly_payment, advance_deposit, room_name, floor_number')
          .eq('id', roomId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _room = room as Map<String, dynamic>?;
        _loadingRoom = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _room = null;
        _loadingRoom = false;
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    // ✅ EXTRA SAFETY: only allow when viewing self
    if (!_viewingSelf) return;

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

      const contentType = 'image/jpeg';
      final path = '${user.id}.jpg';

      await _sb.storage.from('avatars').uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      final publicUrl = _sb.storage.from('avatars').getPublicUrl(path);

      await _sb.auth.updateUser(
        UserAttributes(data: {'avatar_url': publicUrl}),
      );

      if (!mounted) return;

      setState(() {
        _avatarUrlBase = publicUrl;
        _avatarVersion++;
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

  Future<void> _openEdit() async {
    if (_userRow == null) return;

    // ✅ only allow when viewing self
    if (!_viewingSelf) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't edit another user's profile.")),
      );
      return;
    }

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TenantEditProfile(
          name: (_userRow!['full_name'] ??
                  '${_userRow!['first_name'] ?? ''} ${_userRow!['last_name'] ?? ''}')
              .toString()
              .trim(),
          email: (_userRow!['email'] ?? '').toString(),
          phone: (_userRow!['phone'] ?? '').toString(),
          address: (_userRow!['address'] ?? '').toString(),
          currentAvatarUrl: _withCacheBuster(_avatarUrlBase),
        ),
      ),
    );

    if (saved == true && mounted) {
      _avatarVersion++;
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0B3A5D);
    const backgroundColor = Color(0xFFF1F5F9);

    final row = _userRow ?? {};
    final displayName =
        (row['full_name'] ?? '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}')
            .toString()
            .trim();
    final email = (row['email'] ?? '').toString();

    final avatarUrl = _withCacheBuster(_avatarUrlBase);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Tenant Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            )
          : (_error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(
                        primaryColor: primaryColor,
                        displayName: displayName,
                        email: email,
                        avatarUrl: avatarUrl,
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildAllInfoCard(
                          context,
                          displayName: displayName,
                          row: row,
                        ),
                      ),
                    ],
                  ),
                )),
    );
  }

  // ----------------------------- HEADER -----------------------------
  Widget _buildHeader({
    required Color primaryColor,
    required String displayName,
    required String email,
    required String? avatarUrl,
  }) {
    final ImageProvider? avatarImage =
        (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B3A5D), Color(0xFF1D628F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white,
                      child: ClipOval(
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: avatarImage != null
                              ? Image(
                                  image: avatarImage,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.person,
                                    size: 42,
                                    color: Colors.grey,
                                  ),
                                )
                              : const Icon(
                                  Icons.person,
                                  size: 42,
                                  color: Color(0xFF0B3A5D),
                                ),
                        ),
                      ),
                    ),

                    // ✅ IMPORTANT CHANGE:
                    // Show the camera button ONLY when viewing self (tenant).
                    if (_viewingSelf)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: InkWell(
                          onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _uploadingAvatar ? Colors.grey : Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              _uploadingAvatar ? Icons.hourglass_top : Icons.camera_alt,
                              size: 16,
                              color: _uploadingAvatar ? Colors.white : primaryColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty ? 'Your name' : displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        email.isEmpty ? '—' : email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _statusChip(
                            icon: Icons.person_outline,
                            label: 'Tenant',
                            color: Colors.cyan,
                          ),
                          const SizedBox(width: 8),
                          const Spacer(),

                          // ✅ Edit button also only when viewing self
                          if (_viewingSelf)
                            ElevatedButton.icon(
                              onPressed: _openEdit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: primaryColor,
                                elevation: 2,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text(
                                'Edit',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllInfoCard(
    BuildContext context, {
    required String displayName,
    required Map<String, dynamic> row,
  }) {
    final screenHeight = MediaQuery.of(context).size.height;

    final monthlyRent = _room != null ? _money(_room!['monthly_payment']) : '—';
    final advanceDeposit = _room != null ? _money(_room!['advance_deposit']) : '—';
    final roomName = _room != null ? (_room!['room_name'] ?? '—').toString() : '—';
    final floorNo = _room != null
        ? (_room!['floor_number'] != null ? 'Floor ${_room!['floor_number']}' : 'Not set')
        : '—';

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: screenHeight * 0.55),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.7),
          width: 0.7,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            title: 'Personal Details',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFieldTile(
                  label: 'Full Name',
                  value: displayName.isEmpty ? 'Not set' : displayName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldTile(
                  label: 'Phone',
                  value: (row['phone'] ?? 'Not set').toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildFieldTile(
            label: 'Email',
            value: (row['email'] ?? '').toString().isEmpty ? 'Not set' : (row['email'] ?? '').toString(),
          ),
          const SizedBox(height: 18),
          const Divider(thickness: 0.8, color: Color(0xFFE0E4EA)),
          const SizedBox(height: 14),
          _buildSectionHeader(
            title: 'Contact & Address',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: 12),
          _buildFieldTile(
            label: 'Address',
            value: (row['address'] ?? 'Not set').toString(),
            maxLines: 3,
          ),
          const SizedBox(height: 18),
          const Divider(thickness: 0.8, color: Color(0xFFE0E4EA)),
          const SizedBox(height: 14),
          _buildSectionHeader(
            title: 'Housing Details',
            icon: Icons.home_outlined,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildFieldTile(
                  label: 'Advance / Deposit',
                  value: _loadingRoom ? 'Loading…' : advanceDeposit,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldTile(
                  label: 'Monthly Rent',
                  value: _loadingRoom ? 'Loading…' : monthlyRent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildFieldTile(
                  label: 'Room Name',
                  value: _loadingRoom ? 'Loading…' : roomName,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFieldTile(
                  label: 'Floor No.',
                  value: _loadingRoom ? 'Loading…' : floorNo,
                ),
              ),
            ],
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
            color: const Color(0xFF005B96).withOpacity(0.1),
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
            fontSize: 11.5,
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
            value.isEmpty ? 'Not set' : value,
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

  BottomNavigationBarItem _nav(IconData icon, String label, int index) {
    final selected = _selectedNavIndex == index;
    return BottomNavigationBarItem(
      icon: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 3,
            width: selected ? 20 : 0,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: selected ? Colors.black : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Icon(icon),
        ],
      ),
      label: label,
    );
  }
}
