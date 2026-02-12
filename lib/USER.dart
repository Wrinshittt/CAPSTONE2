// USER.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_finder/LANDLORD/REGISTER.dart';
import 'package:smart_finder/TENANT/TREGISTER.dart';

// Use your real login screens here:
import 'package:smart_finder/TENANT/TLOGIN.dart'; // class LoginT
import 'package:smart_finder/LANDLORD/login.dart'; // class Login (landlord)

class User extends StatefulWidget {
  const User({super.key});

  @override
  State<User> createState() => _LandlordState();
}

class _LandlordState extends State<User> {
  bool _isHoveringTenant = false;
  bool _isHoveringLandlord = false;
  String? selectedRole; // 'tenant' or 'landlord'

  // Track if registration has already been done (per role)
  bool _hasRegisteredTenant = false;
  bool _hasRegisteredLandlord = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  // Load previous role + registration status from SharedPreferences
  Future<void> _loadSavedState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      selectedRole = prefs.getString('selected_role');
      _hasRegisteredTenant = prefs.getBool('has_registered_tenant') ?? false;
      _hasRegisteredLandlord = prefs.getBool('has_registered_landlord') ?? false;
    });
  }

  Future<void> _persistRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_role', role);
  }

  Future<void> _setTenantRegisteredOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_registered_tenant', true);
    setState(() {
      _hasRegisteredTenant = true;
    });
  }

  Future<void> _setLandlordRegisteredOnce() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_registered_landlord', true);
    setState(() {
      _hasRegisteredLandlord = true;
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color.fromARGB(255, 113, 113, 113),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Called when the user has confirmed a role (pressed "Yes" in dialog).
  /// Handles the registration-once / then-login logic.
  Future<void> _onRoleConfirmed(String role) async {
    setState(() {
      selectedRole = role;
    });

    // Save chosen role
    await _persistRole(role);
    if (!mounted) return;

    if (role == 'tenant') {
      if (!_hasRegisteredTenant) {
        // First time Tenant → go to registration
        await _setTenantRegisteredOnce();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RegisterT()),
        );
      } else {
        // Next times Tenant → go to login
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const LoginT()),
        );
      }
    } else if (role == 'landlord') {
      if (!_hasRegisteredLandlord) {
        // First time Landlord → go to registration
        await _setLandlordRegisteredOnce();
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const RegisterL()),
        );
      } else {
        // Next times Landlord → go to login
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const Login()),
        );
      }
    }
  }

  // Popup confirmation dialog when choosing role
  Future<void> _showConfirmationDialog(String role) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Must choose Yes/No
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            "Confirm Selection",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[900],
            ),
          ),
          content: Text(
            "Are you sure you want to continue as a ${role == 'tenant' ? 'Tenant' : 'Landlord'}?",
            style: const TextStyle(fontSize: 15),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(); // Close dialog
              },
              child: const Text(
                "No",
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                // Close dialog first
                Navigator.of(dialogContext).pop();
                // Then run the same logic that the old Confirm button used
                await _onRoleConfirmed(role);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF04395E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF04395E),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Column(
                          children: [
                            Image.asset('assets/images/SMARTFINDER3.png', height: 200),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.20),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'Smart Finder • Role Selection',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Welcome to Smart Finder!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'Your trusted partner in finding and managing apartment rentals — '
                                'helping students, professionals, and property owners connect and '
                                'complete their rental journey with ease.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13.5,
                                  height: 1.4,
                                ),
                              ),
                              SizedBox(height: 22),
                              Text(
                                'Please choose how you want to use the app:',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // =============== Tenant Card ===============
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) =>
                              setState(() => _isHoveringTenant = true),
                          onExit: (_) =>
                              setState(() => _isHoveringTenant = false),
                          child: GestureDetector(
                            onTap: () => _showConfirmationDialog('tenant'),
                            child: _RoleCard(
                              isSelected: selectedRole == 'tenant',
                              isHovering: _isHoveringTenant,
                              title: 'I am a Tenant',
                              subtitle:
                                  'Browse listings, view photo tours, and contact landlords directly.',
                              assetPath: 'assets/images/TENANT.png',
                              accentColor: const Color(0xFF2563EB),
                              badgeText: 'Tenant',
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // =============== Landlord Card ===============
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) =>
                              setState(() => _isHoveringLandlord = true),
                          onExit: (_) =>
                              setState(() => _isHoveringLandlord = false),
                          child: GestureDetector(
                            onTap: () => _showConfirmationDialog('landlord'),
                            child: _RoleCard(
                              isSelected: selectedRole == 'landlord',
                              isHovering: _isHoveringLandlord,
                              title: 'I am a Landlord',
                              subtitle:
                                  'Post rooms, manage listings, and connect with responsible tenants.',
                              assetPath: 'assets/images/LANDLORD.png',
                              accentColor: const Color(0xFFF59E0B),
                              badgeText: 'Landlord',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Reusable role card widget to keep the UI consistent and cleaner.
/// Hover/selected state uses a smooth AnimatedScale + AnimatedContainer combo.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.isSelected,
    required this.isHovering,
    required this.title,
    required this.subtitle,
    required this.assetPath,
    required this.accentColor,
    required this.badgeText,
  });

  final bool isSelected;
  final bool isHovering;
  final String title;
  final String subtitle;
  final String assetPath;
  final Color accentColor;
  final String badgeText;

  @override
  Widget build(BuildContext context) {
    final bool active = isSelected || isHovering;
    final double targetScale = active ? 1.03 : 1.0;

    return AnimatedScale(
      scale: targetScale,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE3F0FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? accentColor : Colors.transparent,
            width: active ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: active
                  ? accentColor.withOpacity(0.35)
                  : Colors.black12,
              blurRadius: active ? 12 : 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Role image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(6),
                child: Image.asset(
                  assetPath,
                  height: 62,
                  width: 62,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Texts and badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + badge
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: accentColor.withOpacity(0.7),
                            width: 0.7,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              badgeText == 'Tenant'
                                  ? Icons.person_outline
                                  : Icons.home_work_outlined,
                              size: 14,
                              color: accentColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
