// TENANT/TROOMINFO.dart  ✅ UPDATED (adds water_per_head + per_watt_price, removes reservation logic)
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../TOUR.dart';

class TenantRoomInfo extends StatefulWidget {
  final String roomId;

  final String? titleHint;
  final String? addressHint;
  final double? monthlyHint;

  const TenantRoomInfo({
    super.key,
    required this.roomId,
    this.titleHint,
    this.addressHint,
    this.monthlyHint,
  });

  @override
  State<TenantRoomInfo> createState() => _TenantRoomInfoState();
}

class _TenantRoomInfoState extends State<TenantRoomInfo> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  String _apartmentName = '';
  String _location = '';
  int? _floorNumber;
  double? _monthlyPayment;
  double? _advanceDeposit;

  // ✅ NEW: pricing fields
  double? _waterPerHead;
  double? _perWattPrice;

  String _description = '';
  String _roomName = '';

  final List<_Img> _images = [];
  List<String> _inclusions = [];
  List<String> _preferences = [];

  int _hoveredIndex = -1;
  int _selectedIndex = 0;

  static const Color _primaryColor = Color(0xFF003049);
  static const Color _backgroundColor = Color(0xFFF2F4F7);

  @override
  void initState() {
    super.initState();
    _apartmentName = widget.titleHint ?? _apartmentName;
    _location = widget.addressHint ?? _location;
    _monthlyPayment = widget.monthlyHint ?? _monthlyPayment;

    _loadRoom();
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  String _composeTitle() {
    final parts = <String>[];
    if (_roomName.trim().isNotEmpty) parts.add(_roomName.trim());
    if (_apartmentName.trim().isNotEmpty) parts.add(_apartmentName.trim());
    if (parts.isEmpty) return 'Room Info';
    return parts.join(' • ');
  }

  String _moneyFixed0(double? v) {
    if (v == null) return '—';
    return '₱${v.toStringAsFixed(0)}';
  }

  // ✅ NEW (matches CODE 1 style)
  String _moneyFixed2(double? v) {
    if (v == null) return '—';
    return '₱${v.toStringAsFixed(2)}';
  }

  // ✅ NEW: formats like "₱150.00 /head"
  String _moneyWithSuffix(double? v, String suffix) {
    if (v == null) return '—';
    return '₱${v.toStringAsFixed(2)} $suffix';
  }

  String _floorText(int? floor) => floor == null ? 'Floor —' : 'Floor $floor';

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

  Future<void> _loadRoom() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // ✅ UPDATED: include water_per_head + per_watt_price
      final data = await _sb
          .from('rooms')
          .select('''
            id,
            apartment_name,
            location,
            floor_number,
            monthly_payment,
            advance_deposit,
            water_per_head,
            per_watt_price,
            description,
            room_name,
            room_images ( id, image_url, sort_order ),
            room_inclusions ( inclusion_options ( name ) ),
            room_preferences ( preference_options ( name ) )
          ''')
          .eq('id', widget.roomId)
          .maybeSingle();

      if (data == null) {
        setState(() {
          _loading = false;
          _error = 'Room not found.';
        });
        return;
      }

      _apartmentName = (data['apartment_name'] ?? '') as String;
      _location = (data['location'] ?? '') as String;
      _floorNumber = data['floor_number'] as int?;
      _monthlyPayment = _toDouble(data['monthly_payment']);
      _advanceDeposit = _toDouble(data['advance_deposit']);

      // ✅ NEW
      _waterPerHead = _toDouble(data['water_per_head']);
      _perWattPrice = _toDouble(data['per_watt_price']);

      _description = (data['description'] ?? '') as String;
      _roomName = (data['room_name'] ?? '') as String;

      _images
        ..clear()
        ..addAll([
          for (final r in (data['room_images'] as List? ?? []))
            _Img(
              id: r['id'] as String,
              url: (r['image_url'] ?? '') as String,
              sort: (r['sort_order'] ?? 0) as int,
            ),
        ]);
      _images.sort((a, b) => a.sort.compareTo(b.sort));

      final incRows = (data['room_inclusions'] as List?) ?? [];
      _inclusions = [
        for (final r in incRows)
          if (r['inclusion_options'] != null &&
              r['inclusion_options']['name'] != null)
            r['inclusion_options']['name'] as String,
      ];

      final prefRows = (data['room_preferences'] as List?) ?? [];
      _preferences = [
        for (final r in prefRows)
          if (r['preference_options'] != null &&
              r['preference_options']['name'] != null)
            r['preference_options']['name'] as String,
      ];

      setState(() {
        _loading = false;
        _error = null;
        _selectedIndex = 0;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load room: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = _composeTitle();

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
          backgroundColor: _primaryColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            titleText,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadRoom,
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          titleText,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadRoom,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeroCard(),
            const SizedBox(height: 20),
            _buildOverviewGrid(), // ✅ now includes water + watts
            const SizedBox(height: 20),
            _buildPhotosSection(),
            const SizedBox(height: 20),
            _roomDetailsBox(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final String mainImageUrl = _images.isNotEmpty ? _images.first.url : '';
    final String location =
        _location.isEmpty ? 'No location provided' : _location;
    final String monthly = _moneyFixed0(_monthlyPayment);

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
                              Icons.price_change_outlined,
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

  Widget _buildOverviewGrid() {
    final String apartmentName = _apartmentName.isEmpty ? '—' : _apartmentName;
    final String location = _location.isEmpty ? '—' : _location;
    final String monthly = _moneyFixed0(_monthlyPayment);
    final String advance = _moneyFixed0(_advanceDeposit);

    // ✅ NEW: pricing display
    final String waterPerHead = _moneyWithSuffix(_waterPerHead, '/head');
    final String perWatt = _moneyWithSuffix(_perWattPrice, '/watts');

    final String floor =
        _floorNumber != null ? _floorText(_floorNumber) : 'Not set';

    final String inclusions =
        _inclusions.isEmpty ? '—' : _inclusions.join(', ');
    final String preferences =
        _preferences.isEmpty ? '—' : _preferences.join(', ');

    final String roomName = _roomName.trim().isEmpty ? 'Room' : _roomName.trim();

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
        const SizedBox(height: 10),

        // ✅ NEW ROW: Water + Watts
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
                value: perWatt,
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
                icon: Icons.people_alt_outlined,
                title: 'Preferences',
                value: preferences,
                maxLines: 3,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPhotosSection() {
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
        _imageRow(),
      ],
    );
  }

  Widget _imageRow() {
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
        final url = thumbs[index].url;
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

                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (_, __, ___) => Tour(
                        initialIndex: index,
                        roomId: widget.roomId,
                        titleHint: _apartmentName,
                        addressHint: _location,
                        monthlyHint: _monthlyPayment,
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

  Widget _roomDetailsBox() {
    final tags = <String>[
      ..._inclusions.map((e) => '#$e'),
      ..._preferences.map((e) => '#$e'),
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
            _description.isEmpty ? "No description provided." : _description,
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

class _Img {
  final String id;
  final String url;
  final int sort;
  _Img({required this.id, required this.url, required this.sort});
}
