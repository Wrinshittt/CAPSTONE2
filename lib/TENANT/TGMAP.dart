// TENANT/TGMAP.dart
// MapLibre + MapTiler. Pins landlord location only (non-interactive).

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
        PaintingStyle,
        Rect;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'TAPARTMENT.dart';
import 'TROOMINFO.dart';
import 'CHAT.dart' show ChatScreenTenant;
import 'package:smart_finder/services/chat_service.dart';

class TenantGmap extends StatefulWidget {
  final String roomId;
  final String? titleHint;
  final String? addressHint; // last-resort fallback only
  final double? monthlyHint;

  const TenantGmap({
    super.key,
    required this.roomId,
    this.titleHint,
    this.addressHint,
    this.monthlyHint,
  });

  @override
  State<TenantGmap> createState() => _TenantGmapState();
}

class _TenantGmapState extends State<TenantGmap> {
  // ── CONFIG ──
  static const String _mapTilerKey = 'dRFWpeKo0QTp5Fv4hdUM';
  static String get _styleUrl =>
      'https://api.maptiler.com/maps/streets/style.json?key=$_mapTilerKey';

  // ── SERVICES ──
  final SupabaseClient _sb = Supabase.instance.client;
  late final ChatService _chat = ChatService(_sb);

  // ── MAP STATE ──
  MaplibreMapController? _controller;
  LatLng? _target;
  Symbol? _pin;
  bool _loading = true;

  // ── UI STATE ──
  bool _startingChat = false;
  String? _resolvedAddress;
  bool _customPinReady = false;

  // landlord info for chat header
  String? _landlordId;
  String? _landlordName;
  String? _landlordAvatarUrl; // from avatars bucket (jpg/png)

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Read the room → landlord id & textual location fallback
      final roomRow = await _sb
          .from('rooms')
          .select('landlord_id, location')
          .eq('id', widget.roomId)
          .maybeSingle();

      _landlordId = roomRow?['landlord_id']?.toString();
      final String? roomLocationFallback = roomRow?['location']
          ?.toString()
          .trim();

      LatLng? pos;
      String? addrForDisplay;

      if (_landlordId != null && _landlordId!.isNotEmpty) {
        // Landlord location precedence: landlord_profile(lat/lng) → geocode landlord address
        final lp = await _sb
            .from('landlord_profile')
            .select('lat, lng, address')
            .eq('user_id', _landlordId!)
            .maybeSingle();

        final double? lat = (lp?['lat'] as num?)?.toDouble();
        final double? lng = (lp?['lng'] as num?)?.toDouble();
        final String? laddr = lp?['address']?.toString().trim();

        if (lat != null && lng != null) {
          pos = LatLng(lat, lng);
          addrForDisplay = (laddr != null && laddr.isNotEmpty)
              ? laddr
              : roomLocationFallback;
        } else if (laddr != null && laddr.isNotEmpty) {
          pos = await _geocodePH(laddr);
          addrForDisplay = laddr;
        }

        // Landlord display name (users table – NO avatar_url column needed)
        final user = await _sb
            .from('users')
            .select('full_name')
            .eq('id', _landlordId!)
            .maybeSingle();
        _landlordName = (user?['full_name'] as String?)?.trim();

        // Avatar: build from public storage bucket `avatars` → <userId>.jpg/.png
        final storage = _sb.storage.from('avatars');
        final jpg = storage.getPublicUrl('$_landlordId.jpg');
        final png = storage.getPublicUrl('$_landlordId.png');
        // Prefer jpg; you can flip the order if you mainly upload png
        _landlordAvatarUrl = jpg;
      }

      // Fallback to room textual location if needed
      if (pos == null && (roomLocationFallback?.isNotEmpty ?? false)) {
        pos = await _geocodePH(roomLocationFallback!);
        addrForDisplay = roomLocationFallback;
      }

      // Final fallbacks
      pos ??= const LatLng(14.5995, 120.9842); // Manila
      addrForDisplay ??= widget.addressHint ?? 'Location unavailable';

      setState(() {
        _target = pos;
        _resolvedAddress = addrForDisplay;
        _loading = false;
      });

      if (_controller != null) {
        await _centerAndPin(pos);
      }
    } catch (e) {
      setState(() {
        _target = const LatLng(14.5995, 120.9842);
        _resolvedAddress = widget.addressHint ?? 'Location unavailable';
        _loading = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Map init error: $e')));
    }
  }

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

    final first = features.first;
    final center = (first['center'] as List?) ?? [];
    if (center.length < 2) return null;

    final lng = (center[0] as num).toDouble();
    final lat = (center[1] as num).toDouble();
    return LatLng(lat, lng);
  }

  // ── draw a crisp transparent red pin (no asset) ──
  Future<Uint8List> _makeRedPinBytes({int size = 128}) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    final w = size.toDouble(), h = size.toDouble();

    final pinPath = ui.Path();
    final cx = w / 2, cy = h * 0.4;
    final r = w * 0.22;

    // top circle
    pinPath.addOval(ui.Rect.fromCircle(center: Offset(cx, cy), radius: r));

    // tail – correct 4-arg quadraticBezierTo(x1,y1,x2,y2)
    final tail = ui.Path()
      ..moveTo(cx - r * 0.75, cy + r * 0.4)
      ..quadraticBezierTo(
        cx, // control x
        h * 0.98, // control y
        cx + r * 0.75, // end x
        cy + r * 0.4, // end y
      )
      ..close();
    pinPath.addPath(tail, Offset.zero);

    // fill
    final fill = ui.Paint()..color = const Color(0xFFE53935);
    canvas.drawPath(pinPath, fill);

    // stroke
    final stroke = ui.Paint()
      ..color = const Color(0xFFB71C1C)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = size * 0.045;
    canvas.drawPath(pinPath, stroke);

    // inner dot
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

  Future<void> _messageLandlord() async {
    if (_startingChat) return;
    setState(() => _startingChat = true);
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Please log in first.')));
        return;
      }

      final result = await _chat.startChatFromRoom(
        roomId: widget.roomId,
        tenantId: me,
      );

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreenTenant(
            conversationId: result['conversationId']!,
            peerName: _landlordName ?? result['landlordName'] ?? 'Landlord',
            peerAvatarUrl: _landlordAvatarUrl, // from storage bucket
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.titleHint ?? 'Smart-Finder Apartment';
    final subtitle =
        _resolvedAddress ?? widget.addressHint ?? 'Address not provided';

    return Scaffold(
      backgroundColor: const Color(0xFF04395E),
      body: SafeArea(
        child: Column(
          children: [
            // ── MAP ──
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  if (_loading)
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
                          _customPinReady = false; // fallback sprite
                        }
                        if (_target != null) await _centerAndPin(_target!);
                      },
                      compassEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      myLocationEnabled: false,
                    ),

                  // Back button
                  Positioned(
                    top: 20,
                    left: 12,
                    child: GestureDetector(
                      onTap: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TenantApartment(),
                        ),
                      ),
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

            // ── INFO + ACTIONS ──
            Container(
              color: const Color(0xFF5A7689),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                          subtitle,
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(
                        width: 180,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF003049),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _startingChat ? null : _messageLandlord,
                          child: Text(
                            _startingChat ? 'Starting…' : 'Message Landlord',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 180,
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
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TenantRoomInfo(
                                  roomId: widget.roomId,
                                  titleHint: widget.titleHint,
                                  addressHint:
                                      _resolvedAddress ?? widget.addressHint,
                                  monthlyHint: widget.monthlyHint,
                                ),
                              ),
                            );
                          },
                          child: const Text('More Details'),
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
}
