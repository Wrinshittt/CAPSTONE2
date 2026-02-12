// lib/LANDLORD/totalroom.dart
import 'package:flutter/material.dart';
import 'package:smart_finder/LANDLORD/CHAT2.dart';
import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/APARTMENT.dart';
import 'package:smart_finder/LANDLORD/LSETTINGS.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/LANDLORD/TIMELINE.dart';
import 'package:smart_finder/LANDLORD/TENANTS.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// services
import '../services/room_service.dart';

// imports for both room states
import 'package:smart_finder/LANDLORD/roomavail.dart' as avail;
import 'package:smart_finder/LANDLORD/roomnotavail.dart' as notavail;

// shared landlord bottom navigation
import 'landlord_bottom_nav.dart';

class TotalRoom extends StatefulWidget {
  const TotalRoom({super.key});

  @override
  State<TotalRoom> createState() => _TotalRoomState();
}

class _TotalRoomState extends State<TotalRoom> {
  final RoomService _service = RoomService();
  late final Stream<List<Map<String, dynamic>>> _roomsStream;

  // ✅ live apartment name from landlord_profile
  late final Stream<String> _aptNameStream;

  // ✅ branches stream from landlord_branches (dropdown options)
  late final Stream<List<Map<String, dynamic>>> _branchesStream;

  // ✅ selection
  static const String _all = '__ALL__';
  String _selectedBranch = _all;

  // ✅ NEW: what the big title shows (changes when user selects)
  String? _titleOverride;
  bool _userPickedTitle = false;

  int _selectedIndex = 5; // Rooms tab

  // (kept from your code)
  final ScrollController _bottomNavController = ScrollController();
  static double _savedBottomNavOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _roomsStream = _service.streamMyRooms();

    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;

