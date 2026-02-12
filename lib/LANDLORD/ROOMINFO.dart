import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ UPDATED: Use LANDLORD/TOUR.dart (CODE 2)
import 'package:smart_finder/LANDLORD/TOUR.dart';

class Roominfo extends StatefulWidget {
  final String roomId;
  const Roominfo({super.key, required this.roomId});

  @override
  State<Roominfo> createState() => _RoominfoState();
}

class _RoominfoState extends State<Roominfo> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _room; // rooms row
  List<Map<String, dynamic>> _images = []; // [{id, image_url, sort_order}]
  List<String> _inclusions = [];
  List<String> _preferences = [];

  int _hoveredIndex = -1;
  int _selectedIndex = 0;

  static const Color _primaryColor = Color(0xFF003049);
  static const Color _backgroundColor = Color(0xFFF2F4F7);

  @override
  void initState() {
    super.initState();
    _loadRoom();
  }

  String _s(dynamic v, [String fallback = '—']) {
    final t = (v ?? '').toString().trim();
    return t.isEmpty ? fallback : t;
  }

  Future<void> _loadRoom() async {
    try {
      // ✅ UPDATED: include water_per_head and per_watt_price
      final room = await supabase
          .from('rooms')
          .select(
            'id, floor_number, apartment_name, location, monthly_payment, advance_deposit, '
            'water_per_head, per_watt_price, '
            'description, room_name, availability_status, status',
          )
          .eq('id', widget.roomId)
          .single();

      final imgs = await supabase
          .from('room_images')
          .select('id, image_url, sort_order')
          .eq('room_id', widget.roomId)
          .order('sort_order', ascending: true);

      List<String> inclusions = [];
      try {
        final incRows = await supabase
            .from('room_inclusions')
            .select('inclusion_options(name)')
            .eq('room_id', widget.roomId);

        inclusions = incRows
            .map<String>(
              (e) => (e['inclusion_options']?['name'] as String?) ?? '',
            )
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } catch (_) {}

      List<String> preferences = [];
      try {
        final prefRows = await supabase
            .from('room_preferences')
            .select('preference_options(name)')
            .eq('room_id', widget.roomId);

        preferences = prefRows
            .map<String>(
              (e) => (e['preference_options']?['name'] as String?) ?? '',
            )
            .where((s) => s.trim().isNotEmpty)
            .toList();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _room = room;
        _images = List<Map<String, dynamic>>.from(imgs);
        _inclusions = inclusions;
        _preferences = preferences;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _money(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '—';
    return '₱${n.toStringAsFixed(2)}';
  }

  // ✅ formats like "₱150.00 /head" and "₱12.50 /watts"
  String _moneyWithSuffix(dynamic v, String suffix) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '—';
    return '₱${n.toStringAsFixed(2)} $suffix';
  }

  String _floorText(int? floor) => floor == null ? 'Floor —' : 'Floor $floor';

  bool _isAvailable(Map<String, dynamic> room) {
    final availability =
        (room['availability_status'] ?? room['status'] ?? 'available')
            .toString()
            .toLowerCase();
    return availability == 'available';
  }

  Widget _thumb(String url) {
    return Image.network(
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
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;

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

    if (_error != null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        appBar: AppBar(
          backgroundColor: const Color(0xFF04354B),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Room Info',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 0.8,
            ),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Failed to load room: $_error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final Map<String, dynamic> safeRoom = room ?? <String, dynamic>{};

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Room Info',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroCard(safeRoom),
            const SizedBox(height: 20),
            _buildOverviewGrid(safeRoom),
            const SizedBox(height: 20),
            _buildPhotosSection(safeRoom),
            const SizedBox(height: 20),
            _roomDetailsBox(
              description: _s(safeRoom['description'], 'No description provided.'),
              tags: [
                ..._preferences.map((e) => '#$e'),
                ..._inclusions.map((e) => '#$e'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------- HERO CARD --------------------
  Widget _buildHeroCard(Map<String, dynamic> room) {
    final String mainImageUrl =
        _images.isNotEmpty ? (_images.first['image_url'] as String? ?? '') : '';
    final String location = _s(room['location'], 'No location provided');
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
              if (mainImageUrl.trim().isNotEmpty)
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
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.6),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              FontAwesomeIcons.pesoSign,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              monthly,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
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
    return Image.network(
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
  }

  // -------------------- OVERVIEW GRID --------------------
  Widget _buildOverviewGrid(Map<String, dynamic> room) {
    final String apartmentName = _s(room['apartment_name']);
    final String location = _s(room['location']);
    final String monthly = _money(room['monthly_payment']);
    final String advance = _money(room['advance_deposit']);

    final String waterPerHead = _moneyWithSuffix(room['water_per_head'], '/head');
    final String perWattPrice = _moneyWithSuffix(room['per_watt_price'], '/watts');

    final String floor = room['floor_number'] != null
        ? _floorText(room['floor_number'] as int?)
        : 'Not set';

    final String inclusions = _inclusions.isEmpty ? '—' : _inclusions.join(', ');

    final String roomName = _s(room['room_name'], 'Room');

    final String tenantText = _isAvailable(room) ? 'Not yet occupied' : 'Occupied';

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
                icon: Icons.layers_outlined,
                title: 'Floor',
                value: floor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.meeting_room_outlined,
                title: 'Room Name',
                value: roomName,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoCard(
                icon: Icons.chair_outlined,
                title: 'Inclusions',
                value: inclusions,
                maxLines: 3,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoCard(
                icon: Icons.person_outline,
                title: 'Tenant',
                value: tenantText,
                maxLines: 2,
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
    if (_images.isEmpty) {
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

    final thumbs = _images.take(3).toList();

    return Row(
      children: List.generate(thumbs.length, (index) {
        final url = (thumbs[index]['image_url'] as String?) ?? '';
        final isSelected = index == _selectedIndex;
        final isHovered = index == _hoveredIndex;

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

                  // ✅ UPDATED: Navigate to CODE 2 (LTour) when clicking photos
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => LTour(
                        initialIndex: index,
                        roomId: widget.roomId,
                        titleHint: (room['apartment_name'] as String?)?.trim(),
                        addressHint: (room['location'] as String?)?.trim(),
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
                      child: url.trim().isEmpty
                          ? const ColoredBox(color: Colors.black12)
                          : _thumb(url),
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
