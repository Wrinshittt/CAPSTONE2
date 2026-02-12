import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../TOUR.dart';
import 'EditRoom.dart';

class RoomAvailable extends StatefulWidget {
  const RoomAvailable({super.key, required this.roomData});

  final Map<String, dynamic> roomData;

  @override
  State<RoomAvailable> createState() => _RoomAvailableState();
}

class _RoomAvailableState extends State<RoomAvailable> {
  final SupabaseClient _sb = Supabase.instance.client;

  static const Color _primaryColor = Color(0xFF003049);
  static const Color _backgroundColor = Color(0xFFF2F4F7);

  Map<String, dynamic>? _room;
  bool _loading = true;

  List<String> _imageUrls = const [];

  List<String> _inclusions = [];
  List<String> _preferences = [];

  RealtimeChannel? _roomChannel;
  RealtimeChannel? _imagesChannel;

  int _hoveredIndex = -1;
  int _selectedIndex = 0;

  // -------------------- SMALL HELPERS (UI only) --------------------
  String _readStr(dynamic v) => (v ?? '').toString().trim();

  /// ✅ Display title (Branch > Apartment name > fallback)
  String _displayApartmentTitle(Map<String, dynamic> room) {
    final branch = _readStr(room['branch_name']);
    if (branch.isNotEmpty) return branch;

    final apt = _readStr(room['apartment_name']);
    if (apt.isNotEmpty) return apt;

    // optional fallbacks if you have other columns
    final b2 = _readStr(room['building_name']);
    if (b2.isNotEmpty) return b2;

    return 'Room Info';
  }

  void _showToastModal(BuildContext context, String message) {
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
  }

  String? _resolveRoomId() {
    final dynamic raw = _room != null ? _room!['id'] : widget.roomData['id'];
    if (raw == null) return null;
    final id = raw.toString().trim();
    return id.isEmpty ? null : id;
  }

  @override
  void initState() {
    super.initState();
    _fetchAll();
    _listenRealtime();
  }