    if (uid == null) {
      _aptNameStream = Stream<String>.value('');
      _branchesStream = Stream<List<Map<String, dynamic>>>.value(const []);
    } else {
      _aptNameStream = sb
          .from('landlord_profile')
          .stream(primaryKey: ['user_id'])
          .eq('user_id', uid)
          .map((rows) {
        if (rows.isEmpty) return '';
        final v = rows.first['apartment_name'];
        return (v ?? '').toString().trim();
      });

      // ✅ Pull ALL branches for this landlord
      _branchesStream = sb
          .from('landlord_branches')
          .stream(primaryKey: const ['landlord_id', 'branch_name'])
          .eq('landlord_id', uid)
          .order('created_at', ascending: true);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bottomNavController.hasClients) {
        final maxExtent = _bottomNavController.position.maxScrollExtent;
        final targetOffset = _savedBottomNavOffset.clamp(
          0.0,
          maxExtent.clamp(0.0, double.infinity),
        );
        _bottomNavController.jumpTo(targetOffset);
      }
    });
  }

  @override
  void dispose() {
    if (_bottomNavController.hasClients) {
      _savedBottomNavOffset = _bottomNavController.offset;
    }
    _bottomNavController.dispose();

    _service.dispose();
    super.dispose();
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
      MaterialPageRoute(builder: (_) => const Login()),
      (r) => false,
    );
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);

    Widget? destination;
    switch (index) {
      case 0:
        destination = const Dashboard();
        break;
      case 1:
        destination = const Timeline();
        break;
      case 2:
        destination = const Apartment();
        break;
      case 3:
        destination = const Tenants();
        break;
      case 4:
        destination = const ListChat();
        break;
      case 6:
        destination = const LandlordSettings();
        break;
      case 7:
        _showLogoutConfirmation();
        return;
    }

    if (destination != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination!),
      );
    }
  }

  // ---------- UTILITIES ----------
  String _availability(Map<String, dynamic> r) {
    final a = (r['availability_status'] ?? '').toString().toLowerCase();
    if (a == 'available' || a == 'not_available') return a;
    final s = (r['status'] ?? '').toString().toLowerCase();
    return s == 'available' ? 'available' : 'not_available';
  }

  void _openRoom(Map<String, dynamic> r) {
    final bool isAvail = _availability(r) == 'available';
    final Map<String, dynamic> room = Map<String, dynamic>.from(r);

    final Widget page = isAvail
        ? avail.RoomAvailable(roomData: room)
        : notavail.RoomNotAvailable(roomData: room);

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  // ✅ robust getter for the room's "apartment/branch" name
  String _getRoomBranch(Map<String, dynamic> room) {
    dynamic v = room['apartment_name'];
    v ??= room['branch_name'];
    v ??= room['apartmentName'];
    v ??= room['apartment'];
    v ??= room['apartment_title'];
    v ??= room['name'];
    return (v ?? '').toString().trim();
  }

  // ✅ fallback title from rooms if landlord_profile is empty
  String _getApartmentNameFromRooms(List<Map<String, dynamic>> rooms) {
    if (rooms.isEmpty) return '';
    final first = rooms.first;

    dynamic v = first['apartment_name'];
    v ??= first['apartmentName'];
    v ??= first['apartment'];
    v ??= first['apartment_title'];
    v ??= first['name'];

    final s = (v ?? '').toString().trim();
    if (s.isNotEmpty) return s;

    for (final r in rooms) {
      final ss = _getRoomBranch(r);
      if (ss.isNotEmpty) return ss;
    }
    return '';
  }

  // ✅ filter rooms by selected branch
  List<Map<String, dynamic>> _filterRooms(
    List<Map<String, dynamic>> rooms,
    String selectedBranch,
  ) {
    if (selectedBranch == _all) return rooms;
    return rooms.where((r) => _getRoomBranch(r) == selectedBranch).toList();
  }

  // ✅ branches list from landlord_branches + include default apt name
  List<String> _buildBranchNames({
    required List<Map<String, dynamic>> branchRows,
    required String liveAptName,
  }) {
    final set = <String>{};

    for (final row in branchRows) {
      final b = (row['branch_name'] ?? '').toString().trim();
      if (b.isNotEmpty) set.add(b);
    }

    final defaultApt = liveAptName.trim();
    if (defaultApt.isNotEmpty) set.add(defaultApt);

    final list = set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  // ✅ NEW: icon-only picker
  Future<void> _openBranchPicker({
    required List<String> branches,
  }) async {
    if (branches.isEmpty) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select Apartment / Branch',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                  itemCount: branches.length + 1,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: Colors.black.withOpacity(0.06),
                  ),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      final selected = _selectedBranch == _all;
                      return ListTile(
                        title: const Text(
                          'All Rooms',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check_circle, color: Color(0xFF16A34A))
                            : const Icon(Icons.circle_outlined, color: Colors.black38),
                        onTap: () => Navigator.pop(ctx, _all),
                      );
                    }

                    final name = branches[i - 1];
                    final selected = _selectedBranch == name;

                    return ListTile(
                      title: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Color(0xFF16A34A))
                          : const Icon(Icons.circle_outlined, color: Colors.black38),
                      onTap: () => Navigator.pop(ctx, name),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || picked == null) return;

    setState(() {
      _selectedBranch = picked;
      _userPickedTitle = true;

      // ✅ requirement: if user selects "All", title becomes "All Rooms"
      if (picked == _all) {
        _titleOverride = 'All Rooms';
      } else {
        _titleOverride = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF0B3A5D);
    const Color backgroundColor = Color(0xFFF2F4F7);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'MY ROOMS',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF04354B),
        onRefresh: () async {
          if (!mounted) return;
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 250));
        },
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: _roomsStream,
          initialData: const [],
          builder: (context, roomSnap) {
            final rooms = roomSnap.data ?? const [];

            Widget topInfoBar = Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.04),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withOpacity(0.05),
                    width: 0.6,
                  ),
                ),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.door_front_door_outlined,
                    size: 20,
                    color: primaryColor,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Tap a room card to view full details.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF4B5563),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );

            // ERROR
            if (roomSnap.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  topInfoBar,
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          'Could not load rooms:\n${roomSnap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Color(0xFF374151)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            // LOADING
            if (roomSnap.connectionState == ConnectionState.waiting && rooms.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  topInfoBar,
                  const SizedBox(
                    height: 360,
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),
                  ),
                ],
              );
            }

            // EMPTY
            if (rooms.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  topInfoBar,
                  const SizedBox(height: 40),
                  const _EmptyListState(),
                ],
              );
            }

            final fallbackAptName = _getApartmentNameFromRooms(rooms);

            return StreamBuilder<String>(
              stream: _aptNameStream,
              initialData: '',
              builder: (context, aptSnap) {
                final liveApt = (aptSnap.data ?? '').trim();
                final baseTitle = liveApt.isNotEmpty
                    ? liveApt
                    : (fallbackAptName.isNotEmpty ? fallbackAptName : 'No apartment name set');

                // ✅ If user picked already:
                // - if _all: show "All Rooms"
                // - else: show chosen branch
                // ✅ If not picked yet: show baseTitle
                final displayTitle = _userPickedTitle
                    ? (_selectedBranch == _all ? 'All Rooms' : (_titleOverride ?? baseTitle))
                    : baseTitle;

                return StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _branchesStream,
                  initialData: const [],
                  builder: (context, branchSnap) {
                    final branchRows = branchSnap.data ?? const [];
                    final branches = _buildBranchNames(
                      branchRows: branchRows,
                      liveAptName: liveApt.isNotEmpty ? liveApt : fallbackAptName,
                    );

                    // If selected branch disappears, reset to ALL and title to All Rooms
                    if (_selectedBranch != _all &&
                        branches.isNotEmpty &&
                        !branches.contains(_selectedBranch)) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _selectedBranch = _all;
                          _userPickedTitle = true;
                          _titleOverride = 'All Rooms';
                        });
                      });
                    }

                    final filteredRooms = _filterRooms(rooms, _selectedBranch);

                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: filteredRooms.length + 2,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (context, i) {
                        if (i == 0) return topInfoBar;

                        // Title + icon only
                        if (i == 1) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 2),
                            child: Row(
                              children: [
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    displayTitle,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: branches.isEmpty ? null : () => _openBranchPicker(branches: branches),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 28,
                                      color: branches.isEmpty ? Colors.black26 : const Color(0xFF111827),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                            ),
                          );
                        }

                        final r = filteredRooms[i - 2];
                        final title = (r['room_name'] ?? 'Room').toString();
                        final location = (r['location'] ?? '').toString();
                        final monthly = r['monthly_payment'];
                        final isAvail = _availability(r) == 'available';

                        return _RoomCard(
                          title: title,
                          location: location,
                          monthly: monthly,
                          isAvailable: isAvail,
                          onTap: () => _openRoom(r),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: const LandlordBottomNav(currentIndex: 5),
    );
  }
}

