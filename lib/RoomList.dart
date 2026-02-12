// RoomsList.dart
import 'package:flutter/material.dart';
import 'package:smart_finder/LANDLORD/APARTMENT.dart';
import 'package:smart_finder/LANDLORD/GMAP.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/LANDLORD/TOUR.dart' show LTour;

/// ✅ SnackBar replacement: auto-dismiss info toast modal
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
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

class RoomsList extends StatefulWidget {
  /// ✅ Tenant flow: pass landlordId to show that landlord’s rooms
  /// ✅ Landlord flow: leave null to show logged-in landlord’s rooms
  final String? landlordId;

  /// Optional title override for AppBar
  final String? titleHint;

  const RoomsList({
    super.key,
    this.landlordId,
    this.titleHint,
  });

  @override
  State<RoomsList> createState() => _RoomsListState();
}

class _RoomsListState extends State<RoomsList> {
  final _sb = Supabase.instance.client;

  RealtimeChannel? _roomsChannel;

  List<_RoomItem> _rooms = [];
  bool _loading = true;
  String? _error;

  int currentPage = 0;
  final int cardsPerPage = 10;
  final ScrollController _scrollController = ScrollController();

  final Map<String, bool> _favorite = {};
  final Map<String, bool> _bookmark = {};
  final Map<String, int> _heartCounts = {};

  @override
  void initState() {
    super.initState();
    _fetchRooms();
    _subscribeRooms();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _roomsChannel?.unsubscribe();
    super.dispose();
  }

  // ---------- Helpers ----------
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  bool _isApprovedRow(Map<String, dynamic> raw) {
    final s = (raw['status'] ?? '').toString().toLowerCase().trim();
    return s == 'published' || s == 'approved';
  }

  bool _isVacantRow(Map<String, dynamic> raw) {
    final av = (raw['availability_status'] ?? '').toString().toLowerCase().trim();
    final st = (raw['status'] ?? '').toString().toLowerCase().trim();

    final looksAvailable =
        av == 'available' ||
        av == 'vacant' ||
        av == 'open' ||
        av == 'empty' ||
        st == 'available';

    final allowEmptyAvailability = av.isEmpty;

    return looksAvailable || allowEmptyAvailability;
  }

  String? _imageUrlFromRow(Map<String, dynamic> row) {
    final imgs = (row['room_images'] as List?) ?? [];
    if (imgs.isEmpty) return null;

    imgs.sort((a, b) =>
        ((a['sort_order'] ?? 0) as int).compareTo((b['sort_order'] ?? 0) as int));

    final first = imgs.first as Map?;
    if (first == null) return null;

    final direct = (first['image_url'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final sp = (first['storage_path'] as String?)?.trim();
    if (sp != null && sp.isNotEmpty) {
      return _sb.storage.from('room-images').getPublicUrl(sp);
    }
    return null;
  }

  // ---------- Fetch Rooms ----------
  Future<void> _fetchRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ Determine which landlord we are showing
      String? targetLandlordId = widget.landlordId?.trim();

      if (targetLandlordId == null || targetLandlordId.isEmpty) {
        // landlord flow fallback
        final user = _sb.auth.currentUser;
        if (user == null) {
          setState(() {
            _loading = false;
            _error = 'You must be logged in to view rooms.';
          });
          return;
        }
        targetLandlordId = user.id;
      }

      // ✅ fetch rooms for the chosen landlordId
      final List<dynamic> data = await _sb
          .from('rooms')
          .select('''
            id,
            landlord_id,
            apartment_name,
            location,
            monthly_payment,
            created_at,
            status,
            availability_status,
            room_images:room_images!fk_room_images_room ( image_url, storage_path, sort_order )
          ''')
          .eq('landlord_id', targetLandlordId)
          .order('created_at', ascending: false)
          .order('sort_order', referencedTable: 'room_images', ascending: true);

      final rooms = <_RoomItem>[];

      for (final raw in data) {
        final row = (raw as Map).cast<String, dynamic>();
        if (!_isApprovedRow(row) || !_isVacantRow(row)) continue;

        rooms.add(
          _RoomItem(
            id: row['id'].toString(),
            title: (row['apartment_name'] ?? 'Apartment').toString(),
            address: (row['location'] ?? '—').toString(),
            monthly: _toDouble(row['monthly_payment']),
            imageUrl: _imageUrlFromRow(row),
          ),
        );
      }

      setState(() {
        _rooms = rooms;
        _loading = false;
        _error = rooms.isEmpty ? 'No approved vacant rooms found.' : null;
        currentPage = 0;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load rooms: $e';
      });
    }
  }

  // ---------- Realtime ----------
  void _subscribeRooms() {
    _roomsChannel?.unsubscribe();

    _roomsChannel = _sb.channel('roomslist-rooms')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rooms',
        callback: (_) => _fetchRooms(),
      )
      ..subscribe();
  }

  // ---------- Navigation ----------
  void openRoomInfo(_RoomItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LTour(
          initialIndex: 0,
          roomId: item.id,
          titleHint: item.title,
          addressHint: item.address,
        ),
      ),
    );
  }

  void openMap(_RoomItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Gmap(roomId: item.id),
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final appBarTitle = (widget.titleHint ?? '').trim().isNotEmpty
        ? widget.titleHint!.trim()
        : (_rooms.isNotEmpty ? _rooms.first.title : 'Rooms');

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          appBarTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontSize: 20,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRooms,
        color: const Color(0xFF04354B),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF04354B)),
              )
            : (_error != null
                ? Center(child: Text(_error!))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _rooms.length,
                    itemBuilder: (context, index) {
                      final item = _rooms[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: LandlordApartmentCard(
                          title: item.title,
                          address: item.address,
                          priceText: '₱ ${item.monthly.toStringAsFixed(0)} / Month',
                          imageUrl: item.imageUrl,
                          isFavorited: false,
                          isBookmarked: false,
                          onFavoriteToggle: () {},
                          onBookmarkPressed: () {},
                          onOpen: () => openRoomInfo(item),
                          onMapTap: () => openMap(item),
                          showRanking: false,
                          hashtags: const [],
                          heartCount: item.heartCount,
                        ),
                      );
                    },
                  )),
      ),
    );
  }
}

/* --------------------------- MODEL --------------------------- */

class _RoomItem {
  final String id;
  final String title;
  final String address;
  final double monthly;
  final String? imageUrl;
  int heartCount = 0;

  _RoomItem({
    required this.id,
    required this.title,
    required this.address,
    required this.monthly,
    required this.imageUrl,
  });
}
