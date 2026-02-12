// TENANT/TOUR.dart
// UPDATED (full):
// ✅ Tenant "More Rooms" now navigates to the SAME RoomsList.dart page as LANDLORD/TOUR.dart (CODE 2)
// ✅ Landlord card now navigates to LANDLORD/profile.dart (Adminprofile) when tapped
// - Shows only when there are > 3 available rooms from the same landlord
// - Navigates to RoomsList.dart (same as CODE 2)
// - Keeps tenant chat logic + landlord real name + filtering + panorama logic + UI

// ignore_for_file: unused_import

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui show ImageFilter;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:panorama/panorama.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ✅ SAME as CODE 2 (landlord) - RoomsList navigation target
import 'package:smart_finder/RoomList.dart';

// ✅ NEW: navigate to landlord profile screen (CODE 2)
import 'package:smart_finder/LANDLORD/profile.dart';

import 'TROOMINFO.dart';
import 'CHAT.dart'; // tenant chat screen

/* ============================== LRU cache ============================== */

class _LruBytes {
  final int capacity;
  final _map = LinkedHashMap<int, Uint8List>();

  _LruBytes({this.capacity = 6});

  Uint8List? get(int k) {
    final v = _map.remove(k);
    if (v != null) _map[k] = v;
    return v;
  }

  void set(int k, Uint8List v) {
    if (_map.containsKey(k)) _map.remove(k);
    _map[k] = v;
    if (_map.length > capacity) {
      _map.remove(_map.keys.first);
    }
  }

  void clear() => _map.clear();
}

/* =============================== Worker =============================== */

class _NormalizeArgs {
  final Uint8List bytes;
  final int maxW;
  final int maxH;
  final int blurRadius;
  final int quality;

  _NormalizeArgs({
    required this.bytes,
    required this.maxW,
    required this.maxH,
    required this.blurRadius,
    required this.quality,
  });
}

Future<Uint8List> _normalize2to1Worker(_NormalizeArgs a) async {
  final src0 = img.decodeImage(a.bytes);
  if (src0 == null) throw Exception('Cannot decode image');

  final capped = img.copyResize(
    src0,
    width: src0.width > a.maxW ? a.maxW : src0.width,
    height: src0.height > a.maxH ? a.maxH : src0.height,
    interpolation: img.Interpolation.linear,
  );

  final w = capped.width, h = capped.height;
  final ratio = w / h;
  const eps = 0.01;

  if ((ratio - 2.0).abs() < eps) {
    return Uint8List.fromList(img.encodeJpg(capped, quality: a.quality));
  }

  late final int outW, outH;
  int dx = 0, dy = 0;

  if (ratio < 2.0) {
    outW = 2 * h;
    outH = h;
    dx = ((outW - w) / 2).round();
    dy = 0;
  } else {
    outW = w;
    outH = (w / 2).round();
    dx = 0;
    dy = ((outH - h) / 2).round();
  }

  final baseForBlur = img.copyResizeCropSquare(
    capped,
    size: math.min(outW, outH),
  );

  final blurred = img.gaussianBlur(
    img.copyResize(baseForBlur, width: outW, height: outH),
    radius: a.blurRadius,
  );

  img.compositeImage(blurred, capped, dstX: dx, dstY: dy);
  return Uint8List.fromList(img.encodeJpg(blurred, quality: a.quality));
}

/* ============================== Net utils ============================= */

final http.Client _http = http.Client();

Future<Uint8List> _fetchBytesWithRetry(
  String url, {
  Duration timeout = const Duration(seconds: 8),
  int retries = 1,
}) async {
  int attempts = 0;
  while (true) {
    attempts++;
    try {
      final resp = await _http.get(Uri.parse(url)).timeout(
            timeout,
            onTimeout: () => throw TimeoutException('Network timeout'),
          );
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return resp.bodyBytes;
      }
      throw Exception('HTTP ${resp.statusCode}');
    } catch (e) {
      if (attempts > 1 + retries) rethrow;
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }
}

/* ============================== Screen =============================== */

class Tour extends StatefulWidget {
  final int initialIndex;
  final String roomId;
  final String? titleHint;
  final String? addressHint;
  final num? monthlyHint;

  // chat-related fields (pass these when pushing Tour)
  final String conversationId;
  final String peerName;
  final String? peerAvatarUrl;
  final String? landlordPhone;

  const Tour({
    super.key,
    required this.initialIndex,
    required this.roomId,
    this.titleHint,
    this.addressHint,
    this.monthlyHint,
    required this.conversationId,
    required this.peerName,
    this.peerAvatarUrl,
    this.landlordPhone,
  });

  @override
  State<Tour> createState() => _TourState();
}

