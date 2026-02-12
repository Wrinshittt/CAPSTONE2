import 'package:flutter/material.dart';
import 'package:smart_finder/LANDLORD/WALKIN_TPROFILE.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ Ensure we import the right class that accepts `tenantData`
import 'tenantinfo.dart' show Tenantinfo;

import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/APARTMENT.dart';
import 'package:smart_finder/LANDLORD/TOTALROOM.dart';
import 'package:smart_finder/LANDLORD/LSETTINGS.dart';
import 'package:smart_finder/LANDLORD/CHAT2.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/LANDLORD/TIMELINE.dart';

// ✅ App-tenant profile screen
import 'package:smart_finder/TENANT/TPROFILE.dart';

// ✅ Walk-in tenant profile screen (CODE 2)
// 🔧 Change this import path to wherever you saved CODE 2:

// ⬇️ Shared landlord bottom navigation bar
import 'landlord_bottom_nav.dart';

class Tenants extends StatefulWidget {
  const Tenants({super.key});

  @override
  State<Tenants> createState() => _TenantsState();
}

class _TenantsState extends State<Tenants> {
  final _sb = Supabase.instance.client;

  String searchQuery = '';
  int? hoveredIndex;
  int _selectedIndex = 3; // Tenants tab selected

  // ✅ re-assignable for pull-to-refresh
  late Stream<List<Map<String, dynamic>>> _tenantStream;

  @override
  void initState() {
    super.initState();
    _selectedIndex = 3;
    _tenantStream = _streamTenantsSafe();
  }

  /// Stream all, then filter by landlord_id + status in Dart.
  Stream<List<Map<String, dynamic>>> _streamTenantsSafe() {
    final me = _sb.auth.currentUser?.id;
    if (me == null) return const Stream.empty();

    return _sb.from('room_tenants').stream(primaryKey: ['id']).map((rows) {
      final list = List<Map<String, dynamic>>.from(rows);
      return list.where((t) {
        final status = (t['status'] ?? '').toString().toLowerCase().trim();
        final ll = (t['landlord_id'] ?? '').toString().trim();
        return status == 'active' && ll == me;
      }).toList();
    });
  }

  Future<void> _showLogoutConfirmation() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Log out'),
            content: const Text('Are you sure you want to log out of Smart Finder?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Log out', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) return;
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const Login()),
      (route) => false,
    );
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;

    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Dashboard()));
    } else if (index == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Timeline()));
    } else if (index == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Apartment()));
    } else if (index == 3) {
      // stay
    } else if (index == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ListChat()));
    } else if (index == 5) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TotalRoom()));
    } else if (index == 6) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LandlordSettings()));
    } else if (index == 7) {
      _showLogoutConfirmation();
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF0A3D62);
    const Color backgroundColor = Color(0xFFF3F4F6);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        automaticallyImplyLeading: false,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'TENANTS',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
            color: Colors.white,
          ),
        ),
      ),

      body: RefreshIndicator(
        color: const Color(0xFF04354B),
        onRefresh: () async {
          setState(() => _tenantStream = _streamTenantsSafe());
        },
        child: Column(
          children: [
            // Top card + search
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Color.fromARGB(25, 0, 0, 0),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: const [
                      Icon(Icons.info_outline, size: 18, color: Color(0xFF9CA3AF)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'View and manage all active tenants under your properties.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.withOpacity(0.35), width: 0.9),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (value) => setState(() => searchQuery = value),
                      cursorColor: primaryColor,
                      decoration: InputDecoration(
                        hintText: "Search tenant by name or email",
                        hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: primaryColor),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _tenantStream,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(
                            height: 360,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.8,
                                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    if (snap.hasError) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Error loading tenants:\n${snap.error}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    final rows = snap.data ?? const [];
                    final filtered = rows.where((t) {
                      final s = searchQuery.toLowerCase();
                      final name = (t['full_name'] ?? '').toString().toLowerCase();
                      final email = (t['email'] ?? '').toString().toLowerCase();
                      return name.contains(s) || email.contains(s);
                    }).toList();

                    if (filtered.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 40),
                          Center(
                            child: Text(
                              'No tenants found.',
                              style: TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final t = filtered[index];

                        final name = (t['full_name'] ?? 'Unknown').toString();
                        final email = (t['email'] ?? '—').toString();

                        // ✅ APP tenant identifier
                        final String tenantUserId = (t['tenant_user_id'] ?? '').toString().trim();

                        // ✅ Needed for WALK-IN profile
                        final String roomId = (t['room_id'] ?? '').toString().trim();

                        return MouseRegion(
                          onEnter: (_) => setState(() => hoveredIndex = index),
                          onExit: (_) => setState(() => hoveredIndex = null),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeInOut,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: hoveredIndex == index
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 12,
                                        offset: const Offset(0, 5),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Card(
                              color: hoveredIndex == index ? const Color(0xFFEFF6FF) : Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: hoveredIndex == index
                                      ? primaryColor.withOpacity(0.25)
                                      : Colors.black.withOpacity(0.05),
                                  width: 0.9,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                onTap: () async {
                                  // ✅ App tenant → go to app tenant profile
                                  if (tenantUserId.isNotEmpty) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TenantProfile(userId: tenantUserId),
                                      ),
                                    );
                                    return;
                                  }

                                  // ✅ Walk-in tenant → go to CODE 2
                                  if (roomId.isNotEmpty) {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => WalkInTenantProfile(roomId: roomId),
                                      ),
                                    );
                                    return;
                                  }

                                  // fallback
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => Tenantinfo(tenantData: Map<String, dynamic>.from(t)),
                                    ),
                                  );
                                },
                                leading: CircleAvatar(
                                  radius: 24,
                                  backgroundColor: primaryColor.withOpacity(0.08),
                                  child: Text(
                                    _initials(name),
                                    style: const TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15.5,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    email,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Text(
                                        'Active',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: primaryColor,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.open_in_new, size: 18, color: primaryColor),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: const LandlordBottomNav(currentIndex: 3),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
