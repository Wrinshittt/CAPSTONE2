// lib/LANDLORD/LSETTINGS.dart
import 'package:flutter/material.dart';
import 'package:smart_finder/LANDLORD/EDITPROFILE.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/LANDLORD/CHAT2.dart';
import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/profile.dart' show Adminprofile;
import 'package:smart_finder/LANDLORD/RESETPASS.dart';
import 'package:smart_finder/LANDLORD/TIMELINE.dart';
import 'package:smart_finder/LANDLORD/APARTMENT.dart';
import 'package:smart_finder/LANDLORD/TENANTS.dart';
import 'package:smart_finder/LANDLORD/TOTALROOM.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/TENANT/TERMSCONDITION.dart';

// ⬇️ shared landlord bottom navigation
import 'package:smart_finder/LANDLORD/landlord_bottom_nav.dart';

class LandlordSettings extends StatefulWidget {
  const LandlordSettings({super.key});

  @override
  State<LandlordSettings> createState() => _LandlordSettingsState();
}

class _LandlordSettingsState extends State<LandlordSettings> {
  final _sb = Supabase.instance.client;

  int _selectedIndex = 6;

  bool _loading = true;
  String? _name;
  String? _email;
  String? _phone;
  String? _address;
  String? _avatarUrl; // now actually used in the header