class _TourState extends State<Tour> with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  // ===== Match CODE 2 palette =====
  static const Color _bg = Color(0xFFF3F4F6);
  static const Color _brand = Color(0xFF04354B);
  static const Color _panel = Colors.white;
  static const Color _textPrimary = Color(0xFF111827);
  static const Color _textSecondary = Color(0xFF6B7280);
  static const Color _border = Color(0xFFD1D5DB);
  static const Color _chipBg = Color(0xFFE0F2FE);
  static const Color _chipText = Color(0xFF0369A1);
  static const Color _accent = Color(0xFF2563EB);

  // Images + hotspots
  final List<_NetImage> _images = [];
  final Map<String, int> _indexById = {};
  final Map<int, List<_HS>> _hotspotsByIndex = {};

  // Cache
  final _LruBytes _panoCache = _LruBytes(capacity: 6);
  Uint8List? _currentBytes;

  // UI state
  bool _loading = true;
  String? _error;
  bool _imageLoading = false;
  String? _imageError;

  // Room info
  String? _title, _address, _status, _desc;
  num? _monthly, _advance;
  int? _floor;

  // Landlord preview (tenant should see name)
  String? _landlordId;
  bool _landlordPreviewLoading = false;
  String? _landlordPreviewError;
  String? _landlordAvatarUrl;
  String? _landlordDisplayName;
  String? _landlordEmail;
  bool _landlordVerified = false;

  // More from this landlord (tenant)
  bool _sameLandlordLoading = false;
  String? _sameLandlordError;
  final List<Map<String, dynamic>> _sameLandlordRooms = [];

  // Window: 210° calm span, hard stops, slight eps
  static const double kTotalSpanDeg = 210.0;
  static const double _edgeEpsDeg = 0.6;
  double get _minYawDeg => -kTotalSpanDeg / 2 + _edgeEpsDeg;
  double get _maxYawDeg => kTotalSpanDeg / 2 - _edgeEpsDeg;

  // Zoom (fixed)
  static const double kFixedZoom = 0.55;

  // Edge visuals
  static const double kEdgeFadeStartDeg = 10.0;
  static const double kEdgeFadeMaxOpacity = 0.85;
  static const double kEdgeBlurSigma = 10.0;

  // keep tenant: no vertical curve
  static const double kCurveMaxDeg = 0.0;
  static const double kCurvePower = 1.2;

  // Camera
  double _viewLonDeg = 0.0;
  double _viewLatDeg = 0.0;

  // Smooth pan target + ticker
  double _targetLonDeg = 0.0;
  late final Ticker _ticker;

  // Realtime
  RealtimeChannel? _chImages, _chHotspots, _chRooms;

  // Haptic flags
  bool _edgeBuzzedLeft = false, _edgeBuzzedRight = false;

  // Index
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = math.max(0, math.min(widget.initialIndex, 9999));
    _applyYaw(0);

    _ticker = createTicker((_) {
      final diff = (_targetLonDeg - _viewLonDeg);
      if (diff.abs() < 0.01) {
        _viewLonDeg = _targetLonDeg;
      } else {
        _viewLonDeg += diff * 0.18;
      }
      _viewLatDeg = _curvedLatitudeForYaw(_viewLonDeg);
      if (mounted) setState(() {});
    });
    _ticker.start();

    _bootstrap();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _chImages?.unsubscribe();
    _chHotspots?.unsubscribe();
    _chRooms?.unsubscribe();
    super.dispose();
  }

  /* ---------------------------- Realtime ---------------------------- */

  void _subscribeRealtime() {
    _chImages = _sb
        .channel('room_images_${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_images',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (_) => _reloadImagesAndMaybeResetIndex(),
        )
        .subscribe();

    _chHotspots = _sb
        .channel('hotspots_${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'hotspots',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (_) => _reloadHotspots(),
        )
        .subscribe();

    _chRooms = _sb
        .channel('rooms_${widget.roomId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rooms',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.roomId,
          ),
          callback: (_) async {
            await _reloadRoomInfo();
            await _reloadLandlordPreview();
            await _reloadSameLandlordRooms();
          },
        )
        .subscribe();
  }

  Future<void> _reloadImagesAndMaybeResetIndex() async {
    try {
      final imgs = await _sb
          .from('room_images')
          .select('id,image_url,sort_order,storage_path')
          .eq('room_id', widget.roomId)
          .order('sort_order', ascending: true);

      final list = (imgs as List);
      final newImages = <_NetImage>[
        for (final r in list)
          _NetImage(
            id: r['id'] as String,
            url: (() {
              final direct = (r['image_url'] as String?)?.trim();
              if (direct != null && direct.isNotEmpty) return direct;
              final sp = r['storage_path'] as String?;
              if (sp != null && sp.trim().isNotEmpty) {
                return _sb.storage.from('room-images').getPublicUrl(sp);
              }
              return '';
            })(),
          ),
      ];

      final changed = newImages.length != _images.length ||
          newImages.asMap().entries.any(
                (e) =>
                    _images.length <= e.key || _images[e.key].url != e.value.url,
              );

      if (!mounted) return;
      setState(() {
        _images
          ..clear()
          ..addAll(newImages);
        _indexById
          ..clear()
          ..addEntries(
            _images.asMap().entries.map((e) => MapEntry(e.value.id, e.key)),
          );
      });

      if (changed) {
        _panoCache.clear();
        if (_images.isNotEmpty) {
          final nextIndex =
              math.max(0, math.min(_currentIndex, _images.length - 1));
          await _preparePano(nextIndex);
        } else {
          setState(() {
            _currentBytes = null;
            _imageError = 'No panoramas uploaded.';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _reloadHotspots() async {
    try {
      _hotspotsByIndex.clear();
      if (_images.isEmpty) return;

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

        final lonAny = r['dx'] as num?;
        final latAny = r['dy'] as num?;
        if (lonAny == null || latAny == null) continue;

        double lonDeg;
        if (lonAny >= 0 && lonAny <= 1) {
          lonDeg = (lonAny.toDouble() * 360.0) - 180.0;
        } else if (lonAny.abs() <= math.pi + 1e-6) {
          lonDeg = lonAny.toDouble() * 180.0 / math.pi;
        } else {
          lonDeg = lonAny.toDouble();
        }

        double latDeg;
        if (latAny >= 0 && latAny <= 1) {
          latDeg = (latAny.toDouble() - 0.5) * 180.0;
        } else if (latAny.abs() <= (math.pi / 2 + 1e-6)) {
          latDeg = latAny.toDouble() * 180.0 / math.pi;
        } else {
          latDeg = latAny.toDouble();
        }
        latDeg = latDeg.clamp(-90.0, 90.0);

        final hs = _HS(
          longitudeDeg: lonDeg,
          latitudeDeg: latDeg,
          targetIndex: tgtIdx,
          label: (r['label'] as String?)?.trim(),
        );
        _hotspotsByIndex.putIfAbsent(srcIdx, () => []).add(hs);
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _reloadRoomInfo() async {
    try {
      final room = await _sb
          .from('rooms')
          .select(
            'apartment_name, location, monthly_payment, advance_deposit, '
            'status, floor_number, description, availability_status, landlord_id',
          )
          .eq('id', widget.roomId)
          .maybeSingle();

      String? newLandlordId;
      if (room != null) newLandlordId = room['landlord_id']?.toString();

      if (room != null && mounted) {
        setState(() {
          _title = (room['apartment_name'] as String?)?.trim();
          _address = (room['location'] as String?)?.trim();
          _monthly = room['monthly_payment'] as num?;
          _advance = room['advance_deposit'] as num?;
          _status = (room['availability_status'] as String?) ??
              (room['status'] as String?);
          _floor = (room['floor_number'] as int?);
          _desc = (room['description'] as String?);
          _landlordId = newLandlordId;
        });
      }

      await _reloadLandlordPreview();
      await _reloadSameLandlordRooms();
    } catch (_) {}
  }

  /* --------------------- Landlord preview (REAL name) --------------------- */

  Future<void> _reloadLandlordPreview() async {
    final lid = (_landlordId ?? '').trim();
    if (lid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _landlordPreviewLoading = false;
        _landlordPreviewError = null;
        _landlordAvatarUrl = null;
        _landlordDisplayName = null;
        _landlordEmail = null;
        _landlordVerified = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _landlordPreviewLoading = true;
      _landlordPreviewError = null;
    });

    try {
      String? avatarUrl;
      try {
        avatarUrl = _sb.storage.from('avatars').getPublicUrl('$lid.jpg');
      } catch (_) {}

      String? firstName;
      String? lastName;
      dynamic rawIsApproved;

      // Prefer landlord_profile
      try {
        final landlordProfile = await _sb
            .from('landlord_profile')
            .select('first_name, last_name, is_approved')
            .eq('user_id', lid)
            .maybeSingle();

        if (landlordProfile != null) {
          firstName = landlordProfile['first_name'] as String?;
          lastName = landlordProfile['last_name'] as String?;
          rawIsApproved = landlordProfile['is_approved'];
        }
      } catch (_) {}

      // Fallback to users table
      String? email;
      String? fullName;
      try {
        final usersRow = await _sb
            .from('users')
            .select('first_name, last_name, full_name, email')
            .eq('id', lid)
            .maybeSingle();

        if (usersRow != null) {
          email = usersRow['email'] as String?;
          firstName ??= usersRow['first_name'] as String?;
          lastName ??= usersRow['last_name'] as String?;
          fullName = usersRow['full_name'] as String?;
        }
      } catch (_) {}

      String displayName;
      final f = (firstName ?? '').trim();
      final l = (lastName ?? '').trim();
      if (f.isNotEmpty || l.isNotEmpty) {
        displayName = ('$f $l').trim();
      } else if ((fullName ?? '').trim().isNotEmpty) {
        displayName = fullName!.trim();
      } else if (widget.peerName.trim().isNotEmpty) {
        displayName = widget.peerName.trim();
      } else {
        displayName = 'Landlord';
      }

      bool verified = false;
      String? normalizedStatus;
      if (rawIsApproved is bool) {
        normalizedStatus = rawIsApproved ? 'approved' : 'rejected';
      } else if (rawIsApproved is num) {
        normalizedStatus = rawIsApproved == 1 ? 'approved' : 'rejected';
      } else if (rawIsApproved is String) {
        normalizedStatus = rawIsApproved.toLowerCase().trim();
      }
      if (normalizedStatus == 'approved' || normalizedStatus == 'true') {
        verified = true;
      }

      if (!mounted) return;
      setState(() {
        _landlordAvatarUrl =
            (avatarUrl != null && avatarUrl.trim().isNotEmpty) ? avatarUrl : null;
        _landlordDisplayName = displayName;
        _landlordEmail = (email != null && email.trim().isNotEmpty) ? email : null;
        _landlordVerified = verified;
        _landlordPreviewLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _landlordPreviewLoading = false;
        _landlordPreviewError = 'Could not load landlord profile.';
      });
    }
  }

  /* --------------------- More from this landlord --------------------- */

  Future<void> _reloadSameLandlordRooms() async {
    final lid = (_landlordId ?? '').trim();
    if (lid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _sameLandlordRooms.clear();
        _sameLandlordError = null;
        _sameLandlordLoading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _sameLandlordLoading = true;
      _sameLandlordError = null;
    });

    try {
      final rows = await _sb
          .from('rooms')
          .select(
            'id, apartment_name, location, monthly_payment, status, availability_status, created_at',
          )
          .eq('landlord_id', lid)
          .neq('id', widget.roomId)
          .order('created_at', ascending: false)
          .limit(6);

      final list = (rows as List? ?? const <dynamic>[]).cast<dynamic>();

      final filtered = <Map<String, dynamic>>[];
      for (final r in list) {
        if (r is! Map) continue;

        final av = (r['availability_status'] ?? '').toString().toLowerCase().trim();
        final st = (r['status'] ?? '').toString().toLowerCase().trim();

        final looksAvailable =
            av == 'available' || av == 'vacant' || av == 'open' || st == 'available';

        // Tenant should only see approved/published rooms
        final looksApproved = st == 'published' || st == 'approved';

        // explicitly exclude unapproved-ish values
        final looksUnapproved = st == 'pending' ||
            st == 'review' ||
            st == 'for review' ||
            st == 'for_review' ||
            st == 'unapproved' ||
            st == 'draft' ||
            st == 'rejected' ||
            st == 'declined' ||
            st == 'disabled' ||
            st == 'inactive';

        if (!looksUnapproved && looksApproved && (looksAvailable || av.isEmpty)) {
          filtered.add(Map<String, dynamic>.from(r));
        }
      }

      // Attach first image per room (smallest sort_order)
      if (filtered.isNotEmpty) {
        final ids = filtered
            .map((m) => (m['id'] ?? '').toString())
            .where((s) => s.trim().isNotEmpty)
            .toList();

        if (ids.isNotEmpty) {
          final quoted = ids.map((id) => '"$id"').join(',');
          final imgs = await _sb
              .from('room_images')
              .select('room_id, image_url, sort_order, storage_path')
              .filter('room_id', 'in', '($quoted)');

          final Map<String, Map<String, dynamic>> firstByRoom = {};
          for (final im in (imgs as List? ?? const <dynamic>[])) {
            if (im is! Map) continue;
            final rid = (im['room_id'] ?? '').toString();
            if (rid.isEmpty) continue;

            final so = (im['sort_order'] as int?) ?? 0;
            final current = firstByRoom[rid];
            if (current == null || so < ((current['sort_order'] as int?) ?? (1 << 30))) {
              firstByRoom[rid] = {
                'image_url': im['image_url'],
                'storage_path': im['storage_path'],
                'sort_order': so,
              };
            }
          }

          for (var i = 0; i < filtered.length; i++) {
            final rid = (filtered[i]['id'] ?? '').toString();
            final pick = firstByRoom[rid];

            String? url;
            if (pick != null) {
              final direct = (pick['image_url'] as String?)?.trim();
              if (direct != null && direct.isNotEmpty) {
                url = direct;
              } else {
                final sp = (pick['storage_path'] as String?)?.trim();
                if (sp != null && sp.isNotEmpty) {
                  url = _sb.storage.from('room-images').getPublicUrl(sp);
                }
              }
            }

            filtered[i] = {
              ...filtered[i],
              'imageUrl': url,
            };
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _sameLandlordRooms
          ..clear()
          ..addAll(filtered);
        _sameLandlordLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sameLandlordLoading = false;
        _sameLandlordError = 'Could not load other rooms.';
        _sameLandlordRooms.clear();
      });
    }
  }

  void _openOtherRoomAsTenant(String roomId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Tour(
          initialIndex: 0,
          roomId: roomId,
          titleHint: null,
          addressHint: null,
          monthlyHint: null,
          conversationId: '', // allow creation inside _onMessage
          peerName: (_landlordDisplayName ?? widget.peerName).trim().isEmpty
              ? 'Landlord'
              : (_landlordDisplayName ?? widget.peerName).trim(),
          peerAvatarUrl: _landlordAvatarUrl ?? widget.peerAvatarUrl,
          landlordPhone: widget.landlordPhone,
        ),
      ),
    );
  }

  // ✅ SAME as CODE 2: navigate to RoomsList.dart BUT PASS LANDLORD ID
  void _openRoomsList() {
    final lid = (_landlordId ?? '').trim();
    if (lid.isEmpty) {
      InfoToastModal.show(context, 'Landlord not found yet.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomsList(
          landlordId: lid,
          titleHint: 'More Rooms',
        ),
      ),
    );
  }

  // ✅ NEW: landlord card tap should navigate to landlord profile (CODE 2)
  void _openLandlordProfile() {
    final lid = (_landlordId ?? '').trim();
    if (lid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Landlord profile not available yet.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Adminprofile(lid),
      ),
    );
  }

  /* ---------------------------- Bootstrap ---------------------------- */

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
      _imageError = null;
    });

    try {
      await _reloadImagesAndMaybeResetIndex();
      await _reloadHotspots();
      await _reloadRoomInfo();
      await _reloadLandlordPreview();
      await _reloadSameLandlordRooms();
      setState(() => _loading = false);

      if (_images.isNotEmpty) {
        await _preparePano(_currentIndex);
      } else {
        setState(() => _imageError = 'No panoramas uploaded.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load tour: $e';
      });
    }
  }

  /* ---------------------- Normalize & Prepare ----------------------- */

  Widget _previewForUrl(String url) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12),
    );
  }

  Future<void> _preparePano(int index) async {
    if (!mounted) return;
    setState(() {
      _imageLoading = true;
      _imageError = null;
    });

    try {
      final cached = _panoCache.get(index);
      if (cached != null) {
        _currentBytes = cached;
      } else {
        final url = _images[index].url;
        if (url.isEmpty) throw Exception('Panorama URL is empty.');
        final raw = await _fetchBytesWithRetry(url);

        final bytes = await compute<_NormalizeArgs, Uint8List>(
          _normalize2to1Worker,
          _NormalizeArgs(
            bytes: raw,
            maxW: 2000,
            maxH: 1000,
            blurRadius: 10,
            quality: 88,
          ),
        );

        _panoCache.set(index, bytes);
        _currentBytes = bytes;
      }

      final centerYaw = (_minYawDeg + _maxYawDeg) / 2.0;
      _applyYaw(centerYaw);
      _targetLonDeg = centerYaw;

      if (mounted) setState(() => _imageLoading = false);
      _prefetchAround(index);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageError = 'Could not load panorama.';
        _imageLoading = false;
      });
    }
  }

  void _prefetchAround(int i) {
    final order = <int>[
      if (i + 1 < _images.length) i + 1,
      if (i - 1 >= 0) i - 1,
      if (i + 2 < _images.length) i + 2,
    ];
    for (final idx in order) {
      if (_panoCache.get(idx) != null) continue;
      final url = _images[idx].url;
      if (url.isEmpty) continue;
      unawaited(() async {
        try {
          final raw = await _fetchBytesWithRetry(
            url,
            timeout: const Duration(seconds: 6),
          );
          final bytes = await compute<_NormalizeArgs, Uint8List>(
            _normalize2to1Worker,
            _NormalizeArgs(
              bytes: raw,
              maxW: 2000,
              maxH: 1000,
              blurRadius: 10,
              quality: 88,
            ),
          );
          _panoCache.set(idx, bytes);
        } catch (_) {}
      }());
    }
  }

  Future<void> _goTo(int index) async {
    final clamped = math.max(0, math.min(index, _images.length - 1));
    if (!mounted) return;
    setState(() => _currentIndex = clamped);
    await _preparePano(clamped);
  }

  /* --------------------------- Camera --------------------------- */

  double _curvedLatitudeForYaw(double lonDeg) {
    if (kCurveMaxDeg == 0.0) return 0.0;
    final span = (_maxYawDeg - _minYawDeg);
    if (span <= 0) return 0.0;
    final t = ((lonDeg - _minYawDeg) / span) * 2.0 - 1.0;
    final absPow = math.pow(t.abs(), kCurvePower).toDouble();
    final factor = (1.0 - absPow).clamp(0.0, 1.0);
    return -kCurveMaxDeg * factor;
  }

  void _applyYaw(double lonDeg) {
    final clamped = lonDeg.clamp(_minYawDeg, _maxYawDeg).toDouble();
    _viewLonDeg = clamped;
    _viewLatDeg = _curvedLatitudeForYaw(clamped);
    _targetLonDeg = clamped;

    if (clamped <= _minYawDeg + 1e-3) {
      if (!_edgeBuzzedLeft) HapticFeedback.selectionClick();
      _edgeBuzzedLeft = true;
      _edgeBuzzedRight = false;
    } else if (clamped >= _maxYawDeg - 1e-3) {
      if (!_edgeBuzzedRight) HapticFeedback.selectionClick();
      _edgeBuzzedRight = true;
      _edgeBuzzedLeft = false;
    } else {
      _edgeBuzzedLeft = false;
      _edgeBuzzedRight = false;
    }
  }

  void _aimYaw(double lonDeg) {
    _targetLonDeg = lonDeg.clamp(_minYawDeg, _maxYawDeg).toDouble();
  }

  double _leftEdgeOpacity() {
    final d = (_viewLonDeg - _minYawDeg).clamp(0.0, kEdgeFadeStartDeg);
    final t = 1.0 - (d / kEdgeFadeStartDeg);
    return (t * kEdgeFadeMaxOpacity).clamp(0.0, kEdgeFadeMaxOpacity);
  }

  double _rightEdgeOpacity() {
    final d = (_maxYawDeg - _viewLonDeg).clamp(0.0, kEdgeFadeStartDeg);
    final t = 1.0 - (d / kEdgeFadeStartDeg);
    return (t * kEdgeFadeMaxOpacity).clamp(0.0, kEdgeFadeMaxOpacity);
  }

  void _openDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TenantRoomInfo(
          roomId: widget.roomId,
          titleHint: widget.titleHint ?? _title,
          addressHint: widget.addressHint ?? _address,
          monthlyHint: (widget.monthlyHint ?? _monthly)?.toDouble(),
        ),
      ),
    );
  }

  // Message button → ensure there is a tenant+landlord conversation,
  // then open ChatScreenTenant.
  Future<void> _onMessage() async {
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null || me.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be logged in to chat.')),
        );
        return;
      }

      // If a conversationId was already passed in, just use it.
      String convId = widget.conversationId.trim();

      if (convId.isEmpty) {
        // 1) Get the landlord for this room
        final roomRow = await _sb
            .from('rooms')
            .select('landlord_id')
            .eq('id', widget.roomId)
            .maybeSingle();

        if (roomRow == null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Room not found.')));
          return;
        }

        final landlordId = (roomRow['landlord_id'] as String?)?.trim() ?? '';
        if (landlordId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Landlord is not linked to this room yet.')),
          );
          return;
        }

        // 2) Check if a conversation already exists for this tenant+landlord
        final existingConv = await _sb
            .from('conversations')
            .select('id')
            .eq('tenant_id', me)
            .eq('landlord_id', landlordId)
            .maybeSingle();

        if (existingConv != null) {
          convId = existingConv['id'] as String;
        } else {
          // 3) Create a new conversation
          final inserted = await _sb
              .from('conversations')
              .insert({
                'tenant_id': me,
                'landlord_id': landlordId,
                if ((widget.landlordPhone ?? '').trim().isNotEmpty)
                  'other_party_phone': widget.landlordPhone!.trim(),
              })
              .select('id')
              .maybeSingle();

          if (inserted == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Could not create chat for this landlord.')),
            );
            return;
          }
          convId = inserted['id'] as String;
        }
      }

      if (convId.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat is not available for this room.')),
        );
        return;
      }

      final displayPeerName =
          (_landlordDisplayName ?? widget.peerName).trim().isEmpty
              ? 'Landlord'
              : (_landlordDisplayName ?? widget.peerName).trim();

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreenTenant(
            conversationId: convId,
            peerName: displayPeerName,
            peerAvatarUrl: _landlordAvatarUrl ?? widget.peerAvatarUrl,
            landlordPhone: widget.landlordPhone,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open chat: $e')));
    }
  }

  /* ----------------------------- UI helpers (CODE 2 style) ----------------------------- */

  Widget _heroNavIconOnly({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 34,
          color: Colors.white,
          shadows: [
            Shadow(
              blurRadius: 12,
              color: Colors.black.withOpacity(0.55),
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dotsIndicator() {
    final count = math.min(3, _images.length);
    if (count <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final isActive = i == (_currentIndex.clamp(0, count - 1));
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive ? _brand : _border,
            borderRadius: BorderRadius.circular(99),
          ),
        );
      }),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }

  // ✅ CHANGED: landlord card tap now opens landlord profile (Adminprofile)
  Widget _landlordPreviewCardTenant() {
    final lid = (_landlordId ?? '').trim();
    if (lid.isEmpty) {
      final fallbackName =
          widget.peerName.trim().isEmpty ? 'Landlord' : widget.peerName.trim();
      return InkWell(
        onTap: _openLandlordProfile, // ✅ was _onMessage
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE5E7EB),
                backgroundImage: (widget.peerAvatarUrl != null &&
                        widget.peerAvatarUrl!.trim().startsWith('http'))
                    ? NetworkImage(widget.peerAvatarUrl!.trim())
                    : null,
                child: (widget.peerAvatarUrl == null ||
                        !widget.peerAvatarUrl!.trim().startsWith('http'))
                    ? const Icon(Icons.person, color: _textSecondary, size: 22)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fallbackName,
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 14, color: _textSecondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'View profile',
                            style: const TextStyle(
                                color: _textSecondary, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, color: _textSecondary),
            ],
          ),
        ),
      );
    }

    if (_landlordPreviewLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
            ),
            SizedBox(width: 10),
            Text(
              'Loading landlord…',
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_landlordPreviewError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Text(
          _landlordPreviewError!,
          style: const TextStyle(color: _textSecondary, fontSize: 13),
        ),
      );
    }

    final name = (_landlordDisplayName ?? widget.peerName).trim().isEmpty
        ? 'Landlord'
        : (_landlordDisplayName ?? widget.peerName).trim();

    final subtitle = (_landlordEmail ?? '').trim().isNotEmpty
        ? _landlordEmail!.trim()
        : 'View profile';

    return InkWell(
      onTap: _openLandlordProfile, // ✅ was _onMessage
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFFE5E7EB),
              backgroundImage: (_landlordAvatarUrl != null &&
                      _landlordAvatarUrl!.startsWith('http'))
                  ? NetworkImage(_landlordAvatarUrl!)
                  : (widget.peerAvatarUrl != null &&
                          widget.peerAvatarUrl!.trim().startsWith('http'))
                      ? NetworkImage(widget.peerAvatarUrl!.trim())
                      : null,
              child: ((_landlordAvatarUrl == null ||
                          !_landlordAvatarUrl!.startsWith('http')) &&
                      (widget.peerAvatarUrl == null ||
                          !widget.peerAvatarUrl!.trim().startsWith('http')))
                  ? const Icon(Icons.person, color: _textSecondary, size: 22)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_landlordVerified) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: _chipBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: _chipText.withOpacity(0.30)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified,
                                  size: 14, color: _chipText),
                              SizedBox(width: 5),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  color: _chipText,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 14, color: _textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          subtitle,
                          style: const TextStyle(
                              color: _textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, color: _textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _sameLandlordSection() {
    if (_sameLandlordLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
            ),
            SizedBox(width: 10),
            Text(
              'Loading rooms…',
              style: TextStyle(color: _textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_sameLandlordError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Text(
          _sameLandlordError!,
          style: const TextStyle(color: _textSecondary, fontSize: 13),
        ),
      );
    }

    if (_sameLandlordRooms.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Text(
          'No other available rooms found.',
          style: TextStyle(color: _textSecondary, fontSize: 13),
        ),
      );
    }

    final roomsToShow = _sameLandlordRooms.take(3).toList();

    return Column(
      children: [
        for (final r in roomsToShow)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                final rid = (r['id'] ?? '').toString();
                if (rid.isEmpty) return;
                _openOtherRoomAsTenant(rid);
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 62,
                        height: 62,
                        child: (() {
                          final url = (r['imageUrl'] as String?)?.trim();
                          if (url == null || url.isEmpty) {
                            return Container(
                              color: const Color(0xFFE5E7EB),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported,
                                color: _textSecondary,
                                size: 18,
                              ),
                            );
                          }
                          return Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFFE5E7EB),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported,
                                color: _textSecondary,
                                size: 18,
                              ),
                            ),
                          );
                        })(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ((r['apartment_name'] ?? 'Room').toString())
                                    .trim()
                                    .isEmpty
                                ? 'Room'
                                : (r['apartment_name'] ?? 'Room').toString(),
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 14, color: _textSecondary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  (r['location'] ?? '—').toString(),
                                  style: const TextStyle(
                                      color: _textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (r['monthly_payment'] != null)
                            Text(
                              '₱${r['monthly_payment']} / month',
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _detailLine(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(
                color: _textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            v,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /* ----------------------------- Build ----------------------------- */

  @override
  Widget build(BuildContext context) {
    final leftOpacity = _leftEdgeOpacity();
    final rightOpacity = _rightEdgeOpacity();

    final heroHeight = math.min(
      420.0,
      MediaQuery.of(context).size.height * 0.43,
    );

    final rawName = (_title ?? widget.titleHint ?? '').trim();
    final displayName = rawName.isEmpty ? 'Smart-Finder Apartment' : rawName;

    final rawLocation = (_address ?? widget.addressHint ?? '').trim();
    final displayLocation = rawLocation.isEmpty ? '—' : rawLocation;

    // Match CODE 2 arrow rules:
    final showLeftArrow =
        _images.length > 1 && (_currentIndex == 1 || _currentIndex == 2);
    final isLastImage =
        _images.isNotEmpty && _currentIndex >= _images.length - 1;
    final showRightArrow = _images.length > 1 && !isLastImage;

    final availableRoomsCount = _sameLandlordRooms.length;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _brand))
            : (_error != null
                ? _ErrorBox(text: _error!)
                : SingleChildScrollView(
                    child: Column(
                      children: [
                        // ---------------- HERO PANORAMA ----------------
                        SizedBox(
                          height: heroHeight,
                          width: double.infinity,
                          child: ClipRRect(
                            borderRadius: BorderRadius.zero,
                            child: Stack(
                              children: [
                                if (_images.isNotEmpty)
                                  Positioned.fill(
                                    child: _previewForUrl(_images[_currentIndex].url),
                                  ),
                                Positioned.fill(
                                  child: _imageError != null
                                      ? _ErrorBox(text: _imageError!)
                                      : (_imageLoading || _currentBytes == null)
                                          ? const SizedBox()
                                          : Panorama(
                                              sensorControl: SensorControl.None,
                                              longitude: _viewLonDeg,
                                              latitude: _viewLatDeg,
                                              minLongitude: _minYawDeg,
                                              maxLongitude: _maxYawDeg,
                                              minLatitude: _viewLatDeg,
                                              maxLatitude: _viewLatDeg,
                                              minZoom: kFixedZoom,
                                              maxZoom: kFixedZoom,
                                              animSpeed: 0.0,
                                              onViewChanged: (lonDeg, latDeg, tiltDeg) {
                                                if (!lonDeg.isFinite) return;
                                                _aimYaw(lonDeg);
                                              },
                                              child: Image.memory(
                                                _currentBytes!,
                                                gaplessPlayback: true,
                                                filterQuality: FilterQuality.high,
                                              ),
                                              hotspots: [
                                                for (final hs
                                                    in _hotspotsByIndex[_currentIndex] ??
                                                        const <_HS>[])
                                                  Hotspot(
                                                    longitude: hs.longitudeDeg,
                                                    latitude: 0,
                                                    width: 84,
                                                    height: 84,
                                                    widget: GestureDetector(
                                                      behavior: HitTestBehavior.opaque,
                                                      onTap: () => _goTo(hs.targetIndex),
                                                      child: Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          if ((hs.label ?? '').isNotEmpty)
                                                            Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                horizontal: 10,
                                                                vertical: 6,
                                                              ),
                                                              margin: const EdgeInsets.only(
                                                                  bottom: 8),
                                                              decoration: BoxDecoration(
                                                                color: Colors.black54,
                                                                borderRadius:
                                                                    BorderRadius.circular(10),
                                                              ),
                                                              child: Text(
                                                                hs.label!,
                                                                style: const TextStyle(
                                                                  color: Colors.white,
                                                                  fontSize: 13,
                                                                  fontWeight: FontWeight.w700,
                                                                ),
                                                              ),
                                                            ),
                                                          const Icon(
                                                            Icons.radio_button_checked,
                                                            color: Colors.redAccent,
                                                            size: 34,
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                ),

                                // Edge visuals (“force field”)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 56,
                                          child: AnimatedOpacity(
                                            opacity: leftOpacity,
                                            duration: const Duration(milliseconds: 80),
                                            child: ClipRect(
                                              child: BackdropFilter(
                                                filter: ui.ImageFilter.blur(
                                                  sigmaX: kEdgeBlurSigma,
                                                  sigmaY: kEdgeBlurSigma,
                                                ),
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.centerLeft,
                                                      end: Alignment.centerRight,
                                                      colors: [
                                                        Colors.black54,
                                                        Colors.transparent,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const Expanded(child: SizedBox()),
                                        SizedBox(
                                          width: 56,
                                          child: AnimatedOpacity(
                                            opacity: rightOpacity,
                                            duration: const Duration(milliseconds: 80),
                                            child: ClipRect(
                                              child: BackdropFilter(
                                                filter: ui.ImageFilter.blur(
                                                  sigmaX: kEdgeBlurSigma,
                                                  sigmaY: kEdgeBlurSigma,
                                                ),
                                                child: Container(
                                                  decoration: const BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.centerRight,
                                                      end: Alignment.centerLeft,
                                                      colors: [
                                                        Colors.black54,
                                                        Colors.transparent,
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Back button (CODE 2 style)
                                Positioned(
                                  top: 10,
                                  left: 10,
                                  child: GestureDetector(
                                    onTap: () => Navigator.pop(context),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: const [
                                          BoxShadow(
                                            blurRadius: 14,
                                            offset: Offset(0, 6),
                                            color: Color.fromARGB(35, 0, 0, 0),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.arrow_back,
                                        color: _brand,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),

                                if (showLeftArrow)
                                  Positioned(
                                    left: 12,
                                    top: heroHeight * 0.45,
                                    child: _heroNavIconOnly(
                                      icon: Icons.arrow_back_ios_new,
                                      onTap: () {
                                        final next = (_currentIndex - 1)
                                            .clamp(0, _images.length - 1);
                                        _goTo(next);
                                      },
                                    ),
                                  ),

                                if (showRightArrow)
                                  Positioned(
                                    right: 12,
                                    top: heroHeight * 0.45,
                                    child: _heroNavIconOnly(
                                      icon: Icons.arrow_forward_ios,
                                      onTap: () {
                                        final next = (_currentIndex + 1)
                                            .clamp(0, _images.length - 1);
                                        _goTo(next);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        _dotsIndicator(),
                        const SizedBox(height: 10),

                        // ---------------- INFO PANEL ----------------
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(22),
                              topRight: Radius.circular(22),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        displayName,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: _textPrimary,
                                          height: 1.12,
                                          letterSpacing: -0.2,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        displayLocation,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: _textSecondary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          height: 1.25,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 16),
                                Divider(color: _border.withOpacity(.9)),
                                const SizedBox(height: 12),

                                // Landlord (tenant view) - ✅ now opens profile
                                _sectionTitle('Landlord'),
                                const SizedBox(height: 10),
                                _landlordPreviewCardTenant(),

                                const SizedBox(height: 14),

                                // Description
                                _sectionTitle('Description'),
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _bg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Text(
                                    (_desc ?? '').isEmpty
                                        ? 'No description provided.'
                                        : _desc!,
                                    style: const TextStyle(
                                      color: _textPrimary,
                                      fontSize: 13,
                                      height: 1.35,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // Hotspots
                                if ((_hotspotsByIndex[_currentIndex] ??
                                        const <_HS>[])
                                    .isNotEmpty) ...[
                                  _sectionTitle('Hotspots'),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      for (final h
                                          in _hotspotsByIndex[_currentIndex] ??
                                              const <_HS>[])
                                        InkWell(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          onTap: () => _goTo(h.targetIndex),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                            decoration: BoxDecoration(
                                              color: _chipBg,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                  color: _chipText
                                                      .withOpacity(0.25)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(Icons.place,
                                                    size: 18,
                                                    color: _chipText),
                                                const SizedBox(width: 8),
                                                Text(
                                                  h.label ??
                                                      'View ${h.targetIndex + 1}',
                                                  style: const TextStyle(
                                                    color: _chipText,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],

                                // Details
                                _sectionTitle('Details'),
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: _bg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: _border),
                                  ),
                                  child: Column(
                                    children: [
                                      if ((_monthly ?? widget.monthlyHint) != null)
                                        _detailLine('Monthly',
                                            '₱${_monthly ?? widget.monthlyHint}'),
                                      if (_advance != null)
                                        _detailLine('Advance', '₱$_advance'),
                                      if (_floor != null)
                                        _detailLine('Floor', '$_floor'),
                                      if ((_status ?? '').trim().isNotEmpty)
                                        _detailLine('Status', _status!.trim()),
                                      if ((_monthly ?? widget.monthlyHint) ==
                                              null &&
                                          _advance == null &&
                                          _floor == null &&
                                          (_status ?? '').trim().isEmpty)
                                        const Text(
                                          'No details available.',
                                          style: TextStyle(
                                              color: _textSecondary,
                                              fontSize: 13),
                                        ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 14),

                                // More from this landlord + count chip
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        'More from this landlord',
                                        style: TextStyle(
                                          color: _textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _chipBg,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                        border: Border.all(
                                            color: _chipText.withOpacity(0.25)),
                                      ),
                                      child: Text(
                                        _sameLandlordLoading
                                            ? '…'
                                            : '$availableRoomsCount available',
                                        style: const TextStyle(
                                          color: _chipText,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),
                                _sameLandlordSection(),

                                // ✅ Tenant "More Rooms" (same navigation target as CODE 2)
                                if (availableRoomsCount > 3) ...[
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: _openRoomsList,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: _chipBg.withOpacity(0.55),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                              color: _chipText.withOpacity(0.18)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'More Rooms',
                                              style: TextStyle(
                                                color: _accent,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w900,
                                                decoration:
                                                    TextDecoration.underline,
                                                decorationThickness: 1.2,
                                              ),
                                            ),
                                            SizedBox(width: 6),
                                            Icon(Icons.open_in_new,
                                                size: 16, color: _accent),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 18),

                                // Bottom actions (tenant keeps Message)
                                SafeArea(
                                  top: false,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 4, 0, 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: SizedBox(
                                            height: 52,
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _brand,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                elevation: 2,
                                              ),
                                              onPressed: _onMessage,
                                              icon: const Icon(Icons.sms),
                                              label: const Text(
                                                'Message',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w800),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: SizedBox(
                                            height: 52,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _brand,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                elevation: 2,
                                              ),
                                              onPressed: _openDetails,
                                              child: const Text(
                                                'View full room info',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w800),
                                              ),
                                            ),
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
                      ],
                    ),
                  )),
      ),
    );
  }
}

/* ============================== Widgets ============================== */

class _ErrorBox extends StatelessWidget {
  final String text;
  const _ErrorBox({required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          text,
          style: const TextStyle(color: Color(0xFF6B7280)),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/* =============================== Models ============================== */

class _NetImage {
  final String id;
  final String url;
  _NetImage({required this.id, required this.url});
}

class _HS {
  final double longitudeDeg;
  final double latitudeDeg;
  final int targetIndex;
  final String? label;
  _HS({
    required this.longitudeDeg,
    required this.latitudeDeg,
    required this.targetIndex,
    this.label,
  });
}
