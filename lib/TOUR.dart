// TOUR.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:panorama/panorama.dart'; // ✅ correct package
import 'package:supabase_flutter/supabase_flutter.dart';
import 'TENANT/TROOMINFO.dart';


class Tour extends StatefulWidget {
  final int initialIndex;
  final String roomId;
  final String? titleHint;
  final String? addressHint;
  final double? monthlyHint;

  const Tour({  
    super.key,
    required this.initialIndex,
    required this.roomId,
    this.titleHint,
    this.addressHint,
    this.monthlyHint,
  });

  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> {
  final _sb = Supabase.instance.client;

  final List<_NetImage> _images = [];
  final Map<String, int> _indexById = {};
  final Map<int, List<_HS>> _hotspotsByIndex = {};

  int _currentIndex = 0;
  bool _showHud = true;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _load();
  }

  double _degToRad(num d) => d.toDouble() * math.pi / 180.0;
  double _radToDeg(num r) => r.toDouble() * 180.0 / math.pi;
  double _normLon(double r) {
    while (r > math.pi) r -= 2 * math.pi;
    while (r < -math.pi) r += 2 * math.pi;
    return r;
  }

  double _clampLat(double r) => r.clamp(-math.pi / 2, math.pi / 2);

  double? _toRadiansAuto(num? v, {required bool isLat}) {
    if (v == null) return null;
    final d = v.toDouble();
    final radLimit = isLat ? (math.pi / 2 + 1e-6) : (math.pi + 1e-6);
    if (d.abs() <= radLimit) return isLat ? _clampLat(d) : _normLon(d);
    final r = _degToRad(d);
    return isLat ? _clampLat(r) : _normLon(r);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final imgs = await _sb
          .from('room_images')
          .select('id,image_url,sort_order')
          .eq('room_id', widget.roomId)
          .order('sort_order', ascending: true);

      _images
        ..clear()
        ..addAll([
          for (final r in (imgs as List))
            _NetImage(
              id: r['id'] as String,
              url: (r['image_url'] as String?)?.trim() ?? '',
            ),
        ]);

      _indexById
        ..clear()
        ..addEntries(
          _images.asMap().entries.map((e) => MapEntry(e.value.id, e.key)),
        );

      _hotspotsByIndex.clear();
      if (_images.isNotEmpty) {
        final hsRows = await _sb
            .from('hotspots')
            .select('source_image_id,target_image_id,dx,dy,label')
            .eq('room_id', widget.roomId);

        for (final r in (hsRows as List)) {
          final srcId = r['source_image_id'] as String?;
          final tgtId = r['target_image_id'] as String?;
          if (srcId == null || tgtId == null) continue;

          final srcIdx = _indexById[srcId];
          final tgtIdx = _indexById[tgtId];
          if (srcIdx == null || tgtIdx == null) continue;

          final lon = _toRadiansAuto(r['dx'] as num?, isLat: false);
          final lat = _toRadiansAuto(r['dy'] as num?, isLat: true);
          if (lon == null || lat == null) continue;

          final hs = _HS(
            longitude: _normLon(lon),
            latitude: _clampLat(lat),
            targetIndex: tgtIdx,
            label: r['label'] as String?,
          );
          _hotspotsByIndex.putIfAbsent(srcIdx, () => []).add(hs);
        }
      }

      if (_hotspotsByIndex.isEmpty && _images.length >= 2) {
        for (int i = 0; i < _images.length; i++) {
          final next = (i + 1) % _images.length;
          _hotspotsByIndex[i] = [
            _HS(
              longitude: 0.0,
              latitude: 0.0,
              targetIndex: next,
              label: 'Go to ${next + 1}',
            ),
          ];
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load tour: $e';
      });
    }
  }

  void _goTo(int index) {
    setState(() => _currentIndex = index.clamp(0, _images.length - 1));
  }

  void _openDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TenantRoomInfo(
          roomId: widget.roomId,
          titleHint: widget.titleHint,
          addressHint: widget.addressHint,
          monthlyHint: widget.monthlyHint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A3D62),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : (_error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Stack(
                            children: [
                              // Panorama with hotspots
                              Positioned.fill(
                                child: Panorama(
                                  sensorControl: SensorControl.Orientation,
                                  animSpeed: 0.5,
                                  onTap: (lon, lat, tilt) => _openDetails(),
                                  child: _images[_currentIndex].url.isEmpty
                                      ? Image.asset(
                                          'assets/images/roompano.png',
                                          fit: BoxFit.cover,
                                        )
                                      : Image.network(
                                          _images[_currentIndex].url,
                                          fit: BoxFit.cover,
                                        ),
                                  hotspots: [
                                    for (final hs
                                        in _hotspotsByIndex[_currentIndex] ??
                                            const <_HS>[])
                                      Hotspot(
                                        longitude: _radToDeg(hs.longitude),
                                        latitude: _radToDeg(hs.latitude),
                                        width: 60,
                                        height: 60,
                                        widget: GestureDetector(
                                          onDoubleTap: () =>
                                              _goTo(hs.targetIndex),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if ((hs.label ?? '').isNotEmpty)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  margin: const EdgeInsets.only(
                                                    bottom: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black54,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    hs.label!,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                              const Icon(
                                                Icons.place,
                                                color: Colors.redAccent,
                                                size: 40,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              // Back and HUD
                              Positioned(
                                top: 20,
                                left: 12,
                                child: GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(8),
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

                        // Bottom info and controls
                        Container(
                          color: const Color(0xFF5A7689),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((_hotspotsByIndex[_currentIndex] ?? const [])
                                  .isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    for (final h
                                        in _hotspotsByIndex[_currentIndex]!)
                                      ActionChip(
                                        onPressed: () => _goTo(h.targetIndex),
                                        avatar: const Icon(
                                          Icons.place,
                                          size: 18,
                                        ),
                                        label: Text(
                                          h.label ?? 'View ${h.targetIndex}',
                                        ),
                                      ),
                                  ],
                                ),
                              const SizedBox(height: 12),
                              Text(
                                widget.titleHint ?? "Apartment",
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
                                  Text(
                                    widget.addressHint ?? "—",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    )),
      ),
    );
  }
}

/* ---------- helpers ---------- */

class _NetImage {
  final String id;
  final String url;
  _NetImage({required this.id, required this.url});
}

class _HS {
  final double longitude;
  final double latitude;
  final int targetIndex;
  final String? label;
  _HS({
    required this.longitude,
    required this.latitude,
    required this.targetIndex,
    this.label,
  });
}