  // Scroll controller for the old bottom navigation (kept but not used much)
  final ScrollController _navScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMe();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedNav();
    });
  }

  @override
  void dispose() {
    _navScrollController.dispose();
    super.dispose();
  }

  void _scrollToSelectedNav() {
    if (!_navScrollController.hasClients) return;

    const double itemWidth = 88.0;
    final double target = _selectedIndex * itemWidth;
    final double max = _navScrollController.position.maxScrollExtent;

    double offset = target;
    if (offset < 0) offset = 0;
    if (offset > max) offset = max;

    _navScrollController.jumpTo(offset);
  }

  String _capitalizeWord(String input) {
    if (input.isEmpty) return input;
    final lower = input.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String _toTitleCase(String input) {
    if (input.trim().isEmpty) return input;
    return input
        .split(RegExp(r'\s+'))
        .map(_capitalizeWord)
        .join(' ')
        .trim();
  }

  Future<void> _loadMe() async {
    setState(() => _loading = true);
    try {
      final authUser = _sb.auth.currentUser;

      if (authUser == null) {
        setState(() {
          _name = 'Your name';
          _email = '';
          _phone = '';
          _address = '';
          _avatarUrl = null;
          _loading = false;
        });
        return;
      }

      final uid = authUser.id;
      final authEmail = authUser.email ?? '';
      final metaFullName =
          (authUser.userMetadata?['full_name'] ?? '').toString().trim();
      final metaAvatar =
          (authUser.userMetadata?['avatar_url'] ?? '').toString().trim();

      // landlord_profile row (source of truth)
      Map<String, dynamic>? landlordRow;
      try {
        landlordRow = await _sb
            .from('landlord_profile')
            .select(
              'first_name, last_name, address, contact_number',
            )
            .eq('user_id', uid)
            .maybeSingle();
      } catch (e) {
        debugPrint('Error fetching landlord_profile in _loadMe: $e');
      }

      final lpFirst = (landlordRow?['first_name'] ?? '').toString().trim();
      final lpLast = (landlordRow?['last_name'] ?? '').toString().trim();
      final lpAddress = (landlordRow?['address'] ?? '').toString().trim();
      final lpPhone =
          (landlordRow?['contact_number'] ?? '').toString().trim();

      // users row (email, fallback name/address/phone)
      Map<String, dynamic>? usersRow;
      try {
        usersRow = await _sb
            .from('users')
            .select(
              'full_name, first_name, last_name, email, phone, address',
            )
            .eq('id', uid)
            .maybeSingle();
      } catch (e) {
        debugPrint('Error fetching users in _loadMe: $e');
      }

      final rawFirstFromUsers =
          (usersRow?['first_name'] ?? '').toString().trim();
      final rawLastFromUsers =
          (usersRow?['last_name'] ?? '').toString().trim();
      final rawFullNameFromRow =
          (usersRow?['full_name'] ?? '').toString().trim();

      // Choose first/last name
      String firstName = lpFirst.isNotEmpty ? lpFirst : rawFirstFromUsers;
      String lastName = lpLast.isNotEmpty ? lpLast : rawLastFromUsers;

      if (firstName.isEmpty &&
          lastName.isEmpty &&
          rawFullNameFromRow.isNotEmpty) {
        final parts = rawFullNameFromRow.split(RegExp(r'\s+'));
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }

      if (firstName.isEmpty &&
          lastName.isEmpty &&
          metaFullName.isNotEmpty) {
        final parts = metaFullName.split(RegExp(r'\s+'));
        firstName = parts.first;
        if (parts.length > 1) {
          lastName = parts.sublist(1).join(' ');
        }
      }

      String displayName = '';
      if (firstName.isNotEmpty || lastName.isNotEmpty) {
        final capFirst = _capitalizeWord(firstName);
        final capLast = _capitalizeWord(lastName);
        displayName = '$capFirst $capLast'.trim();
      }
      if (displayName.isEmpty) {
        displayName = 'Your name';
      }

      String emailFromRow = (usersRow?['email'] ?? '').toString().trim();
      if (emailFromRow.isEmpty) {
        emailFromRow = authEmail;
      }

      String addressFromDb = lpAddress.isNotEmpty
          ? lpAddress
          : (usersRow?['address'] ?? '').toString().trim();

      String phoneFromDb = lpPhone.isNotEmpty
          ? lpPhone
          : (usersRow?['phone'] ?? '').toString().trim();

      String? avatar = metaAvatar.isNotEmpty ? metaAvatar : null;

      setState(() {
        _name = displayName;
        _email = emailFromRow;
        _phone = phoneFromDb;
        _address = addressFromDb;
        _avatarUrl = avatar;
        _loading = false;
      });
    } catch (e) {
      final authUser = _sb.auth.currentUser;
      final fallbackEmail = authUser?.email ?? '';
      final metaFullName =
          (authUser?.userMetadata?['full_name'] ?? '').toString().trim();
      final metaAvatar =
          (authUser?.userMetadata?['avatar_url'] ?? '').toString().trim();

      String displayName =
          metaFullName.isNotEmpty ? _toTitleCase(metaFullName) : 'Your name';

      debugPrint('Error in _loadMe (settings): $e');

      setState(() {
        _name = displayName;
        _email = fallbackEmail;
        _phone = '';
        _address = '';
        _avatarUrl = metaAvatar.isNotEmpty ? metaAvatar : null;
        _loading = false;
      });
    }
  }

  Future<void> _showLogoutConfirmation() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Log out'),
            content: const Text(
              'Are you sure you want to log out of Smart Finder?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Log out',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) {
      if (mounted) {
        setState(() {
          _selectedIndex = 6;
        });
      }
      return;
    }
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
      (route) => false,
    );
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Dashboard()),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Timeline()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Apartment()),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Tenants()),
      );
    } else if (index == 4) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ListChat()),
      );
    } else if (index == 5) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TotalRoom()),
      );
    } else if (index == 6) {
      // stay on settings
    } else if (index == 7) {
      _showLogoutConfirmation();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF0B3A5D);
    const Color backgroundColor = Color(0xFFF2F4F7);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text(
          'SETTINGS',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Colors.white,
            letterSpacing: 0.8,
          ),
        ),
        // ✅ removed refresh icon button
      ),
      body: Column(
        children: [
          // HEADER CARD
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
                          builder: (_) => const Adminprofile(
                            null, // ✅ pass null: show own landlord profile
                          ),
                        ),
                      );
                      _loadMe();
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
                          _loading ? 'Loading…' : (_name ?? 'Your name'),
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
                          _email?.isNotEmpty == true ? _email! : 'No email set',
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
                                    builder: (_) => const Adminprofile(
                                      null, // ✅ same here
                                    ),
                                  ),
                                );
                                _loadMe();
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

          // SETTINGS LIST
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                _sectionTitle('General'),
                const SizedBox(height: 8),
                _settingsTile(
                  icon: Icons.person_outline,
                  title: 'Account',
                  subtitle: 'Update your profile information',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LandlordEditProfile(
                          name: _name ?? '',
                          email: _email ?? '',
                          phone: _phone ?? '',
                          address: _address ?? '',
                          currentAvatarUrl: _avatarUrl,
                        ),
                      ),
                    ).then((saved) {
                      if (saved == true) _loadMe();
                    });
                  },
                ),
                const SizedBox(height: 12),

                _sectionTitle('Security'),
                const SizedBox(height: 8),
                _settingsTile(
                  icon: Icons.lock_outline,
                  title: 'Security',
                  subtitle: 'Change password and secure your account',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ResetPassword(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),

                _sectionTitle('Support & Info'),
                const SizedBox(height: 8),
                _settingsTile(
                  icon: Icons.phone_outlined,
                  title: 'Contact Us',
                  subtitle: 'Reach out for support or questions',
                  onTap: () {
                    // TODO: Add contact action
                  },
                ),
                const SizedBox(height: 12),
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

      // Shared landlord bottom navigation (Settings tab = index 7)
      bottomNavigationBar: const LandlordBottomNav(currentIndex: 7),
    );
  }

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
