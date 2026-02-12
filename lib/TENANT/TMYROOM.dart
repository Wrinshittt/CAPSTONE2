// lib/TENANT/TMYROOM.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'TAPARTMENT.dart';
import 'TCHAT2.dart';
import 'TSETTINGS.dart';
import 'TLOGIN.dart';
import 'package:smart_finder/TENANT/TBOTTOMNAV.dart';

class MyRoom extends StatefulWidget {
  const MyRoom({super.key});

  @override
  State<MyRoom> createState() => _MyRoomState();
}

class _MyRoomState extends State<MyRoom> {
  final SupabaseClient _sb = Supabase.instance.client;

  static const Color _primaryColor = Color(0xFF003049);
  static const Color _backgroundColor = Color(0xFFE6E6E6);

  // Bottom nav & carousel
  int _selectedIndex = TenantNavIndex.myRoom;
  int _currentPage = 0;
  final PageController _pageController = PageController();
  Timer? _timer;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _room;

  // Real tenant name
  String? _tenantName;

  // ✅ NEW: Like CODE 2
  List<String> _inclusions = [];
  List<String> _preferences = [];

  // Default / fallback images
  final List<String> _fallbackImages = const [
    "assets/images/roompano.png",
    "assets/images/roompano2.png",
    "assets/images/roompano3.png",
  ];

  List<String> _imageUrls = [];

