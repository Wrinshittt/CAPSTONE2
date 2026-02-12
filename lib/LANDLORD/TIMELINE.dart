// timeline.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ROOMINFO.dart';
import 'ADDROOM.dart';
// Landlord map page that shows the address
import 'gmap.dart' show Gmap;
// NEW: Virtual tour page
import 'TOUR.dart' show LTour;
import 'landlord_bottom_nav.dart';

class Timeline extends StatefulWidget {
  const Timeline({super.key});

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  // ------------ Supabase (for rooms) ------------
  final supabase = Supabase.instance.client;

  // ------------ Timeline data ------------
  String sortOption = 'Date Posted';
  List<Map<String, dynamic>> apartments = [];
  int currentPage = 0;
  final int cardsPerPage = 5;
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;

  // Prevent overlapping fetches
  bool _isFetching = false;

  // ================== TAG BUILDING ==================

  static const Map<String, String> _prefPretty = {
    'pet-friendly': '#PetFriendly',
    'pet friendly': '#PetFriendly',
    'open to all': '#OpenToAll',
    'student only': '#StudentOnly',
    'working professionals': '#WorkingProfessionals',
    'professional only': '#WorkingProfessionals',
    'non-smoker only': '#NonSmoker',
    'non smoker only': '#NonSmoker',
  };

  static const Map<String, String> _incPretty = {
    'wifi': '#WithWiFi',
    'with wifi': '#WithWiFi',
    'single bed': '#SingleBed',
    'bed': '#SingleBed',
    'double bed': '#DoubleBed',
    'own cr': '#OwnCR',
    'private cr': '#OwnCR',
    'common cr': '#CommonCR',
  };

