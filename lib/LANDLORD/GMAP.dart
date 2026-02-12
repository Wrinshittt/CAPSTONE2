// gmap.dart
// Landlord map (MapLibre + MapTiler) + real panorama strip (no dummy data).
// Clicking a thumbnail or "More Details" opens landlord tour (LTour).

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'dart:ui'
    as ui
    show
        PictureRecorder,
        Canvas,
        Paint,
        Path,
        ImageByteFormat,
        Image,
        PaintingStyle;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'APARTMENT.dart';
import 'Roominfo.dart';
import 'package:smart_finder/LANDLORD/TOUR.dart'
    show LTour; // landlord tour only
import 'package:smart_finder/LANDLORD/chatL.dart' show LandlordChatScreen;

class Gmap extends StatefulWidget {
  const Gmap({super.key, required this.roomId});
  final String roomId;

  @override
  State<Gmap> createState() => _GmapState();
}

class _GmapState extends State<Gmap> {
  // ───────── CONFIG ─────────
  static const String _mapTilerKey = 'dRFWpeKo0QTp5Fv4hdUM';
  static String get _styleUrl =>
      'https://api.maptiler.com/maps/streets/style.json?key=$_mapTilerKey';

  // ───────── SERVICES ─────────
  final SupabaseClient _sb = Supabase.instance.client;

  // ───────── MAP STATE ─────────
  MaplibreMapController? _controller;
  LatLng? _target; // landlord location
  Symbol? _pin;
  bool _customPinReady = false;
  bool _loadingMapData = true;

  // ───────── UI / INFO STATE ─────────
  String _title = 'Apartment';
  String _address = 'Address not provided';
  bool _loadingInfo = true;

  // Real panoramas (no dummy)
  final List<String> _imageUrls = [];
  bool _loadingImages = true;

