// lib/LANDLORD/roomnotavail.dart
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:smart_finder/LANDLORD/WALKIN_TPROFILE.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../TOUR.dart';
import 'EditRoom.dart';

// ✅ App tenant profile page
import '../TENANT/TPROFILE.dart';


class RoomNotAvailable extends StatefulWidget {
  const RoomNotAvailable({
    super.key,
    required this.roomData,
  });

  final Map<String, dynamic> roomData;

  @override
  State<RoomNotAvailable> createState() => _RoomNotAvailableState();
}

class _RoomNotAvailableState extends State<RoomNotAvailable> {
  final SupabaseClient _sb = Supabase.instance.client;

  static const Color _primaryColor = Color(0xFF003049);
  static const Color _backgroundColor = Color(0xFFF2F4F7);

  Map<String, dynamic>? _room;
  bool _loading = true;

  List<String> _imageUrls = [];

  List<String> _inclusions = [];
  List<String> _preferences = [];

  RealtimeChannel? _roomChannel;
  RealtimeChannel? _imagesChannel;

  int _hoveredIndex = -1;
  int _selectedIndex = 0;

  String? _resolveRoomId() {
    final dynamic raw = _room != null ? _room!['id'] : widget.roomData['id'];
    if (raw == null) return null;

    final id = raw.toString().trim();
    return id.isEmpty ? null : id;
  }

  String _money(dynamic v) {
    if (v == null) return '₱—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '₱—';
    return '₱${n.toStringAsFixed(2)}';
  }