  @override
  void initState() {
    super.initState();
    _imageUrls = List<String>.from(_fallbackImages);
    _startAutoScroll();
    _loadRoom();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _money(dynamic v) {
    if (v == null) return '₱—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '₱—';
    return '₱${n.toStringAsFixed(2)}';
  }

  // ✅ NEW: same as CODE 2
  String _moneyWithSuffix(dynamic v, String suffix) {
    if (v == null) return '₱—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '₱—';
    return '₱${n.toStringAsFixed(2)} $suffix';
  }

  // ---------------------------------------------------------------------------
  // AUTO CAROUSEL
  // ---------------------------------------------------------------------------

  void _startAutoScroll() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (Timer timer) {
      if (_pageController.hasClients && _imageUrls.isNotEmpty) {
        final int nextPage = (_currentPage + 1) % _imageUrls.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // LOAD ROOM FROM SUPABASE
  // ---------------------------------------------------------------------------

  Future<void> _loadRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String? me = _sb.auth.currentUser?.id;
      if (me == null) {
        setState(() {
          _loading = false;
          _error = 'You are not logged in.';
        });
        return;
      }

      // Get real tenant name from tenant_profile
      String? tenantName;
      try {
        final profile = await _sb
            .from('tenant_profile')
            .select('full_name')
            .eq('user_id', me)
            .maybeSingle();

        final full = (profile?['full_name'] ?? '').toString().trim();
        if (full.isNotEmpty) {
          tenantName = full;
        }
      } catch (_) {
        // ignore
      }

      // 1) Find active mapping in room_tenants
      final mapping = await _sb
          .from('room_tenants')
          .select('room_id')
          .eq('tenant_user_id', me)
          .eq('status', 'active')
          .maybeSingle();

      if (mapping == null || mapping['room_id'] == null) {
        // No active room assigned yet
        setState(() {
          _room = null;
          _imageUrls = List<String>.from(_fallbackImages);
          _tenantName = tenantName;
          _inclusions = [];
          _preferences = [];
          _loading = false;
        });
        return;
      }

      final String roomId = mapping['room_id'].toString();

      // 2) Load room details
      final room = await _sb.from('rooms').select().eq('id', roomId).maybeSingle();

      // 3) Load images
      final imgs = await _sb
          .from('room_images')
          .select('image_url, storage_path, sort_order')
          .eq('room_id', roomId)
          .order('sort_order', ascending: true);

      final urls = <String>[];
      for (final row in (imgs as List? ?? const [])) {
        final String? direct = row['image_url'] as String?;
        final String? storagePath = row['storage_path'] as String?;
        if (direct != null && direct.trim().isNotEmpty) {
          urls.add(direct);
        } else if (storagePath != null && storagePath.trim().isNotEmpty) {
          final pub = _sb.storage.from('room-images').getPublicUrl(storagePath);
          urls.add(pub);
        }
      }

      // ✅ NEW: Load inclusions like CODE 2
      List<String> inclusions = [];
      try {
        final incRows = await _sb
            .from('room_inclusions')
            .select('inclusion_options(name)')
            .eq('room_id', roomId);

        inclusions = (incRows as List? ?? const [])
            .map<String>((e) => (e['inclusion_options']?['name'] as String?) ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } catch (_) {
        inclusions = [];
      }

      // ✅ NEW: Load preferences like CODE 2
      List<String> preferences = [];
      try {
        final prefRows = await _sb
            .from('room_preferences')
            .select('preference_options(name)')
            .eq('room_id', roomId);

        preferences = (prefRows as List? ?? const [])
            .map<String>((e) => (e['preference_options']?['name'] as String?) ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } catch (_) {
        preferences = [];
      }

      setState(() {
        _room = room as Map<String, dynamic>?;
        _imageUrls = urls.isEmpty ? List<String>.from(_fallbackImages) : urls;
        _tenantName = tenantName;
        _inclusions = inclusions;
        _preferences = preferences;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load room: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION (shared bottom nav)
  // ---------------------------------------------------------------------------

  void _onBottomNavSelected(int index) {
    if (index == _selectedIndex) return;

    setState(() {
      _selectedIndex = index;
    });

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
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantSettings()),
      );
    } else if (index == TenantNavIndex.myRoom) {
      // already here
    } else if (index == TenantNavIndex.logout) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginT()),
        (route) => false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
        bottomNavigationBar: TenantBottomNav(
          currentIndex: _selectedIndex,
          onItemSelected: _onBottomNavSelected,
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        bottomNavigationBar: TenantBottomNav(
          currentIndex: _selectedIndex,
          onItemSelected: _onBottomNavSelected,
        ),
      );
    }

    // No assigned room
    if (_room == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: _buildAppBar(),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _imageCarousel(context),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Room Assigned Yet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "You don’t have a room assigned to your account yet. "
                      "Once your landlord assigns you to a room, it will appear here.",
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: TenantBottomNav(
          currentIndex: _selectedIndex,
          onItemSelected: _onBottomNavSelected,
        ),
      );
    }

    final room = _room!;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadRoom,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _imageCarousel(context),
              const SizedBox(height: 20),
              _infoBoxes(room),
              const SizedBox(height: 20),
              _roomDetailsBox(room),
            ],
          ),
        ),
      ),
      bottomNavigationBar: TenantBottomNav(
        currentIndex: _selectedIndex,
        onItemSelected: _onBottomNavSelected,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // APP BAR
  // ---------------------------------------------------------------------------

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _primaryColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: const Text(
        'MY ROOM',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 25,
        ),
      ),
      centerTitle: true,
    );
  }

  // ---------------------------------------------------------------------------
  // CAROUSEL
  // ---------------------------------------------------------------------------

  Widget _imageCarousel(BuildContext context) {
    if (_imageUrls.isEmpty) {
      _imageUrls = List<String>.from(_fallbackImages);
    }

    return Column(
      children: [
        SizedBox(
          height: 300,
          width: double.infinity,
          child: GestureDetector(
            onPanDown: (_) => _timer?.cancel(),
            onPanEnd: (_) => _startAutoScroll(),
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemCount: _imageUrls.length,
              itemBuilder: (context, index) {
                final String url = _imageUrls[index];
                final bool isAsset = url.startsWith('assets/');

                return ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: isAsset
                      ? Image.asset(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade300,
                            alignment: Alignment.center,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_imageUrls.length, (index) {
            final bool isActive = _currentPage == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 10,
              width: isActive ? 24 : 10,
              decoration: BoxDecoration(
                color: isActive ? _primaryColor : Colors.grey,
                borderRadius: BorderRadius.circular(12),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ROOM OVERVIEW
  // ---------------------------------------------------------------------------

  Widget _infoBoxes(Map<String, dynamic> room) {
    final String apartmentName = (room['apartment_name'] ?? '—').toString();
    final String location = (room['location'] ?? '—').toString();
    final String monthly = _money(room['monthly_payment']);
    final String advance = _money(room['advance_deposit']);

    // ✅ NEW: like CODE 2
    final String waterPerHead = _moneyWithSuffix(room['water_per_head'], '/head');
    final String perWattPrice = _moneyWithSuffix(room['per_watt_price'], '/watts');

    final String roomName = (room['room_name'] ?? 'Room').toString();

    final String floor = room['floor_number'] != null
        ? 'Floor ${room['floor_number']}'
        : 'Not set';

    // ✅ UPDATED: use DB inclusions (like CODE 2). fallback to furnishing if empty.
    final String inclusions = _inclusions.isNotEmpty
        ? _inclusions.join(', ')
        : (room['furnishing'] ?? '—').toString();

    final String tenantName =
        (_tenantName == null || _tenantName!.trim().isEmpty) ? 'You' : _tenantName!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Room Overview',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: FontAwesomeIcons.building,
                title: 'Apartment',
                value: apartmentName,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.location_on_outlined,
                title: 'Location',
                value: location,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.price_change_outlined,
                title: 'Monthly Rent',
                value: monthly,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Advance / Deposit',
                value: advance,
              ),
            ),
          ],
        ),

        // ✅ NEW ROW (same as CODE 2)
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.water_drop_outlined,
                title: 'Water per head',
                value: waterPerHead,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.bolt_outlined,
                title: 'Per watts price',
                value: perWattPrice,
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.meeting_room_outlined,
                title: 'Room Name',
                value: roomName,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.chair_outlined,
                title: 'Inclusions',
                value: inclusions,
                maxLines: 3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.person_outline,
                title: 'Occupant',
                value: tenantName,
                maxLines: 2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.layers_outlined,
                title: 'Floor',
                value: floor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ROOM DETAILS
  // ---------------------------------------------------------------------------

  Widget _roomDetailsBox(Map<String, dynamic> room) {
    final String description = (room['description'] as String?) ??
        "Cozy room with single bed, table, chair, and Wi-Fi.";

    // ✅ UPDATED: build tags from preferences + inclusions like CODE 2
    final List<String> tags = [
      ..._preferences.map((e) => '#$e'),
      ..._inclusions.map((e) => '#$e'),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.description_outlined,
                size: 20,
                color: _primaryColor,
              ),
              SizedBox(width: 8),
              Text(
                'Room Details',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF4B5563),
              height: 1.4,
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: tags
                  .take(10)
                  .map(
                    (t) => Text(
                      t,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info card
// ---------------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
    this.maxLines = 2,
  });

  final IconData icon;
  final String title;
  final String value;
  final int maxLines;

  static const Color _primaryColor = Color(0xFF003049);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 95,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