// ---------- ROOM CARD ----------
class _RoomCard extends StatelessWidget {
  final String title;
  final String location;
  final dynamic monthly;
  final bool isAvailable;
  final VoidCallback onTap;

  const _RoomCard({
    required this.title,
    required this.location,
    required this.monthly,
    required this.isAvailable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF0B3A5D);

    final String statusText = isAvailable ? 'Available' : 'Not Available';
    final Color statusBg = isAvailable ? const Color(0xFFD1FAE5) : const Color(0xFFE5E7EB);
    final Color statusTextColor =
        isAvailable ? const Color(0xFF047857) : const Color(0xFF4B5563);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          border: Border.all(
            color: Colors.black.withOpacity(0.05),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.meeting_room_outlined,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location.isNotEmpty ? location : 'No location set',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusTextColor.withOpacity(0.25),
                      ),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: statusTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 54),
                child: Row(
                  children: [
                    const Text(
                      '₱',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4B5563),
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      monthly != null ? '$monthly / month' : 'No price set',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'View complete room details, photos and tenant actions.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: primaryColor, width: 1),
                      ),
                    ),
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward_ios, size: 14, color: primaryColor),
                    label: const Text(
                      'More Info',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- EMPTY STATE ----------
class _EmptyListState extends StatelessWidget {
  const _EmptyListState();

  @override
  Widget build(BuildContext context) {
    const Color primaryColor = Color(0xFF0B3A5D);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.meeting_room_outlined, size: 40, color: primaryColor),
              SizedBox(height: 12),
              Text(
                'No rooms yet',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Create a room in AddRoom to see it listed here.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