  int _hoveredIndex = -1;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _bootstrapInfo(); // title/address (room level)
    _bootstrapMap(); // landlord address/latlng + pin
    _loadPanoramas(); // real room_images
  }

  // Load room-level display info (title/address fallback)
  Future<void> _bootstrapInfo() async {
    try {
      final row = await _sb
          .from('rooms')
          .select('apartment_name, location')
          .eq('id', widget.roomId)
          .maybeSingle();

      if (row != null) {
        final t = (row['apartment_name'] ?? '').toString().trim();
        final a = (row['location'] ?? '').toString().trim();
        if (!mounted) return;
        setState(() {
          if (t.isNotEmpty) _title = t;
          if (a.isNotEmpty) _address = a; // may be overridden by landlord addr
        });
      }
    } catch (_) {
      // keep defaults
    } finally {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  // Resolve landlord location/address similar to tgmap (current landlord)
  Future<void> _bootstrapMap() async {
    try {
      final me = _sb.auth.currentUser?.id;

      // Also load room as fallback
      final roomRow = await _sb
          .from('rooms')
          .select('location')
          .eq('id', widget.roomId)
          .maybeSingle();
      final String? roomLocationFallback = (roomRow?['location'] as String?)
          ?.trim();

      LatLng? pos;
      String? displayAddress;

      if (me != null) {
        final lp = await _sb
            .from('landlord_profile')
            .select('lat, lng, address')
            .eq('user_id', me)
            .maybeSingle();

        final double? lat = (lp?['lat'] as num?)?.toDouble();
        final double? lng = (lp?['lng'] as num?)?.toDouble();
        final String? laddr = (lp?['address'] as String?)?.trim();

        if (lat != null && lng != null) {
          pos = LatLng(lat, lng);
          displayAddress = (laddr?.isNotEmpty == true)
              ? laddr
              : (roomLocationFallback?.isNotEmpty == true
                    ? roomLocationFallback
                    : null);
        } else if (laddr != null && laddr.isNotEmpty) {
          pos = await _geocodePH(laddr);
          displayAddress = laddr;
        }
      }

      if (pos == null && (roomLocationFallback?.isNotEmpty ?? false)) {
        pos = await _geocodePH(roomLocationFallback!);
        displayAddress = roomLocationFallback;
      }

      pos ??= const LatLng(14.5995, 120.9842); // Manila
      displayAddress ??= _address;

      if (!mounted) return;
      setState(() {
        _target = pos!;
        _address = displayAddress!;
        _loadingMapData = false;
      });

      if (_controller != null) {
        await _centerAndPin(pos);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _target = const LatLng(14.5995, 120.9842);
        _loadingMapData = false;
      });
    }
  }

  // Load panoramas from Supabase (room_images)
  Future<void> _loadPanoramas() async {
    setState(() {
      _loadingImages = true;
      _imageUrls.clear();
    });
    try {
      final rows = await _sb
          .from('room_images')
          .select('image_url, storage_path, sort_order')
          .eq('room_id', widget.roomId)
          .order('sort_order', ascending: true);

      for (final r in (rows as List)) {
        final String? direct = (r['image_url'] as String?);
        final String? storage = (r['storage_path'] as String?);
        if (direct != null && direct.trim().isNotEmpty) {
          _imageUrls.add(direct);
        } else if (storage != null && storage.trim().isNotEmpty) {
          _imageUrls.add(_sb.storage.from('room-images').getPublicUrl(storage));
        }
      }
    } catch (_) {
      // ignore; just show "No panoramas"
    } finally {
      if (mounted) setState(() => _loadingImages = false);
    }
  }

  // Simple PH geocoder via MapTiler
  Future<LatLng?> _geocodePH(String query) async {
    final uri = Uri.parse(
      'https://api.maptiler.com/geocoding/${Uri.encodeComponent(query)}.json'
      '?key=$_mapTilerKey&country=PH&language=en',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body);
    final features = body['features'] as List? ?? [];
    if (features.isEmpty) return null;

    final center = (features.first['center'] as List?) ?? [];
    if (center.length < 2) return null;

    final lng = (center[0] as num).toDouble();
    final lat = (center[1] as num).toDouble();
    return LatLng(lat, lng);
  }

  // Runtime-generated transparent red pin (no asset)
  Future<Uint8List> _makeRedPinBytes({int size = 128}) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final w = size.toDouble(), h = size.toDouble();

    final pin = ui.Path();
    final cx = w / 2, cy = h * 0.4;
    final r = w * 0.22;

    pin.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    final tail = ui.Path()
      ..moveTo(cx - r * 0.75, cy + r * 0.4)
      ..quadraticBezierTo(cx, h * 0.98, cx + r * 0.75, cy + r * 0.4)
      ..close();
    pin.addPath(tail, Offset.zero);

    final fill = ui.Paint()..color = const Color(0xFFE53935);
    canvas.drawPath(pin, fill);

    final stroke = ui.Paint()
      ..color = const Color(0xFFB71C1C)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = size * 0.045;
    canvas.drawPath(pin, stroke);

    final dot = ui.Paint()..color = const Color(0xFF24343A);
    canvas.drawCircle(Offset(cx, cy), r * 0.45, dot);

    final pic = rec.endRecording();
    final img = await pic.toImage(size, size);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  Future<void> _centerAndPin(LatLng at) async {
    await _controller?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: at, zoom: 16)),
    );

    if (_pin != null) {
      await _controller!.removeSymbol(_pin!);
      _pin = null;
    }

    _pin = await _controller!.addSymbol(
      SymbolOptions(
        geometry: at,
        iconImage: _customPinReady ? 'custom-pin-red' : 'marker-stroked-15',
        iconSize: _customPinReady ? 0.95 : 1.7,
        iconOffset: const Offset(0, -0.75),
        draggable: false,
      ),
    );
  }

  // Landlord opens most recent conversation (unchanged logic)
  Future<void> _openChat() async {
    final me = _sb.auth.currentUser?.id;
    if (me == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    try {
      final conv = await _sb
          .from('conversations')
          .select('id, tenant_id')
          .eq('landlord_id', me)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (conv == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No conversations yet. A tenant must message you first.',
            ),
          ),
        );
        return;
      }

      final conversationId = conv['id'] as String;
      final tenantId = conv['tenant_id'] as String?;

      String peerName = 'Tenant';
      if (tenantId != null) {
        final profile = await _sb
            .from('tenant_profile')
            .select('full_name')
            .eq('user_id', tenantId)
            .maybeSingle();
        final users = await _sb
            .from('users')
            .select('full_name')
            .eq('id', tenantId)
            .maybeSingle();
        final fromProfile = (profile?['full_name'] ?? '').toString().trim();
        final fromUsers = (users?['full_name'] ?? '').toString().trim();
        peerName = fromProfile.isNotEmpty
            ? fromProfile
            : (fromUsers.isNotEmpty ? fromUsers : 'Tenant');
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LandlordChatScreen(
            conversationId: conversationId,
            peerName: peerName,
            peerImageAsset: 'assets/images/mykel.png',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
    }
  }

  // Reusable network image with smooth loading and error UI
  Widget _netThumb(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      // Smooth fade-in & progress
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                        (progress.expectedTotalBytes ?? 1)
                  : null,
              color: Colors.white,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) =>
          const Center(child: Icon(Icons.broken_image, color: Colors.white)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const double stripHeight = 116; // fixed—prevents stretch

    return Scaffold(
      backgroundColor: const Color(0xFF04395E),
      body: SafeArea(
        child: Column(
          children: [
            // ───── MAP ─────
            Expanded(
              child: Stack(
                children: [
                  if (_loadingMapData)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  else
                    MaplibreMap(
                      styleString: _styleUrl,
                      initialCameraPosition: CameraPosition(
                        target: _target ?? const LatLng(14.5995, 120.9842),
                        zoom: 12.5,
                      ),
                      onMapCreated: (ctl) async {
                        _controller = ctl;
                      },
                      onStyleLoadedCallback: () async {
                        try {
                          final gen = await _makeRedPinBytes(size: 128);
                          await _controller!.addImage('custom-pin-red', gen);
                          _customPinReady = true;
                        } catch (_) {
                          _customPinReady = false;
                        }
                        if (_target != null) {
                          await _centerAndPin(_target!);
                        }
                      },
                      compassEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      myLocationEnabled: false,
                    ),

                  // Back to Apartment
                  Positioned(
                    top: 12,
                    left: 12,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const Apartment()),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black54, width: 1.5),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ───── BOTTOM (scrollable if short screens) ─────
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // ── PANORAMA STRIP ──
                    Container(
                      color: const Color(0xFF5A7689),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: _loadingImages
                          ? const SizedBox(
                              height: 56,
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : (_imageUrls.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: Text(
                                      'No panoramas posted yet.',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  )
                                : SizedBox(
                                    height: stripHeight,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _imageUrls.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 12),
                                      itemBuilder: (_, i) {
                                        final url = _imageUrls[i];
                                        final isHovered = i == _hoveredIndex;
                                        final isSelected = i == _selectedIndex;

                                        void openTour() {
                                          if (!mounted) return;
                                          _selectedIndex =
                                              i; // avoid race setState
                                          Navigator.of(context).push(
                                            PageRouteBuilder(
                                              pageBuilder: (_, __, ___) =>
                                                  LTour(
                                                    initialIndex: i,
                                                    roomId: widget.roomId,
                                                    titleHint: _title,
                                                    addressHint: _address,
                                                  ),
                                              transitionsBuilder:
                                                  (c, a, __, child) =>
                                                      FadeTransition(
                                                        opacity: a,
                                                        child: child,
                                                      ),
                                            ),
                                          );
                                        }

                                        return MouseRegion(
                                          onEnter: (_) =>
                                              setState(() => _hoveredIndex = i),
                                          onExit: (_) => setState(
                                            () => _hoveredIndex = -1,
                                          ),
                                          child: GestureDetector(
                                            onTap: openTour,
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              width: 180,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color:
                                                      (isHovered || isSelected)
                                                      ? const Color.fromARGB(
                                                          255,
                                                          27,
                                                          70,
                                                          120,
                                                        )
                                                      : Colors.white24,
                                                  width: 3,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withOpacity(0.18),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 3),
                                                  ),
                                                ],
                                              ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(9),
                                                child: AspectRatio(
                                                  aspectRatio: 16 / 9,
                                                  child: _netThumb(url),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  )),
                    ),

                    // ── INFO + ACTIONS ──
                    Container(
                      color: const Color(0xFF5A7689),
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _loadingInfo ? 'Loading…' : _title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                color: Colors.white70,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _address,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF003049),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _openChat,
                                    child: const Text("Message Tenant"),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF003049),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: () {
                                      if (_imageUrls.isNotEmpty) {
                                        final i = _selectedIndex.clamp(
                                          0,
                                          _imageUrls.length - 1,
                                        );
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LTour(
                                              initialIndex: i,
                                              roomId: widget.roomId,
                                              titleHint: _title,
                                              addressHint: _address,
                                            ),
                                          ),
                                        );
                                      } else {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                Roominfo(roomId: widget.roomId),
                                          ),
                                        );
                                      }
                                    },
                                    child: const Text("More Details"),
                                  ),
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
            ),
          ],
        ),
      ),
    );
  }
}