  String _moneyWithSuffix(dynamic v, String suffix) {
    if (v == null) return '₱—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '₱—';
    return '₱${n.toStringAsFixed(2)} $suffix';
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

  void _showInfoDialog(BuildContext context, String message) {
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

  Future<void> _fetchAll() async {
    try {
      final String? idOpt = _resolveRoomId();
      if (idOpt == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final String id = idOpt;

      final roomData =
          await _sb.from('rooms').select().eq('id', id).maybeSingle();

      Map<String, dynamic>? landlordProfile;
      final landlordId = _sb.auth.currentUser?.id;
      if (landlordId != null) {
        landlordProfile = await _sb
            .from('landlord_profile')
            .select('apartment_name')
            .eq('user_id', landlordId)
            .maybeSingle();
      }

      // ✅ Active tenant mapping (now includes phone/address/gender too)
      String? tenantName;
      String? tenantUserId;
      String? tenantPhone;
      String? tenantAddress;
      String? tenantGender;

      try {
        final mapping = await _sb
            .from('room_tenants')
            .select('full_name, tenant_user_id, phone, address, gender')
            .eq('room_id', id)
            .eq('status', 'active')
            .maybeSingle();

        tenantUserId = (mapping?['tenant_user_id'] ?? '').toString().trim();

        tenantPhone = (mapping?['phone'] ?? '').toString().trim();
        tenantAddress = (mapping?['address'] ?? '').toString().trim();
        tenantGender = (mapping?['gender'] ?? '').toString().trim();

        final direct = (mapping?['full_name'] ?? '').toString().trim();
        if (direct.isNotEmpty) {
          tenantName = direct;
        } else {
          if (tenantUserId.isNotEmpty) {
            final prof = await _sb
                .from('tenant_profile')
                .select('full_name')
                .eq('user_id', tenantUserId)
                .maybeSingle();

            final pName = (prof?['full_name'] ?? '').toString().trim();
            if (pName.isNotEmpty) tenantName = pName;
          }
        }
      } catch (e) {
        debugPrint('Tenant lookup error: $e');
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

      List<String> inclusions = [];
      try {
        final incRows = await _sb
            .from('room_inclusions')
            .select('inclusion_options(name)')
            .eq('room_id', id);

        inclusions = (incRows as List? ?? const [])
            .map<String>(
              (e) => (e['inclusion_options']?['name'] as String?) ?? '',
            )
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } catch (e) {
        debugPrint('RoomNotAvailable: load inclusions error: $e');
      }

      List<String> preferences = [];
      try {
        final prefRows = await _sb
            .from('room_preferences')
            .select('preference_options(name)')
            .eq('room_id', id);

        preferences = (prefRows as List? ?? const [])
            .map<String>(
              (e) => (e['preference_options']?['name'] as String?) ?? '',
            )
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } catch (e) {
        debugPrint('RoomNotAvailable: load preferences error: $e');
      }

      if (!mounted) return;

      setState(() {
        final base = (roomData as Map<String, dynamic>?) ?? widget.roomData;
        final merged = <String, dynamic>{...base};

        if (tenantName != null && tenantName.trim().isNotEmpty) {
          merged['tenant_name'] = tenantName.trim();
        }

        if (tenantUserId != null && tenantUserId.trim().isNotEmpty) {
          merged['tenant_user_id'] = tenantUserId.trim();
        } else {
          merged.remove('tenant_user_id'); // ensure null for walk-in
        }

        // store walk-in info so UI can display / pass it if needed
        if (tenantPhone != null && tenantPhone.trim().isNotEmpty) {
          merged['tenant_phone'] = tenantPhone.trim();
        }
        if (tenantAddress != null && tenantAddress.trim().isNotEmpty) {
          merged['tenant_address'] = tenantAddress.trim();
        }
        if (tenantGender != null && tenantGender.trim().isNotEmpty) {
          merged['tenant_gender'] = tenantGender.trim();
        }

        final String? latestApartmentName =
            (landlordProfile?['apartment_name'] as String?)?.trim();
        if (latestApartmentName != null && latestApartmentName.isNotEmpty) {
          merged['apartment_name'] = latestApartmentName;
        }

        _room = merged;
        _inclusions = inclusions;
        _preferences = preferences;
        _imageUrls = urls.isEmpty
            ? [
                'assets/images/roompano.png',
                'assets/images/roompano2.png',
                'assets/images/roompano3.png',
              ]
            : urls;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching room / images: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _listenRealtime() {
    final String? idOpt = _resolveRoomId();
    if (idOpt == null) return;
    final String id = idOpt;

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

    final String apartmentName = (room['apartment_name'] ?? '').toString();
    final String title = apartmentName.isNotEmpty ? apartmentName : 'Room Info';

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
              _roomDetailsBox(room),
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
                    color: Colors.red.shade600.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.block,
                        size: 14,
                        color: Colors.white,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Not Available',
                        style: TextStyle(
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
    final String apartmentName = (room['apartment_name'] ?? '—').toString();
    final String location = (room['location'] ?? '—').toString();
    final String monthly = _money(room['monthly_payment']);
    final String advance = _money(room['advance_deposit']);

    final String waterPerHead =
        _moneyWithSuffix(room['water_per_head'], '/head');
    final String perWattPrice =
        _moneyWithSuffix(room['per_watt_price'], '/watts');

    final String roomName = (room['room_name'] ?? 'Room').toString();

    final String floor = room['floor_number'] != null
        ? 'Floor ${room['floor_number']}'
        : 'Not set';

    final String inclusions =
        _inclusions.isEmpty ? '—' : _inclusions.join(', ');

    final String tenantName = (room['tenant_name'] ?? 'Occupant').toString();
    final String? tenantUserId =
        (room['tenant_user_id'] ?? '').toString().trim().isEmpty
            ? null
            : (room['tenant_user_id'] ?? '').toString().trim();

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
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final roomId = _resolveRoomId();
                  if (roomId == null) {
                    _showInfoDialog(context, 'Missing room id.');
                    return;
                  }

                  // ✅ If tenantUserId exists => app tenant profile
                  if (tenantUserId != null && tenantUserId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TenantProfile(userId: tenantUserId),
                      ),
                    );
                    return;
                  }

                  // ✅ else => walk-in profile page (Name, Address, Gender, Phone)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WalkInTenantProfile(roomId: roomId),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    _InfoCard(
                      icon: Icons.person_outline,
                      title: 'Tenant',
                      value: tenantName,
                      maxLines: 2,
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: Icon(
                        Icons.open_in_new,
                        size: 16,
                        color: Colors.black.withOpacity(0.45),
                      ),
                    ),
                  ],
                ),
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
                    _showInfoDialog(context, 'Missing room id.');
                    return;
                  }

                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => Tour(
                        initialIndex: index,
                        roomId: roomId,
                        titleHint: room['apartment_name'] as String?,
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
  Widget _roomDetailsBox(Map<String, dynamic> room) {
    final String description = (room['description'] as String?) ??
        "Currently unavailable. Cozy room with single bed, table, chair, and Wi-Fi.";

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

  // -------------------- ACTION BUTTONS --------------------
  Widget _actionButtons(Map<String, dynamic> room) {
    final String? roomId = _resolveRoomId();

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
              if (roomId == null) {
                _showInfoDialog(context, 'Missing room id.');
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
              'Edit Room',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              if (roomId == null) {
                _showInfoDialog(context, 'Missing room id.');
                return;
              }

              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Deactivate tenant'),
                  content: const Text(
                    'This will remove the tenant from this room and make it available again. Continue?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Yes, deactivate'),
                    ),
                  ],
                ),
              );

              if (confirm != true) return;

              try {
                final mapping = await _sb
                    .from('room_tenants')
                    .select('id')
                    .eq('room_id', roomId)
                    .eq('status', 'active')
                    .maybeSingle();

                if (mapping != null && mapping['id'] != null) {
                  await _sb
                      .from('room_tenants')
                      .update({'status': 'inactive'})
                      .eq('id', mapping['id']);
                }

                await _sb
                    .from('rooms')
                    .update({'availability_status': 'available'})
                    .eq('id', roomId);

                if (!mounted) return;

                _showInfoDialog(
                  context,
                  'Tenant deactivated. Room is now available again.',
                );

                Navigator.pop(context);
              } catch (e) {
                if (!mounted) return;
                _showInfoDialog(context, 'Failed to deactivate tenant: $e');
              }
            },
            icon: const Icon(Icons.person_off_outlined, size: 22),
            label: const Text(
              'Deactivate Tenant',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

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
