// TENANT/TSETTINGS.dart

import 'package:flutter/material.dart';
import 'package:smart_finder/TENANT/TERMSCONDITION.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'TCHAT2.dart';
import 'TPROFILE.dart';
import 'TAPARTMENT.dart';
import 'TLOGIN.dart';
import 'TMYROOM.dart';
import 'TRESETPASS.dart';
import 'TPROFILEEDIT.dart'; // ✅ NEW: for TenantEditProfile
import 'package:smart_finder/TENANT/TBOTTOMNAV.dart';

class TenantSettings extends StatefulWidget {
  const TenantSettings({super.key});

  @override
  State<TenantSettings> createState() => _TenantSettingsState();
}

class _TenantSettingsState extends State<TenantSettings> {
  final _sb = Supabase.instance.client;

  bool _notificationEnabled = true;

  // use shared nav indices (Settings is index 2)
  int _selectedIndex = TenantNavIndex.settings;

  Map<String, dynamic>? _userRow;
  String? _avatarUrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSafely();
  }

  Future<void> _loadSafely() async {
    try {
      await _load().timeout(
        const Duration(seconds: 6),
      ); // prevent infinite loading
    } catch (e) {
      debugPrint("⚠ SETTINGS LOAD ERROR: $e");
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _load() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;

    try {
      // ✅ Match CODE 1: fetch the same name fields + do NOT rely on avatar_url column
      final row = await _sb
          .from('users')
          .select('id, full_name, email, phone, address, first_name, last_name')
          .eq('id', uid)
          .maybeSingle();

      debugPrint("Fetched tenant settings row: $row");

      // ✅ Match CODE 1: build avatar URL from storage (jpg then png)
      final storage = _sb.storage.from('avatars');
      final jpg = storage.getPublicUrl('$uid.jpg');
      final png = storage.getPublicUrl('$uid.png');
      final url = (jpg.isNotEmpty ? jpg : png);

      if (!mounted) return;

      setState(() {
        _userRow = row;
        _avatarUrl = url.isEmpty ? null : url;
      });
    } catch (e) {
      debugPrint("❌ Supabase error (TenantSettings): $e");
    }
  }

  // --------------------- SHARED BOTTOM NAV HANDLER ---------------------

  void _onBottomNavSelected(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    if (index == TenantNavIndex.apartment) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantApartment()),
      );
    } else if (index == TenantNavIndex.message) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantListChat()),
      );
    } else if (index == TenantNavIndex.settings) {
      // already here
    } else if (index == TenantNavIndex.myRoom) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyRoom()),
      );
    } else if (index == TenantNavIndex.logout) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginT()),
        (r) => false,
      );
    }
    // TenantNavIndex.bookmark can be wired to a Bookmark screen later
  }

  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF0B3A5D);
    const Color backgroundColor = Color(0xFFF2F4F7);

    final authUser = _sb.auth.currentUser;

    // ✅ Match CODE 1 display name logic (full_name fallback to first+last)
    final row = _userRow ?? {};
    final displayNameFromRow = (row['full_name'] ??
            '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}')
        .toString()
        .trim();

    final emailFromRow = (row['email'] ?? '').toString().trim();
    final email =
        emailFromRow.isNotEmpty ? emailFromRow : (authUser?.email ?? '');

    final displayName = (_isLoading || displayNameFromRow.isEmpty)
        ? 'Your name'
        : displayNameFromRow;

    // Also pull phone & address here for passing into TenantEditProfile
    final phone = (row['phone'] ?? '').toString();
    final address = (row['address'] ?? '').toString();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 22,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadSafely,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // HEADER CARD (similar to LandlordSettings)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0B3A5D), Color(0xFF1D628F)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(24),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TenantProfile(),
                        ),
                      );
                      _loadSafely();
                    },
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: Colors.white,
                      backgroundImage:
                          (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                              ? NetworkImage(_avatarUrl!)
                              : null,
                      child: (_avatarUrl == null || _avatarUrl!.isEmpty)
                          ? const Icon(
                              Icons.person,
                              size: 40,
                              color: Color(0xFF0B3A5D),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLoading ? 'Loading…' : displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email.isNotEmpty ? email : 'No email set',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const TenantProfile(),
                                  ),
                                );
                                _loadSafely();
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: primaryColor,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              icon: const Icon(Icons.person_outline, size: 18),
                              label: const Text(
                                'View Profile',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // SETTINGS LIST (sectioned like LSETTINGS.dart)
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.black54,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      _sectionTitle('General'),
                      const SizedBox(height: 8),

                      // ✅ Account card now opens TenantEditProfile (CODE 2)
                      _settingsTile(
                        icon: Icons.person_outline,
                        title: 'Account',
                        subtitle: 'View and edit your profile information',
                        onTap: () async {
                          final nameForEdit =
                              displayNameFromRow.isEmpty ? '' : displayNameFromRow;

                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TenantEditProfile(
                                name: nameForEdit,
                                email: email,
                                phone: phone,
                                address: address,
                                currentAvatarUrl: _avatarUrl,
                              ),
                            ),
                          );

                          // refresh header after editing
                          _loadSafely();
                        },
                      ),

                      const SizedBox(height: 12),
                      _settingsTile(
                        icon: Icons.notifications_outlined,
                        title: 'Notifications',
                        subtitle: 'Sound, snooze and notification preferences',
                        trailing: Switch(
                          value: _notificationEnabled,
                          onChanged: (v) {
                            setState(() => _notificationEnabled = v);
                            // TODO: handle real notification settings if needed
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Security'),
                      const SizedBox(height: 8),
                      _settingsTile(
                        icon: Icons.lock_outline,
                        title: 'Change Password',
                        subtitle: 'Update your account password',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TenantResetPassword(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      _sectionTitle('Support & Info'),
                      const SizedBox(height: 8),
                      _settingsTile(
                        icon: Icons.info_outline,
                        title: 'About',
                        subtitle: 'Terms and Conditions',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TermsAndCondition(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
          ),
        ],
      ),

      // ✅ use shared bottom navigation bar
      bottomNavigationBar: TenantBottomNav(
        currentIndex: _selectedIndex,
        onItemSelected: _onBottomNavSelected,
      ),
    );
  }

  // ---------- SHARED UI HELPERS (similar to LSETTINGS.dart) ----------

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF6B7280),
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: trailing == null ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE3EDF8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: const Color(0xFF1D4F7B),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFF9CA3AF),
              ),
          ],
        ),
      ),
    );
  }
}