  String _autoHash(String v) {
    final cleaned = v
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty
            ? ''
            : (w.substring(0, 1).toUpperCase() +
                w.substring(1).toLowerCase()))
        .join();
    return cleaned.isEmpty ? '' : '#$cleaned';
  }

  List<String> _buildHashtags(
    Set<String> prefLabels,
    Set<String> incLabels,
    String location,
  ) {
    final tags = <String>[];

    for (final raw in prefLabels) {
      final key = raw.trim().toLowerCase();
      final pretty = _prefPretty[key];
      final tag = (pretty ?? _autoHash(raw));
      if (tag.isNotEmpty) tags.add(tag);
    }

    for (final raw in incLabels) {
      final key = raw.trim().toLowerCase();
      final pretty = _incPretty[key];
      final tag = (pretty ?? _autoHash(raw));
      if (tag.isNotEmpty) tags.add(tag);
    }

    final locLower = location.toLowerCase();
    if (locLower.contains('near um')) tags.add('#NearUM');
    if (locLower.contains('near sm eco')) tags.add('#NearSMEco');
    if (locLower.contains('near mapua')) tags.add('#NearMapua');
    if (locLower.contains('near ddc')) tags.add('#NearDDC');

    final seen = <String>{};
    return tags.where((t) => seen.add(t)).toList();
  }

  // Enrich the built items with landlord preferences and inclusions -> tags
  Future<void> _enrichRoomAttributes(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;

    final roomIds =
        items.map((e) => e['id'] as String).where((e) => e.isNotEmpty).toList();
    if (roomIds.isEmpty) return;

    final quoted = roomIds.map((id) => '"$id"').join(',');

    // ---------- room_preferences → preference_options(name)
    try {
      final prefsRows = await supabase
          .from('room_preferences')
          .select('room_id, preference_options(name)')
          .filter('room_id', 'in', '($quoted)');

      final byRoomPrefs = <String, Set<String>>{};
      for (final row in (prefsRows as List? ?? <dynamic>[])) {
        final rid = row['room_id']?.toString();
        if (rid == null) continue;

        final set = byRoomPrefs.putIfAbsent(rid, () => <String>{});
        final po = row['preference_options'];

        if (po is Map) {
          final n = (po['name'] ?? '').toString().trim();
          if (n.isNotEmpty) set.add(n);
        } else if (po is List) {
          for (final o in po) {
            final n = (o['name'] ?? '').toString().trim();
            if (n.isNotEmpty) set.add(n);
          }
        }
      }

      for (var i = 0; i < items.length; i++) {
        items[i] = {
          ...items[i],
          'prefLabels': byRoomPrefs[items[i]['id']] ?? <String>{},
        };
      }
    } catch (e, st) {
      debugPrint('prefs load failed: $e\n$st');
    }

    // ---------- room_inclusions → inclusion_options(name)
    try {
      final incRows = await supabase
          .from('room_inclusions')
          .select('room_id, inclusion_options(name)')
          .filter('room_id', 'in', '($quoted)');

      final byRoomIncs = <String, Set<String>>{};
      for (final row in (incRows as List? ?? <dynamic>[])) {
        final rid = row['room_id']?.toString();
        if (rid == null) continue;

        final set = byRoomIncs.putIfAbsent(rid, () => <String>{});
        final io = row['inclusion_options'];

        if (io is Map) {
          final n = (io['name'] ?? '').toString().trim();
          if (n.isNotEmpty) set.add(n);
        } else if (io is List) {
          for (final o in io) {
            final n = (o['name'] ?? '').toString().trim();
            if (n.isNotEmpty) set.add(n);
          }
        }
      }

      for (var i = 0; i < items.length; i++) {
        items[i] = {
          ...items[i],
          'incLabels': byRoomIncs[items[i]['id']] ?? <String>{},
        };
      }
    } catch (e, st) {
      debugPrint('inclusions load failed: $e\n$st');
    }

    // Build display hashtags used for the cards
    for (var i = 0; i < items.length; i++) {
      items[i] = {
        ...items[i],
        'tags': _buildHashtags(
          (items[i]['prefLabels'] as Set<String>? ?? {}),
          (items[i]['incLabels'] as Set<String>? ?? {}),
          (items[i]['location'] as String?) ?? '',
        ),
      };
    }
  }

  // ================== TIMELINE ==================
  @override
  void initState() {
    super.initState();
    _refreshFromSupabase();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refreshFromSupabase() async {
    if (_isFetching) return;
    _isFetching = true;
    if (mounted) setState(() => _loading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            apartments = [];
            currentPage = 0;
          });
        }
        return;
      }

      final List rooms = await supabase
          .from('rooms')
          .select(
            'id, apartment_name, location, monthly_payment, created_at, status',
          )
          .eq('landlord_id', user.id)
          .order('created_at', ascending: false);

      if (rooms.isEmpty) {
        if (mounted) {
          setState(() {
            apartments = [];
            _loading = false;
            currentPage = 0;
          });
        }
        return;
      }

      final List<String> roomIds =
          rooms.map<String>((r) => r['id'] as String).toList();

      final quoted = roomIds.map((id) => '"$id"').join(',');
      final List imgs = await supabase
          .from('room_images')
          .select('room_id, image_url, sort_order')
          .filter('room_id', 'in', '($quoted)');

      final Map<String, Map<String, dynamic>> firstImageByRoom = {};
      for (final img in imgs) {
        final rid = img['room_id'] as String;
        final so = (img['sort_order'] ?? 0) as int;
        final current = firstImageByRoom[rid];
        if (current == null || so < (current['sort_order'] ?? 1 << 30)) {
          firstImageByRoom[rid] = {
            'image_url': img['image_url'],
            'sort_order': so,
          };
        }
      }

      final List<Map<String, dynamic>> items = [];
      for (final r in rooms) {
        final img = firstImageByRoom[r['id']];
        items.add({
          'id': r['id'],
          'status': (r['status'] ?? 'pending').toString(),
          'title': (r['apartment_name'] ?? 'Room').toString(),
          'price': (r['monthly_payment'] ?? '').toString(),
          'location': (r['location'] ?? '').toString(),
          'imageUrl': img?['image_url'] as String?,
          'prefLabels': <String>{},
          'incLabels': <String>{},
          'tags': const <String>[],
          // extra fields for sorting
          'created_at': r['created_at'],
          'priceValue': (r['monthly_payment'] as num?)?.toDouble() ?? 0.0,
        });
      }

      await _enrichRoomAttributes(items);

      if (mounted) {
        setState(() {
          apartments = items;
          currentPage = 0;
          _sortApartments(); // apply current sort option after load
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Rooms/images query failed: ${e.message}');
      if (mounted) {
        setState(() => apartments = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn’t load timeline: ${e.message}')),
        );
      }
    } catch (e, st) {
      debugPrint('Rooms/images query threw: $e\n$st');
      if (mounted) {
        setState(() => apartments = []);
        const snackBar = SnackBar(
          content: Text(
            'Couldn’t load timeline. Check connection or permissions.',
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    } finally {
      _isFetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Sorting function used by dropdown ----------
  void _sortApartments() {
    if (apartments.isEmpty) return;

    if (sortOption == 'Price') {
      apartments.sort((a, b) {
        final pa = (a['priceValue'] as num?)?.toDouble() ?? 0.0;
        final pb = (b['priceValue'] as num?)?.toDouble() ?? 0.0;
        return pa.compareTo(pb); // ascending price
      });
    } else {
      // Date Posted (use created_at, newest first)
      apartments.sort((a, b) {
        final sa = (a['created_at'] ?? '').toString();
        final sb = (b['created_at'] ?? '').toString();
        final da = DateTime.tryParse(sa);
        final db = DateTime.tryParse(sb);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da); // newest first
      });
    }

    currentPage = 0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = (apartments.length / cardsPerPage).ceil();
    final startIndex = currentPage * cardsPerPage;
    final endIndex = (startIndex + cardsPerPage).clamp(0, apartments.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          "MY TIMELINE",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
      ),

      // ✅ Pull-to-refresh (same pattern as TOTALROOM.dart)
      body: RefreshIndicator(
        color: const Color(0xFF04354B),
        onRefresh: () async {
          await _refreshFromSupabase();
        },
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 240),
                  Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF04354B),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  // 🔵 FULL-WIDTH HEADER CARD
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
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
                        const Row(
                          children: [
                            Icon(
                              Icons.view_timeline_outlined,
                              size: 20,
                              color: Color(0xFF6B7280),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Manage your rooms timeline",
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildTopControls(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 🔵 Timeline content with side padding only
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: apartments.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    'No rooms yet. Tap Add to create one.',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                ...List.generate(endIndex - startIndex, (index) {
                                  final apartment = apartments[startIndex + index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16.0),
                                    child: _buildApartmentCard(
                                      startIndex + index,
                                      apartment,
                                    ),
                                  );
                                }),
                                _buildPagination(totalPages),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
      ),

      // ✅ Shared bottom nav: index 1 = Timeline
      bottomNavigationBar: const LandlordBottomNav(
        currentIndex: 1,
      ),
    );
  }

  // ---------- UI helpers ----------
  Widget _buildTopControls() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
              ),
            ),
            value: sortOption,
            items: const [
              DropdownMenuItem(
                value: 'Date Posted',
                child: Text("Sort by Date Posted"),
              ),
              DropdownMenuItem(value: 'Price', child: Text("Sort by Price")),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                sortOption = value;
                _sortApartments(); // apply sort when dropdown changes
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF04354B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (context) => const Addroom()),
              );
              if (result == null) return;
              await _refreshFromSupabase();
              if (!mounted) return;
              const snackBar = SnackBar(content: Text('Room saved'));
              ScaffoldMessenger.of(context).showSnackBar(snackBar);
            },
            icon: const Icon(Icons.add),
            label: const Text(
              "Add Room",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // STATUS pill → Option A, appbar color, rounded rectangle
  Widget _buildStatusPill(String label) {
    const Color appBarColor = Color(0xFF04354B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: appBarColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // DELETE pill → Option A, red, rounded rectangle
  Widget _buildDeletePill(
    BuildContext context,
    Map<String, dynamic> apartment,
  ) {
    final supabase = Supabase.instance.client;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text("Confirm Delete"),
            content: const Text(
              "Are you sure you want to delete this apartment?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () async {
                  await supabase.from('rooms').delete().eq('id', apartment['id']);
                  await _refreshFromSupabase();
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text(
                  "Delete",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: const Text(
          "Delete",
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildApartmentCard(int index, Map<String, dynamic> apartment) {
    // Adjust this color if your Apartment cards use a different one.
    const cardColor = Color(0xFFD7E0E6);
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);

    final String status = (apartment['status'] ?? 'pending').toString();

    Color statusColor;
    if (status == 'published') {
      statusColor = const Color(0xFF16A34A); // green
    } else if (status == 'pending') {
      statusColor = const Color(0xFFF97316); // orange
    } else if (status == 'rejected') {
      statusColor = const Color(0xFFDC2626); // red
    } else {
      statusColor = const Color(0xFF6B7280); // gray
    }

    final String? imageUrl = apartment['imageUrl'] as String?;
    final Uint8List? imageBytes = apartment['imageBytes'] as Uint8List?;

    void openTour() {
      final roomId = apartment['id'] as String;
      final titleHint = (apartment['title'] ?? '').toString();
      final addressHint = (apartment['location'] ?? '').toString();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LTour(
            initialIndex: 0,
            roomId: roomId,
            titleHint: titleHint.isEmpty ? null : titleHint,
            addressHint: addressHint.isEmpty ? null : addressHint,
          ),
        ),
      );
    }

    void openMap() {
      final roomId = apartment['id'] as String;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => Gmap(roomId: roomId)),
      );
    }

    Widget imageWidget;
    if (imageBytes != null) {
      imageWidget = GestureDetector(
        onTap: openTour,
        child: Image.memory(
          imageBytes,
          height: 170,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      imageWidget = GestureDetector(
        onTap: openTour,
        child: Image.network(
          imageUrl,
          height: 170,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else {
      imageWidget = GestureDetector(
        onTap: openTour,
        child: Container(
          height: 170,
          width: double.infinity,
          color: Colors.black26,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported, color: Colors.white70),
        ),
      );
    }

    final String title =
        (apartment['title'] ?? "Smart Finder Apartment").toString();
    final String price = (apartment['price'] ?? "0").toString();
    final String location =
        (apartment['location'] ?? "Unknown location").toString();

    final List<String> tags =
        (apartment['tags'] as List?)?.cast<String>() ?? const <String>[];

    String statusButtonText;
    if (status == 'published') {
      statusButtonText = "Published";
    } else if (status == 'pending') {
      statusButtonText = "Awaiting Approval";
    } else if (status == 'rejected') {
      statusButtonText = "Rejected";
    } else {
      statusButtonText = "Status: $status";
    }

    return GestureDetector(
      onTap: openTour,
      child: Card(
        color: cardColor,
        elevation: 3,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: imageWidget,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color.fromARGB(150, 0, 0, 0),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "₱$price / Month",
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location,
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: tags
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2FE),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(
                                  color: Color(0xFF0369A1),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (status != 'rejected') ...[
                        _buildStatusPill(statusButtonText),
                        const SizedBox(width: 8),
                      ],
                      _buildDeletePill(context, apartment),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Open Map',
                        onPressed: openMap,
                        icon: const Icon(
                          Icons.location_pin,
                          color: Color(0xFFEF4444),
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
    );
  }

  Widget _buildPagination(int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          IconButton(
            onPressed: currentPage > 0
                ? () {
                    setState(() {
                      currentPage--;
                      _scrollController.jumpTo(0);
                    });
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            color: Colors.black87,
          ),
          ...List.generate(totalPages, (index) {
            final isSelected = index == currentPage;
            return GestureDetector(
              onTap: () {
                setState(() {
                  currentPage = index;
                  _scrollController.jumpTo(0);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isSelected
                      ? const Color.fromARGB(255, 214, 214, 214)
                      : Colors.white,
                  boxShadow: isSelected
                      ? const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 4,
                            offset: Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  "${index + 1}",
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          IconButton(
            onPressed: currentPage < totalPages - 1
                ? () {
                    setState(() {
                      currentPage++;
                      _scrollController.jumpTo(0);
                    });
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
            color: Colors.black87,
          ),
        ],
      ),
    );
  }
}