  @override
  void dispose() {
    _roomChannel?.unsubscribe();
    _imagesChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    try {
      final id = _resolveRoomId();
      if (id == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final Map<String, dynamic>? data =
          await _sb.from('rooms').select().eq('id', id).maybeSingle();

      final landlordId = _sb.auth.currentUser?.id;
      Map<String, dynamic>? landlordProfile;
      if (landlordId != null) {
        landlordProfile = await _sb
            .from('landlord_profile')
            .select('apartment_name')
            .eq('user_id', landlordId)
            .maybeSingle();
      }

      final imgs = await _sb
          .from('room_images')
          .select('image_url, storage_path, sort_order')
          .eq('room_id', id)
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

      final incRows = await _sb
          .from('room_inclusions')
          .select('inclusion_options(name)')
          .eq('room_id', id);

      final incNames = <String>{};
      for (final row in (incRows as List? ?? const [])) {
        final rel = row['inclusion_options'];
        if (rel is Map && rel['name'] != null) {
          final name = rel['name'].toString().trim();
          if (name.isNotEmpty) incNames.add(name);
        }
      }

      String fallbackInclusions = '';
      if (data != null && data['furnishing'] != null) {
        fallbackInclusions = data['furnishing'].toString().trim();
      } else if (widget.roomData['furnishing'] != null) {
        fallbackInclusions = widget.roomData['furnishing'].toString().trim();
      }

      List<String> inclusionsList = [];
      String inclusionsText;

      if (incNames.isNotEmpty) {
        inclusionsList = incNames.toList()..sort();
        inclusionsText = inclusionsList.join(', ');
      } else if (fallbackInclusions.isNotEmpty) {
        inclusionsText = fallbackInclusions;
      } else {
        inclusionsText = 'Single bed, table, chair, Wi-Fi';
      }

      List<String> prefList = [];
      try {
        final prefRows = await _sb
            .from('room_preferences')
            .select('preference_options(name)')
            .eq('room_id', id);

        final prefNames = <String>{};
        for (final row in (prefRows as List? ?? const [])) {
          final rel = row['preference_options'];
          if (rel is Map && rel['name'] != null) {
            final name = rel['name'].toString().trim();
            if (name.isNotEmpty) prefNames.add(name);
          }
        }

        prefList = prefNames.toList()..sort();
      } catch (_) {}

      if (!mounted) return;

      // -------------------- IMPORTANT FIX --------------------
      // Previously, landlord_profile.apartment_name always overwrote the room's own
      // apartment/branch name, causing "1st branch" to display even when you open "2nd branch".
      //
      // ✅ Fix: Only use landlord_profile.apartment_name as a fallback when the room itself
      // does NOT have a branch/apartment name.
      Map<String, dynamic> mergedRoom = data ?? widget.roomData;

      final String? profileApartmentName =
          (landlordProfile?['apartment_name'] as String?)?.trim();

      final roomBranchName = _readStr(mergedRoom['branch_name']);
      final roomApartmentName = _readStr(mergedRoom['apartment_name']);

      final bool roomHasSpecificName =
          roomBranchName.isNotEmpty || roomApartmentName.isNotEmpty;

      if (!roomHasSpecificName &&
          profileApartmentName != null &&
          profileApartmentName.isNotEmpty) {
        mergedRoom = {...mergedRoom, 'apartment_name': profileApartmentName};
      }

      mergedRoom = {
        ...mergedRoom,
        'inclusions': inclusionsText,
        'furnishing': inclusionsText,
      };

      setState(() {
        _room = mergedRoom;
        _imageUrls = urls.isNotEmpty
            ? urls
            : [
                'assets/images/roompano.png',
                'assets/images/roompano2.png',
                'assets/images/roompano3.png',
              ];
        _inclusions = inclusionsList;
        _preferences = prefList;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _listenRealtime() {
    final id = _resolveRoomId();
    if (id == null) return;

    _roomChannel?.unsubscribe();
    _roomChannel = _sb.channel('rooms_changes_$id')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: id,
        ),
        callback: (_) async => _fetchAll(),
      )
      ..subscribe();

    _imagesChannel?.unsubscribe();
    _imagesChannel = _sb.channel('room_images_changes_$id')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'room_images',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: id,
        ),
        callback: (_) async => _fetchAll(),
      )
      ..subscribe();
  }

  String _money(dynamic v) {
    if (v == null) return '₱—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '₱—';
    return '₱${n.toStringAsFixed(2)}';
  }

  String _suffixMoney(dynamic v, String suffix) {
    if (v == null) return '₱—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '₱—';
    return '₱${n.toStringAsFixed(2)} $suffix';
  }

  bool _isAvailable(Map<String, dynamic> room) {
    final availability =
        (room['availability_status'] ?? room['status'] ?? 'available')
            .toString()
            .toLowerCase();
    return availability == 'available';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
          ),
        ),
      );
    }

    final room = _room ?? widget.roomData;

    // ✅ AppBar now shows selected apartment name (Branch)
    final title = _displayApartmentTitle(room);

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF04354B),
        onRefresh: () async => _fetchAll(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeroCard(room),
              const SizedBox(height: 20),
              _buildOverviewGrid(room),
              const SizedBox(height: 20),
              _buildPhotosSection(room),
              const SizedBox(height: 20),
              _roomDetailsBox(
                description: (room['description'] as String?) ??
                    "Cozy room with single bed, table, chair, and Wi-Fi.",
                tags: [
                  ..._preferences.map((e) => '#$e'),
                  ..._inclusions.map((e) => '#$e'),
                ],
              ),
              const SizedBox(height: 20),
              _actionButtons(room),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------- HERO CARD --------------------
  Widget _buildHeroCard(Map<String, dynamic> room) {
    final String mainImageUrl = _imageUrls.isNotEmpty ? _imageUrls.first : '';
    final String location =
        (room['location'] ?? 'No location provided').toString();
    final String monthly = _money(room['monthly_payment']);
    final bool available = _isAvailable(room);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 190,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (mainImageUrl.isNotEmpty)
                _buildHeroImage(mainImageUrl)
              else
                Container(
                  color: const Color(0xFFE5E7EB),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.photo_outlined,
                    size: 42,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.05),
                        Colors.black.withOpacity(0.6),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          location,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          monthly,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: available
                        ? const Color(0xFF16A34A).withOpacity(0.95)
                        : const Color(0xFF6B7280).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        available
                            ? Icons.check_circle_outline
                            : Icons.lock_outline,
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        available ? 'Available' : 'Occupied',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroImage(String url) {
    final bool isAsset = url.startsWith('assets/');
    final Widget imageWidget = isAsset
        ? Image.asset(url, fit: BoxFit.cover)
        : Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => Container(
              color: const Color(0xFFE5E7EB),
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: Color(0xFF9CA3AF),
                size: 36,
              ),
            ),
          );
    return imageWidget;
  }

  // -------------------- OVERVIEW GRID --------------------
  Widget _buildOverviewGrid(Map<String, dynamic> room) {
    // ✅ Apartment card now uses Branch/selected apartment name
    final String apartmentName = _displayApartmentTitle(room);

    final String location = (room['location'] ?? '—').toString();
    final String monthly = _money(room['monthly_payment']);
    final String advance = _money(room['advance_deposit']);

    final String waterPerHead = _suffixMoney(room['water_per_head'], '/head');
    final String perWattPrice = _suffixMoney(room['per_watt_price'], '/watts');

    final String inclusions = _inclusions.isEmpty ? '—' : _inclusions.join(', ');

    final String tenantName =
        (room['tenant_name'] ?? 'No tenant assigned').toString();

    final String roomName = (room['room_name'] ?? 'Room').toString();

    final String floor = room['floor_number'] != null
        ? 'Floor ${room['floor_number']}'
        : 'Not set';

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
                icon: Icons.payments_outlined,
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.water_drop_outlined,
                title: 'Water / head',
                value: waterPerHead,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.bolt_outlined,
                title: 'Per watt price',
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
                title: 'Tenant',
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

  // -------------------- PHOTOS SECTION --------------------
  Widget _buildPhotosSection(Map<String, dynamic> room) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Photos',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 10),
        _imageRow(room),
      ],
    );
  }

  Widget _imageRow(Map<String, dynamic> room) {
    if (_imageUrls.isEmpty) {
      return Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        alignment: Alignment.center,
        child: const Text(
          'No photos uploaded yet.',
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF6B7280),
          ),
        ),
      );
    }

    final thumbs = _imageUrls.take(3).toList();

    return Row(
      children: List.generate(thumbs.length, (index) {
        final url = thumbs[index];
        final isSelected = index == _selectedIndex;
        final isHovered = index == _hoveredIndex;

        final bool isAsset = url.startsWith('assets/');
        final Widget imageWidget = isAsset
            ? Image.asset(url, fit: BoxFit.cover)
            : Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.black12,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_primaryColor),
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              );

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == thumbs.length - 1 ? 0 : 8),
            child: MouseRegion(
              onEnter: (_) => setState(() => _hoveredIndex = index),
              onExit: (_) => setState(() => _hoveredIndex = -1),
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = index;
                    _hoveredIndex = index;
                  });

                  final String? roomId = _resolveRoomId();
                  if (roomId == null) {
                    _showToastModal(context, 'Missing room id.');
                    return;
                  }

                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => Tour(
                        initialIndex: index,
                        roomId: roomId,
                        // ✅ pass the branch/apartment display title
                        titleHint: _displayApartmentTitle(room),
                        addressHint: room['location'] as String?,
                        monthlyHint:
                            (room['monthly_payment'] as num?)?.toDouble(),
                      ),
                      transitionsBuilder: (_, a, __, child) =>
                          FadeTransition(opacity: a, child: child),
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 100,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isHovered || isSelected)
                          ? _primaryColor.withOpacity(0.7)
                          : Colors.black.withOpacity(0.18),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: imageWidget,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // -------------------- ROOM DETAILS --------------------
  Widget _roomDetailsBox({
    required String description,
    required List<String> tags,
  }) {
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
                color: Color(0xFF003049),
              ),
              SizedBox(width: 8),
              Text(
                "Room Details",
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

  // -------------------- ACTION BUTTONS --------------------
  Widget _actionButtons(Map<String, dynamic> room) {
    final bool isAvailable = _isAvailable(room);

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () {
              final roomId = _resolveRoomId();
              if (roomId == null) {
                _showToastModal(context, 'Missing room id.');
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditRoom(roomId: roomId),
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined, size: 22),
            label: const Text(
              "Edit Room",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        if (isAvailable)
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: _primaryColor,
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: _primaryColor.withOpacity(0.3)),
                ),
              ),
              onPressed: _openAddTenantModal,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 22),
              label: const Text(
                "Add Tenant",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  void _openAddTenantModal() {
    final landlordId = _sb.auth.currentUser?.id;
    if (landlordId == null) {
      _showToastModal(context, 'No logged-in landlord found.');
      return;
    }

    final roomId = _resolveRoomId();
    if (roomId == null) {
      _showToastModal(context, 'Missing room id.');
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _TenantPicker(
        supabase: _sb,
        landlordId: landlordId,
        roomId: roomId,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// INFO CARD
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

// ---------------------------------------------------------------------------
// TENANT PICKER BOTTOM SHEET
// ✅ Walk-in Tenant form restored exactly like CODE 1 (no removed logic)
// ---------------------------------------------------------------------------

enum _PickerTab { appTenant, walkIn }

class _TenantPicker extends StatefulWidget {
  const _TenantPicker({
    required this.supabase,
    required this.landlordId,
    required this.roomId,
  });

  final SupabaseClient supabase;
  final String landlordId;
  final String roomId;

  @override
  State<_TenantPicker> createState() => _TenantPickerState();
}

class _TenantPickerState extends State<_TenantPicker> {
  final TextEditingController _searchCtrl = TextEditingController();

  // Walk-in controllers
  final TextEditingController _walkInFirstNameCtrl = TextEditingController();
  final TextEditingController _walkInLastNameCtrl = TextEditingController();
  final TextEditingController _walkInPhoneCtrl = TextEditingController();
  final TextEditingController _walkInAddressCtrl = TextEditingController();
  final List<String> _genderOptions = const ['Male', 'Female', 'Other'];
  String? _walkInGender;

  // Image picker
  final ImagePicker _imgPicker = ImagePicker();
  XFile? _walkInIdImageFile;
  Uint8List? _walkInIdImageBytes;
  bool _uploadingWalkInImage = false;

  bool _loading = true;
  String? _error;
  List<Map<String, String>> _allPeople = [];
  String _q = '';
  String? _selectedId;

  _PickerTab _tab = _PickerTab.appTenant;

  void _showToastModal(BuildContext context, String message) {
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
  }

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();

    _walkInFirstNameCtrl.dispose();
    _walkInLastNameCtrl.dispose();
    _walkInPhoneCtrl.dispose();
    _walkInAddressCtrl.dispose();

    super.dispose();
  }

  Future<void> _pickWalkInIdImage() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const Text(
              'Upload Walk-in Tenant ID Photo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Please upload a clear photo of the tenant’s valid ID (front).',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, height: 1.2),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo (Camera)'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (_walkInIdImageFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove selected image'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;

    if (choice == 'remove') {
      setState(() {
        _walkInIdImageFile = null;
        _walkInIdImageBytes = null;
      });
      return;
    }

    final source =
        (choice == 'camera') ? ImageSource.camera : ImageSource.gallery;

    try {
      final x = await _imgPicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (x == null) return;

      final bytes = await x.readAsBytes();
      if (!mounted) return;

      setState(() {
        _walkInIdImageFile = x;
        _walkInIdImageBytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      _showToastModal(context, 'Failed to pick image: $e');
    }
  }

  /// Upload image to Supabase Storage and return public URL
  /// Bucket name: "tenant-ids"
  Future<String?> _uploadWalkInIdImage({
    required String roomId,
    required String landlordId,
  }) async {
    if (_walkInIdImageFile == null) return null;

    try {
      setState(() => _uploadingWalkInImage = true);

      final bytes =
          _walkInIdImageBytes ?? await _walkInIdImageFile!.readAsBytes();

      final extRaw = _walkInIdImageFile!.name.split('.').last.toLowerCase();

      // ✅ Phone formats:
      // - Android usually: jpg/jpeg/png
      // - iPhone often: heic/heif (we support these too)
      const allowed = {'jpg', 'jpeg', 'png', 'heic', 'heif'};
      final safeExt = allowed.contains(extRaw) ? extRaw : 'jpg';

      String contentType;
      switch (safeExt) {
        case 'png':
          contentType = 'image/png';
          break;
        case 'heic':
          contentType = 'image/heic';
          break;
        case 'heif':
          contentType = 'image/heif';
          break;
        default:
          contentType = 'image/jpeg';
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '$landlordId/$roomId/walkin_$ts.$safeExt';

      await widget.supabase.storage.from('tenant-photos').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: contentType,
            ),
          );

      final publicUrl =
          widget.supabase.storage.from('tenant-photos').getPublicUrl(path);

      return publicUrl;
    } catch (e) {
      _showToastModal(context, 'Failed to upload ID image: $e');
      return null;
    } finally {
      if (mounted) setState(() => _uploadingWalkInImage = false);
    }
  }

  Future<void> _loadPeople() async {
    try {
      final meId = widget.landlordId;

      final convs = await widget.supabase
          .from('conversations')
          .select('tenant_id')
          .eq('landlord_id', meId);

      final tenantIds = <String>{};
      for (final row in (convs as List? ?? const [])) {
        final tid = row['tenant_id']?.toString();
        if (tid != null && tid.isNotEmpty) tenantIds.add(tid);
      }

      if (tenantIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _allPeople = [];
          _loading = false;
          _error = null;
        });
        return;
      }

      final assignedRows = await widget.supabase
          .from('room_tenants')
          .select('tenant_user_id, status')
          .eq('status', 'active');

      final assignedIds = <String>{};
      for (final row in (assignedRows as List? ?? const [])) {
        final tid = row['tenant_user_id']?.toString();
        if (tid != null && tid.isNotEmpty) assignedIds.add(tid);
      }

      final availableTenantIds =
          tenantIds.where((id) => !assignedIds.contains(id)).toList();

      if (availableTenantIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _allPeople = [];
          _loading = false;
          _error = null;
        });
        return;
      }

      final tenants = await widget.supabase
          .from('tenant_profile')
          .select('user_id, full_name, phone')
          .inFilter('user_id', availableTenantIds);

      final people = <Map<String, String>>[];
      for (final row in (tenants as List? ?? const [])) {
        final id = row['user_id']?.toString();
        if (id == null || id.isEmpty) continue;

        String name = (row['full_name'] as String? ?? '').trim();
        if (name.isEmpty) name = 'Tenant';

        people.add(<String, String>{'id': id, 'name': name});
      }

      if (!mounted) return;
      setState(() {
        _allPeople = people;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load tenants: $e';
      });
      _showToastModal(context, 'Failed to load tenants: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _allPeople
        .where((p) => p['name']!.toLowerCase().contains(_q.toLowerCase()))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tabs
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _tab = _PickerTab.appTenant;
                          _selectedId = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tab == _PickerTab.appTenant
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'App Tenant',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _tab == _PickerTab.appTenant
                                ? Colors.black87
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _tab = _PickerTab.walkIn;
                          _selectedId = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _tab == _PickerTab.walkIn
                              ? Colors.white
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'Walk-in Tenant',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _tab == _PickerTab.walkIn
                                ? Colors.black87
                                : Colors.black54,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ---------------- APP TENANT ----------------
            if (_tab == _PickerTab.appTenant) ...[
              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black26, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.black54),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Search tenant',
                          border: InputBorder.none,
                        ),
                        onChanged: (v) => setState(() => _q = v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                )
              else if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No tenants found.\n'
                    'Only tenants who have conversations with you and are not already assigned to a room will show here.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final p = filtered[i];
                      final bool isChecked = _selectedId == p['id'];

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black87, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          onTap: () => setState(() {
                            _selectedId = isChecked ? null : p['id'];
                          }),
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFECECEC),
                            radius: 22,
                            child: Icon(Icons.person, color: Colors.black54),
                          ),
                          title: Text(
                            p['name'] ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          trailing: InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () => setState(() {
                              _selectedId = isChecked ? null : p['id'];
                            }),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: Colors.black87,
                                  width: 2,
                                ),
                                color: isChecked
                                    ? Colors.black87
                                    : Colors.transparent,
                              ),
                              alignment: Alignment.center,
                              child: isChecked
                                  ? const Icon(
                                      Icons.check,
                                      size: 18,
                                      color: Colors.white,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],

            // ---------------- WALK-IN TENANT ----------------
            if (_tab == _PickerTab.walkIn) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.black.withOpacity(0.12)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Walk-in Tenant Details',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ✅ Label + phone format guide
                    const Text(
                      'Upload: Convo Screenshot',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Accepted formats: JPG/JPEG',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ✅ Preview box with button INSIDE
                    Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.black.withOpacity(0.08)),
                      ),
                      child: Stack(
                        children: [
                          // Image / placeholder
                          Positioned.fill(
                            child: _walkInIdImageBytes == null
                                ? const Center(
                                    child: Text(
                                      'No image selected.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.black54,
                                        height: 1.2,
                                      ),
                                    ),
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(
                                      _walkInIdImageBytes!,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),

                          // Dark gradient at bottom for buttons
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(12),
                                ),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.55),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.black87,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                      ),
                                      onPressed: _uploadingWalkInImage
                                          ? null
                                          : _pickWalkInIdImage,
                                      icon: const Icon(
                                          Icons.upload_file_outlined),
                                      label: Text(
                                        _walkInIdImageFile == null
                                            ? 'Upload Convo Screenshot'
                                            : 'Change Photo',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  if (_walkInIdImageFile != null)
                                    IconButton(
                                      tooltip: 'Remove',
                                      onPressed: _uploadingWalkInImage
                                          ? null
                                          : () {
                                              setState(() {
                                                _walkInIdImageFile = null;
                                                _walkInIdImageBytes = null;
                                              });
                                            },
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.white,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          if (_uploadingWalkInImage)
                            Positioned.fill(
                              child: Container(
                                color: Colors.black.withOpacity(0.18),
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _walkInFirstNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                              border: OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _walkInLastNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                              border: OutlineInputBorder(),
                            ),
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _walkInGender,
                      items: _genderOptions
                          .map(
                            (g) => DropdownMenuItem<String>(
                              value: g,
                              child: Text(g),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _walkInGender = v),
                      decoration: const InputDecoration(
                        labelText: 'Gender',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _walkInAddressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _walkInPhoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'This tenant does not need the app. They will still be assigned to the room.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.black54,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Footer buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black87, width: 1.5),
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black87,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _uploadingWalkInImage ? null : _onAddPressed,
                    child: _uploadingWalkInImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAddPressed() async {
    // WALK-IN PATH
    if (_tab == _PickerTab.walkIn) {
      final firstName = _walkInFirstNameCtrl.text.trim();
      final lastName = _walkInLastNameCtrl.text.trim();
      final pickedPhone = _walkInPhoneCtrl.text.trim();
      final pickedAddress = _walkInAddressCtrl.text.trim();
      final pickedGender = _walkInGender;

      if (firstName.isEmpty || lastName.isEmpty) {
        _showToastModal(context, 'Please enter first name and last name.');
        return;
      }
      if (pickedGender == null || pickedGender.isEmpty) {
        _showToastModal(context, 'Please select the tenant gender.');
        return;
      }
      if (pickedAddress.isEmpty) {
        _showToastModal(context, 'Please enter the tenant address.');
        return;
      }

      final fullName = '$firstName $lastName'.trim();

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm selection'),
          content: Text(
            'Assign this walk-in tenant to the room?\n\n'
            '$fullName\n'
            '$pickedGender\n'
            '$pickedAddress'
            '${pickedPhone.isNotEmpty ? '\n$pickedPhone' : ''}'
            '${_walkInIdImageFile != null ? '\n\nID Photo: attached' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, add'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        final idPhotoUrl = await _uploadWalkInIdImage(
          roomId: widget.roomId,
          landlordId: widget.landlordId,
        );

        await widget.supabase.from('room_tenants').insert({
          'room_id': widget.roomId,
          'tenant_user_id': null,
          'full_name': fullName,
          'gender': pickedGender,
          'address': pickedAddress,
          'phone': pickedPhone.isEmpty ? null : pickedPhone,
          'landlord_id': widget.landlordId,
          'status': 'active',
          'start_date': DateTime.now().toIso8601String().split('T')[0],
          'walkin_id_photo_url': idPhotoUrl, // add this column in DB
        });

        await widget.supabase
            .from('rooms')
            .update({'availability_status': 'not_available'})
            .eq('id', widget.roomId);

        if (!mounted) return;
        Navigator.pop(context);

        _showToastModal(
          context,
          'Walk-in tenant added. Room is now occupied.',
        );
      } catch (e) {
        if (!mounted) return;
        _showToastModal(context, 'Failed to assign walk-in tenant: $e');
      }

      return;
    }

    // APP TENANT PATH
    if (_selectedId == null || _selectedId!.isEmpty) {
      _showToastModal(context, 'No tenant selected.');
      return;
    }

    final sel = _allPeople.firstWhere(
      (p) => p['id'] == _selectedId,
      orElse: () => const <String, String>{'id': '', 'name': ''},
    );

    final pickedName = sel['name'] ?? '';
    final pickedId = sel['id'] ?? '';

    if (pickedId.isEmpty) {
      _showToastModal(context, 'No tenant selected.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm selection'),
        content: Text('Are you sure this is the right tenant?\n\n$pickedName'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, add'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.supabase.from('room_tenants').insert({
          'room_id': widget.roomId,
          'tenant_user_id': pickedId,
          'full_name': pickedName,
          'landlord_id': widget.landlordId,
          'status': 'active',
          'start_date': DateTime.now().toIso8601String().split('T')[0],
        });

        await widget.supabase
            .from('rooms')
            .update({'availability_status': 'not_available'})
            .eq('id', widget.roomId);

        if (!mounted) return;
        Navigator.pop(context);

        _showToastModal(
          context,
          'Tenant added. Room is now occupied and visible in their My Room page.',
        );
      } catch (e) {
        if (!mounted) return;
        _showToastModal(context, 'Failed to assign tenant: $e');
      }
    }
  }
}
