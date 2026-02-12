import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/LANDLORD/TOUR.dart' show LTour;
import 'GMAP.dart'; // landlord map
import 'landlord_bottom_nav.dart'; // shared bottom nav

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
                  decorationColor: Colors.transparent,
                ),
              ),
            ),
          );
        },
      );
    });
  }
}

// ====== SCORING HELPERS (same as CODE 1) =====================================

// Matching Score = ( Σ wi * mi ) / ( Σ wi )
double computeMatchingScoreExact(
  Map<String, double> weights,
  Map<String, double> matchFlags,
) {
  double weightedSum = 0.0;
  double totalWeight = 0.0;

  weights.forEach((key, w) {
    final m = matchFlags[key] ?? 0.0;
    weightedSum += w * m;
    totalWeight += w;
  });

  if (totalWeight == 0.0) return 0.0;
  return weightedSum / totalWeight;
}

// Priority Score = Σ vj * fj
double computePriorityScore(
  Map<String, double> factorValues,
  Map<String, double> factorWeights,
) {
  double score = 0.0;

  factorValues.forEach((key, value) {
    double weight = factorWeights[key] ?? 0.0;
    score += value * weight;
  });

  return score;
}

// =============================================================================

class Apartment extends StatefulWidget {
  const Apartment({super.key});

  @override
  State<Apartment> createState() => _ApartmentState();
}

class _ApartmentState extends State<Apartment> {
  final _sb = Supabase.instance.client;

  RealtimeChannel? _roomsChannel;

  List<_RoomItem> _rooms = [];
  bool _loading = true;
  String? _error;

  int currentPage = 0;
  final int cardsPerPage = 10;
  final ScrollController _scrollController = ScrollController();

  final TextEditingController _searchCtrl = TextEditingController();

  final Map<String, bool> _favorite = {};
  final Map<String, bool> _bookmark = {};

  // heart counts per room (now driven by Supabase)
  final Map<String, int> _heartCounts = {};

  // When true, show threshold results otherwise full list
  bool _filtersApplied = false;

  // ✅ UPDATED: threshold for filtered view (70%)
  static const double kFinalScoreThreshold = 0.70;

  // ✅ threshold for "More Apartment" mode (50%)
  static const double kMoreApartmentThreshold = 0.50;

  // ✅ when true, show apartments with final score >= 50% (ONLY after clicking More Apartment)
  bool _showAllWithFinalScore = false;

  // ✅ Carousel state (recommendations)
  final PageController _recommendationPageCtrl =
      PageController(viewportFraction: 0.72);
  int _recommendationPage = 0;

  // ✅ LIVE TIMER TICKER (kept same as CODE 1)
  Timer? _ticker;
  DateTime _now = DateTime.now();

  // ---------------- Preferences (same as CODE 1) ----------------
  Map<String, String> preferences = {
    "Pet-Friendly": "No",
    "Open to all": "No",
    "Common CR": "No",
    "Occupation": "Others",

    // ✅ Smoking preference -> "Smoking Allowed"
    // Dropdown options: Ignored (default), Non-Smoker, Smoker Allowed
    "Smoking Allowed": "Ignored",

    "Location": "Any",
    "WiFi": "No",
    // Inclusions
    "Cabinet": "No",
    "Table": "No",
    "Fan": "No",
    "Aircon": "No",
    "Chair": "No",
  };

  // ✅ User-chosen importance only (no defaults)
  // Key exists only when the user explicitly sets it.
  Map<String, int> preferenceImportance = {};

  static const Map<int, String> importanceLabel = {
    1: "Low",
    2: "Medium",
    3: "Must-have",
  };

  final Map<String, IconData> icons = {
    "Pet-Friendly": Icons.pets,
    "Open to all": Icons.people,
    "Common CR": Icons.bathroom,
    "Occupation": Icons.work,
    "Smoking Allowed": Icons.smoking_rooms,
    "Location": Icons.location_on,
    "WiFi": Icons.wifi,
    // Inclusions
    "Cabinet": Icons.inventory_2,
    "Table": Icons.table_bar,
    "Fan": Icons.toys,
    "Aircon": Icons.ac_unit,
    "Chair": Icons.chair_alt,
  };

  final Map<String, List<String>> dropdownOptions = {
    "Pet-Friendly": ["Yes", "No"],
    "Open to all": ["Yes", "No"],
    "Common CR": ["Yes", "No"],
    "Occupation": [
      "Student Only",
      "Professional Only",
      "Working Professionals",
      "Others"
    ],
    "Smoking Allowed": ["Ignored", "Non-Smoker", "Smoker Allowed"],
    "Location": ["Near UM", "Near SM Eco", "Near Mapua", "Near DDC", "Any"],
    "WiFi": ["Yes", "No"],
    // Inclusions
    "Cabinet": ["Yes", "No"],
    "Table": ["Yes", "No"],
    "Fan": ["Yes", "No"],
    "Aircon": ["Yes", "No"],
    "Chair": ["Yes", "No"],
  };

  // ===== Pretty hashtag maps (same as CODE 1) =====
  static const Map<String, String> _prefPretty = {
    'pet-friendly': '#PetFriendly',
    'pet friendly': '#PetFriendly',
    'open to all': '#OpenToAll',
    'student only': '#StudentOnly',
    'working professionals': '#WorkingProfessionals',
    'professional only': '#WorkingProfessionals',
    // Smoking tags
    'non-smoker': '#NonSmoker',
    'non smoker': '#NonSmoker',
    'non-smoker only': '#NonSmoker',
    'non smoker only': '#NonSmoker',
    'smoker allowed': '#SmokerAllowed',
    'smoking allowed': '#SmokerAllowed',
    'near um': '#NearUM',
    'near sm eco': '#NearSMEco',
    'near mapua': '#NearMapua',
    'near ddc': '#NearDDC',
  };

  static const Map<String, String> _incPretty = {
    'wifi': '#WithWiFi',
    'with wifi': '#WithWiFi',
    'single bed': '#SingleBed',
    'double bed': '#DoubleBed',
    'bed': '#SingleBed',
    'own cr': '#OwnCR',
    'private cr': '#OwnCR',
    'common cr': '#CommonCR',
    'cabinet': '#Cabinet',
    'table': '#Table',
    'chair': '#Chair',
  };

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

  String _autoHash(String v) {
    final cleaned = v
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty
            ? ''
            : (w.substring(0, 1).toUpperCase() + w.substring(1).toLowerCase()))
        .join();
    return cleaned.isEmpty ? '' : '#$cleaned';
  }

  @override
  void initState() {
    super.initState();
    _fetchRooms();
    _subscribeRooms();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollController.dispose();
    _searchCtrl.dispose();
    _recommendationPageCtrl.dispose();
    _roomsChannel?.unsubscribe();
    super.dispose();
  }

  // ---------- Helpers ----------
  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  bool _isApprovedStatus(dynamic v) {
    final s = (v ?? '').toString().toLowerCase();
    return s == 'published' || s == 'approved' || s == 'active';
  }

  // ✅ FIXED Availability filter (same as CODE 1)
  bool _isAvailable(dynamic v) {
    final s = (v ?? '').toString().trim().toLowerCase();
    if (s.isEmpty) return true;
    if (s == 'not_available' || s == 'not available' || s == 'unavailable') {
      return false;
    }
    return true;
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  // ---------- Hearts ----------
  Future<void> _loadHeartCounts() async {
    try {
      _heartCounts.clear();
      final List<dynamic> data = await _sb.from('room_hearts').select('room_id');
      for (final row in data) {
        final String roomId = row['room_id'].toString();
        _heartCounts[roomId] = (_heartCounts[roomId] ?? 0) + 1;
      }
    } catch (_) {}
  }

  Future<void> _loadFavoriteFlags() async {
    try {
      _favorite.clear();
      final user = _sb.auth.currentUser;
      if (user == null) return;

      final List<dynamic> data =
          await _sb.from('room_hearts').select('room_id').eq('user_id', user.id);

      for (final row in data) {
        final String roomId = row['room_id'].toString();
        _favorite[roomId] = true;
      }
    } catch (_) {}
  }

  Future<void> _loadBookmarkFlags() async {
    try {
      _bookmark.clear();
      final user = _sb.auth.currentUser;
      if (user == null) return;

      final List<dynamic> data = await _sb
          .from('room_bookmarks')
          .select('room_id')
          .eq('user_id', user.id);

      for (final row in data) {
        final String roomId = row['room_id'].toString();
        _bookmark[roomId] = true;
      }
    } catch (_) {}
  }

  Future<void> _saveHeartCounts() async {}
  Future<void> _saveFavoriteFlags() async {}

  // ---------- Data load (same strategy as CODE 1) ----------
  Future<void> _fetchRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final selectCols = '''
        id,
        landlord_id,
        apartment_name,
        location,
        monthly_payment,
        created_at,
        status,
        availability_status,
        room_images:room_images!fk_room_images_room ( image_url, sort_order ),
        room_preferences:room_preferences!fk_room_preferences_room (
          preference_options:preference_options!fk_room_preferences_preference ( name )
        ),
        room_inclusions:room_inclusions!fk_room_inclusions_room (
          inclusion_options:inclusion_options!fk_room_inclusions_inclusion ( name )
        )
      ''';

      final query = _sb
          .from('rooms')
          .select(selectCols)
          .order('created_at', ascending: false)
          .order('sort_order', referencedTable: 'room_images', ascending: true)
          .limit(200);

      final List<dynamic> data = await query;

      final rooms = <_RoomItem>[];
      for (final raw in data) {
        final row = raw as Map<String, dynamic>;

        if (!_isApprovedStatus(row['status'])) continue;
        if (!_isAvailable(row['availability_status'])) continue;

        final String id = row['id'].toString();

        final String title =
            ((row['apartment_name'] ?? '').toString().trim().isNotEmpty)
                ? (row['apartment_name'] as String)
                : 'Apartment';

        final String address = (row['location'] ?? '—').toString();

        final double monthly = _toDouble(row['monthly_payment']);

        DateTime createdAt = DateTime.now();
        final createdRaw = row['created_at'];
        if (createdRaw != null) {
          createdAt = DateTime.tryParse(createdRaw.toString()) ?? DateTime.now();
        }

        String? thumb;
        final imgs = (row['room_images'] as List?) ?? const [];
        if (imgs.isNotEmpty) {
          imgs.sort((a, b) => ((a['sort_order'] ?? 0) as int)
              .compareTo((b['sort_order'] ?? 0) as int));
          thumb = imgs.first['image_url'] as String?;
        }

        final prefsArr = (row['room_preferences'] as List?) ?? const [];
        final prefSet = <String>{};
        final prefDisp = <String>{};
        for (final x in prefsArr) {
          final rel = x is Map ? x['preference_options'] : null;
          final name =
              ((rel is Map ? rel['name'] : null) ?? '').toString().trim();
          if (name.isNotEmpty) {
            prefSet.add(_norm(name));
            prefDisp.add(name);
          }
        }

        final incArr = (row['room_inclusions'] as List?) ?? const [];
        final incSet = <String>{};
        final incDisp = <String>{};
        for (final x in incArr) {
          final rel = x is Map ? x['inclusion_options'] : null;
          final name =
              ((rel is Map ? rel['name'] : null) ?? '').toString().trim();
          if (name.isNotEmpty) {
            incSet.add(_norm(name));
            incDisp.add(name);
          }
        }

        rooms.add(
          _RoomItem(
            id: id,
            title: title,
            address: address,
            monthly: monthly,
            imageUrl: thumb,
            createdAt: createdAt,
            isReserved: false,
            reservationCreatedAt: null,
            prefLabels: prefSet,
            incLabels: incSet,
            prefDisplayLabels: prefDisp,
            incDisplayLabels: incDisp,
          ),
        );
      }

      await _loadHeartCounts();
      await _loadFavoriteFlags();
      await _loadBookmarkFlags();

      for (final r in rooms) {
        r.heartCount = _heartCounts[r.id] ?? 0;
      }

      if (_filtersApplied) _applyRanking(rooms);

      setState(() {
        _rooms = rooms;
        _loading = false;
        _error = rooms.isEmpty ? 'No approved rooms yet.' : null;
        currentPage = 0;

        _recommendationPage = 0;
        if (_recommendationPageCtrl.hasClients) {
          _recommendationPageCtrl.jumpToPage(0);
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load rooms: $e';
      });
    }
  }

  // ---------- TIMER (same as CODE 1) ----------
  String _formatHms(Duration d) {
    final totalSeconds = d.inSeconds.abs();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String two(int n) => n.toString().padLeft(2, '0');
    return '$hours:${two(minutes)}:${two(seconds)} hrs';
  }

  String _reservationTimer(_RoomItem item) {
    if (!item.isReserved) return '';

    final nowUtc = _now.toUtc();
    final createdUtc = item.reservationCreatedAt;
    if (createdUtc == null) return '';

    final expiry = createdUtc.add(const Duration(hours: 2));
    final remaining = expiry.difference(nowUtc);

    if (remaining.inSeconds <= 0) return '';
    return _formatHms(Duration(seconds: remaining.inSeconds));
  }

  // ---------- Matching / Ranking (same as CODE 1) ----------
  bool _hasPref(_RoomItem r, String label) => r.prefLabels.contains(_norm(label));
  bool _hasInc(_RoomItem r, String label) => r.incLabels.contains(_norm(label));

  double _w(String key) {
    final v = preferenceImportance[key] ?? 1;
    return v.toDouble().clamp(1.0, 3.0);
  }

  ({
    int rawPoints,
    int maxPoints,
    int matches,
    int totalActive,
    double matchingScore,
    double priorityScore,
    double prioritizationScore,
    double finalScore,
  }) _scoreRoomWeighted(_RoomItem r, Map<String, String> prefs) {
    String want(String k) => (prefs[k] ?? '').trim();

    int matchesCount = 0;
    int totalActive = 0;

    final Map<String, double> criterionWeights = {};
    final Map<String, double> criterionMatches = {};

    void addCriterion(String key, bool isActive, bool isMatch) {
      if (!isActive) return;

      totalActive += 1;
      if (isMatch) matchesCount += 1;

      criterionWeights[key] = _w(key);
      criterionMatches[key] = isMatch ? 1.0 : 0.0;
    }

    final wifiActive = want('WiFi').toLowerCase() == 'yes';
    addCriterion('WiFi', wifiActive, _hasInc(r, 'WiFi'));

    final petActive = want('Pet-Friendly').toLowerCase() == 'yes';
    addCriterion('Pet-Friendly', petActive, _hasPref(r, 'Pet-Friendly'));

    final commonCrActive = want('Common CR').toLowerCase() == 'yes';
    addCriterion('Common CR', commonCrActive, _hasInc(r, 'Common CR'));

    final openAllActive = want('Open to all').toLowerCase() == 'yes';
    addCriterion('Open to all', openAllActive, _hasPref(r, 'Open to all'));

    final cabinetActive = want('Cabinet').toLowerCase() == 'yes';
    addCriterion('Cabinet', cabinetActive, _hasInc(r, 'Cabinet'));

    final tableActive = want('Table').toLowerCase() == 'yes';
    addCriterion('Table', tableActive, _hasInc(r, 'Table'));

    final fanActive = want('Fan').toLowerCase() == 'yes';
    addCriterion('Fan', fanActive, _hasInc(r, 'Fan'));

    final airconActive = want('Aircon').toLowerCase() == 'yes';
    addCriterion('Aircon', airconActive, _hasInc(r, 'Aircon'));

    final chairActive = want('Chair').toLowerCase() == 'yes';
    addCriterion('Chair', chairActive, _hasInc(r, 'Chair'));

    final occ = want('Occupation');
    final occActive = occ.isNotEmpty && occ.toLowerCase() != 'others';
    bool occMatch = false;
    if (occActive) {
      final normOcc = _norm(occ);
      occMatch = _hasPref(r, occ) ||
          (normOcc == 'professionalonly' &&
              (_hasPref(r, 'Working Professionals') ||
                  _hasPref(r, 'Professional Only'))) ||
          (normOcc == 'workingprofessionals' &&
              (_hasPref(r, 'Working Professionals') ||
                  _hasPref(r, 'Professional Only')));
    }
    addCriterion('Occupation', occActive, occMatch);

    final smokeChoice = want('Smoking Allowed').trim();
    final smokeChoiceLower = smokeChoice.toLowerCase();
    final smokeActive =
        smokeChoiceLower.isNotEmpty && smokeChoiceLower != 'ignored';

    bool smokeMatch = false;
    if (smokeActive) {
      if (smokeChoiceLower == 'non-smoker' || smokeChoiceLower == 'non smoker') {
        smokeMatch = _hasPref(r, 'Non-Smoker Only') ||
            _hasPref(r, 'Non Smoker Only') ||
            _hasPref(r, 'Non-Smoker') ||
            _hasPref(r, 'Non Smoker');
      } else if (smokeChoiceLower == 'smoker allowed' ||
          smokeChoiceLower == 'smoker') {
        smokeMatch = _hasPref(r, 'Smoker Allowed') ||
            _hasPref(r, 'Smoking allowed') ||
            _hasPref(r, 'Smoking Allowed');
      }
    }
    addCriterion('Smoking Allowed', smokeActive, smokeMatch);

    final loc = want('Location');
    final locActive = loc.isNotEmpty && loc.toLowerCase() != 'any';
    bool locMatch = false;
    if (locActive) {
      final hasPrefLoc = _hasPref(r, loc);
      final hasAddrLoc = r.address.toLowerCase().contains(loc.toLowerCase());
      locMatch = hasPrefLoc || hasAddrLoc;
    }
    addCriterion('Location', locActive, locMatch);

    final double matchingScore =
        computeMatchingScoreExact(criterionWeights, criterionMatches);

    // weighted raw/max for display
    int weightedRaw = 0;
    int weightedMax = 0;
    criterionWeights.forEach((key, w) {
      final wi = w.round();
      weightedMax += wi;
      if ((criterionMatches[key] ?? 0.0) >= 1.0) {
        weightedRaw += wi;
      }
    });

    // ---------- Prioritization (same as CODE 1) ----------
    final demand = (r.heartCount / 20.0).clamp(0.0, 1.0);

    final safeMonthly = (r.monthly <= 0) ? 1.0 : r.monthly;
    final urgency = (1.0 / (1.0 + (safeMonthly / 10000.0))).clamp(0.0, 1.0);

    final factorValues = <String, double>{
      'urgency': urgency,
      'demand': demand,
    };

    final factorWeights = <String, double>{
      'urgency': 0.40,
      'demand': 0.60,
    };

    final priorityScore = computePriorityScore(factorValues, factorWeights);
    final prioritizationScore = priorityScore;

    const double matchingWeight = 0.60;
    const double prioritizationWeight = 0.40;

    final finalScore = (matchingScore * matchingWeight) +
        (prioritizationScore * prioritizationWeight);

    return (
      rawPoints: weightedRaw,
      maxPoints: weightedMax,
      matches: matchesCount,
      totalActive: totalActive,
      matchingScore: matchingScore,
      priorityScore: priorityScore,
      prioritizationScore: prioritizationScore,
      finalScore: finalScore,
    );
  }

  void _applyRanking(List<_RoomItem> rooms) {
    final prefs = preferences;

    for (final r in rooms) {
      final s = _scoreRoomWeighted(r, prefs);

      r.matchCount = s.matches;
      r.totalSlots = s.totalActive;

      r.weightedRaw = s.rawPoints;
      r.weightedMax = s.maxPoints;

      r.matchingScore = s.matchingScore;
      r.priorityScore = s.priorityScore;
      r.prioritizationScore = s.prioritizationScore;
      r.finalScore = s.finalScore;
    }

    // ✅ stable + fair tie-breaking (same as CODE 1)
    rooms.sort((a, b) {
      int c = b.finalScore.compareTo(a.finalScore);
      if (c != 0) return c;

      c = b.matchingScore.compareTo(a.matchingScore);
      if (c != 0) return c;

      c = b.prioritizationScore.compareTo(a.prioritizationScore);
      if (c != 0) return c;

      c = a.monthly.compareTo(b.monthly);
      if (c != 0) return c;

      c = b.createdAt.compareTo(a.createdAt);
      if (c != 0) return c;

      return a.id.compareTo(b.id);
    });
  }

  // ---------- Realtime ----------
  void _subscribeRooms() {
    _roomsChannel?.unsubscribe();

    _roomsChannel = _sb.channel('landlord-rooms')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'rooms',
        callback: (_) => _fetchRooms(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'rooms',
        callback: (_) => _fetchRooms(),
      )
      ..subscribe();
  }

  // ---------- Search / Filter ----------
  List<_RoomItem> get _searchFilteredRooms {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _rooms;
    return _rooms.where((r) {
      return r.title.toLowerCase().contains(q) ||
          r.address.toLowerCase().contains(q);
    }).toList();
  }

  bool _isActivePreference(String key, String value) {
    final v = value.trim().toLowerCase();
    if (key == "Occupation") return v.isNotEmpty && v != "others";
    if (key == "Smoking Allowed") return v.isNotEmpty && v != "ignored";
    if (key == "Location") return v.isNotEmpty && v != "any";
    return v == "yes";
  }

  bool _isSwitchStyleKey(String key) {
    return key != "Occupation" && key != "Location" && key != "Smoking Allowed";
  }

  String _importanceTextFor(String key, bool enabled) {
    if (!enabled) return "Ignored";
    final w = (preferenceImportance[key] ?? 1).clamp(1, 3);
    return importanceLabel[w] ?? "Low";
  }

  void _openFilterDialog() {
    final rootContext = context;

    showModalBottomSheet(
      context: rootContext,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF00324E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.5,
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setStateDialog) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          "FILTER APARTMENTS",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "How ranking works:\n"
                        "• Only ACTIVE preferences are counted\n"
                        "• Match% = matched weights / active weights\n"
                        "• Weighted points = sum of matched importance\n"
                        "• Tie-breaker: cheaper monthly wins when scores tie",
                        style: TextStyle(
                          color: Color(0xFFC7D2FE),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        "Must-have switches",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...preferences.entries.map((entry) {
                        final key = entry.key;
                        final value = entry.value;

                        final bool isActive = _isActivePreference(key, value);
                        final int currentImportance =
                            (preferenceImportance[key] ?? 1).clamp(1, 3);

                        if (_isSwitchStyleKey(key)) {
                          final importanceText =
                              _importanceTextFor(key, isActive);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor:
                                          const Color(0xFF00324E),
                                      child:
                                          Icon(icons[key], color: Colors.white),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        key,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: isActive,
                                      activeColor:
                                          const Color(0xFF6D28D9),
                                      onChanged: (v) {
                                        setStateDialog(() {
                                          preferences[key] = v ? "Yes" : "No";
                                          if (!v) {
                                            preferenceImportance.remove(key);
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Text(
                                      "Importance: ",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF374151),
                                      ),
                                    ),
                                    Text(
                                      importanceText,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isActive
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Opacity(
                                  opacity: isActive ? 1.0 : 0.45,
                                  child: Slider(
                                    min: 1,
                                    max: 3,
                                    divisions: 2,
                                    value: currentImportance.toDouble(),
                                    onChanged: isActive
                                        ? (val) {
                                            final v = val.round().clamp(1, 3);
                                            setStateDialog(() {
                                              preferenceImportance[key] = v;
                                            });
                                          }
                                        : null,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isActive
                                      ? "Enabled: ${importanceText.toLowerCase()} $key"
                                      : "Disabled: not required",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Dropdown-style
                        return Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        const Color(0xFF00324E),
                                    child:
                                        Icon(icons[key], color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      key,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF111827),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: SizedBox(
                                      width: 180,
                                      child: DropdownButton<String>(
                                        value: value,
                                        isExpanded: true,
                                        underline: const SizedBox(),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        dropdownColor: Colors.white,
                                        items: (dropdownOptions[key] ?? [])
                                            .map<DropdownMenuItem<String>>(
                                                (opt) {
                                          return DropdownMenuItem<String>(
                                            value: opt,
                                            child: Text(
                                              opt,
                                              style: const TextStyle(fontSize: 14),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (newValue) {
                                          setStateDialog(() {
                                            preferences[key] =
                                                newValue ?? value;

                                            final nv = preferences[key] ?? value;
                                            if (!_isActivePreference(key, nv)) {
                                              preferenceImportance.remove(key);
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const SizedBox(width: 52),
                                  Expanded(
                                    child: Opacity(
                                      opacity: isActive ? 1.0 : 0.45,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Text(
                                                "Importance: ",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF374151),
                                                ),
                                              ),
                                              Text(
                                                _importanceTextFor(key, isActive),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                  color: isActive
                                                      ? const Color(0xFF2563EB)
                                                      : const Color(0xFF6B7280),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Slider(
                                            min: 1,
                                            max: 3,
                                            divisions: 2,
                                            value: (preferenceImportance[key] ?? 1)
                                                .clamp(1, 3)
                                                .toDouble(),
                                            onChanged: isActive
                                                ? (val) {
                                                    final v =
                                                        val.round().clamp(1, 3);
                                                    setStateDialog(() {
                                                      preferenceImportance[key] = v;
                                                    });
                                                  }
                                                : null,
                                          ),
                                          Text(
                                            isActive
                                                ? "Enabled: ${_importanceTextFor(key, true).toLowerCase()} $key"
                                                : "Ignored: does not affect ranking",
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF6B7280),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _filtersApplied = true;
                              _showAllWithFinalScore = false; // start 70%
                              _applyRanking(_rooms);
                            });

                            if (_scrollController.hasClients) {
                              _scrollController.animateTo(
                                0,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            }

                            Navigator.of(rootContext).pop();

                            InfoToastModal.show(
                              rootContext,
                              "Filters applied — showing Final Score ≥ 70%",
                            );
                          },
                          child: const Text(
                            'APPLY FILTERS',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ✅ Recommendations: cheapest first (does not change ranking logic)
  List<_RoomItem> get _recommendedCheapest {
    final list = List<_RoomItem>.from(_rooms);
    list.sort((a, b) => a.monthly.compareTo(b.monthly));
    return list;
  }

  Widget _moreApartmentsFooter() {
    if (!_filtersApplied) return const SizedBox.shrink();

    final isMoreMode = _showAllWithFinalScore;
    final label = isMoreMode ? "Back to 70% matches" : "More Apartment";
    final toastMsg = isMoreMode
        ? "Back to Final Score ≥ 70%"
        : "Showing apartments with Final Score ≥ 50%";

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              thickness: 1,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _showAllWithFinalScore = !isMoreMode;
                _applyRanking(_rooms);
              });

              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }

              InfoToastModal.show(context, toastMsg);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Divider(
              thickness: 1,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationsCarousel() {
    final items = _recommendedCheapest;
    if (items.isEmpty) return const SizedBox.shrink();

    final display = items.take(10).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Expanded(
                child: Text(
                  'Recommended Property',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 234,
            child: PageView.builder(
              controller: _recommendationPageCtrl,
              itemCount: display.length,
              onPageChanged: (i) => setState(() => _recommendationPage = i),
              itemBuilder: (context, index) {
                final item = display[index];

                final fav = _favorite[item.id] ?? false;
                final bm = _bookmark[item.id] ?? false;

                final timerText = _reservationTimer(item);

                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _RecommendationCard(
                    title: item.title,
                    address: item.address,
                    monthly: item.monthly,
                    imageUrl: item.imageUrl,
                    isFavorited: fav,
                    isBookmarked: bm,
                    heartCount: item.heartCount,
                    hashtags: const [],
                    timerText: timerText,
                    onOpen: () => openRoomInfo(item),
                    onMapTap: () => openMap(item),
                    onFavoriteToggle: () => toggleFavorite(item.id),
                    onBookmarkPressed: () => toggleBookmark(context, item.id),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(display.length, (i) {
              final active = i == _recommendationPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF2563EB)
                      : const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(99),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ---------- Utility ----------
  void toggleFavorite(String roomId) {
    final user = _sb.auth.currentUser;
    if (user == null) {
      InfoToastModal.show(context, 'You need to be logged in to heart.');
      return;
    }

    setState(() {
      final previous = _favorite[roomId] ?? false;
      final next = !previous;
      _favorite[roomId] = next;

      for (final r in _rooms) {
        if (r.id == roomId) {
          if (next) {
            r.heartCount++;
          } else {
            if (r.heartCount > 0) r.heartCount--;
          }
          _heartCounts[roomId] = r.heartCount;
        }
      }

      if (_filtersApplied) _applyRanking(_rooms);
    });

    () async {
      final isNowFavorited = _favorite[roomId] ?? false;
      try {
        if (isNowFavorited) {
          await _sb.from('room_hearts').insert({
            'room_id': roomId,
            'user_id': user.id,
          });
        } else {
          await _sb
              .from('room_hearts')
              .delete()
              .eq('room_id', roomId)
              .eq('user_id', user.id);
        }
      } catch (_) {
        await _loadHeartCounts();
        await _loadFavoriteFlags();
        setState(() {
          for (final r in _rooms) {
            r.heartCount = _heartCounts[r.id] ?? 0;
          }
          _applyRanking(_rooms);
        });
      }
    }();

    _saveHeartCounts();
    _saveFavoriteFlags();
  }

  void toggleBookmark(BuildContext context, String roomId) {
    final user = _sb.auth.currentUser;
    if (user == null) {
      InfoToastModal.show(context, 'You need to be logged in to bookmark.');
      return;
    }

    final newVal = !(_bookmark[roomId] ?? false);

    setState(() => _bookmark[roomId] = newVal);

    InfoToastModal.show(
      context,
      newVal ? 'Apartment bookmarked!' : 'Bookmark removed.',
    );

    () async {
      try {
        if (newVal) {
          await _sb.from('room_bookmarks').insert({
            'user_id': user.id,
            'room_id': roomId,
          });
        } else {
          await _sb
              .from('room_bookmarks')
              .delete()
              .eq('user_id', user.id)
              .eq('room_id', roomId);
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _bookmark[roomId] = !newVal;
        });
        InfoToastModal.show(context, 'Failed to update bookmark: $e');
      }
    }();
  }

  // Open landlord TOUR
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

  // Open landlord map
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
    // Same filter logic as CODE 1
    final List<_RoomItem> ranked = _filtersApplied
        ? (_showAllWithFinalScore
            ? _rooms
                .where((r) => r.finalScore >= kMoreApartmentThreshold)
                .toList()
            : _rooms
                .where((r) =>
                    r.weightedMax > 0 && r.finalScore >= kFinalScoreThreshold)
                .toList())
        : _searchFilteredRooms;

    final totalPages =
        ranked.isEmpty ? 1 : (ranked.length / cardsPerPage).ceil();
    currentPage = currentPage.clamp(0, totalPages - 1);
    final startIndex = currentPage * cardsPerPage;
    final endIndex = (startIndex + cardsPerPage).clamp(0, ranked.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          'APARTMENTS',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontSize: 22,
            letterSpacing: 0.8,
          ),
        ),
        actions: [
          if (_filtersApplied)
            IconButton(
              tooltip: 'Clear filter view',
              icon: const Icon(Icons.filter_alt_off_outlined,
                  color: Colors.white),
              onPressed: () {
                setState(() {
                  _filtersApplied = false;
                  _showAllWithFinalScore = false;
                });
                InfoToastModal.show(
                  context,
                  "Filter view cleared — showing all results",
                );
              },
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchRooms,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF04354B)),
            )
          : (_error != null
              ? Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.vertical(bottom: Radius.circular(20)),
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
                          Row(
                            children: const [
                              Icon(Icons.apartment,
                                  size: 20, color: Color(0xFF6B7280)),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Browse apartments that match your preferences.",
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
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.grey.withOpacity(0.35),
                                width: 0.9,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _searchCtrl,
                                    decoration: InputDecoration(
                                      hintText:
                                          "Search by apartment or location",
                                      hintStyle: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 14,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.search,
                                        color: Color(0xFF04354B),
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 4,
                                      ),
                                    ),
                                    style: const TextStyle(fontSize: 13),
                                    onChanged: (_) {
                                      if (!_filtersApplied) setState(() {});
                                    },
                                    readOnly: _filtersApplied,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _openFilterDialog,
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 10),
                                    height: 38,
                                    width: 38,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF04354B),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.tune_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_filtersApplied) _buildRecommendationsCarousel(),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: _filtersApplied
                          ? Column(
                              children: [
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _showAllWithFinalScore
                                        ? 'Apartments (Final Score ≥ 0.50) (${ranked.length})'
                                        : 'Matches (Final Score ≥ 0.70) (${ranked.length})',
                                    style: const TextStyle(
                                      color: Color(0xFF111827),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    _showAllWithFinalScore
                                        ? 'Tap any apartment to view details.'
                                        : 'Based on your current filters and preferences.',
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (ranked.isEmpty) ...[
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 24),
                                      child: Text(
                                        _showAllWithFinalScore
                                            ? 'No apartments found with Final Score ≥ 50%.'
                                            : 'No matches found with Final Score ≥ 70%.',
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  _moreApartmentsFooter(),
                                ] else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: ranked.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = ranked[index];
                                      final fav = _favorite[item.id] ?? false;
                                      final bm = _bookmark[item.id] ?? false;
                                      final rank = index + 1;

                                      final tags = _buildHashtags(
                                        item.prefDisplayLabels,
                                        item.incDisplayLabels,
                                        item.address,
                                      );

                                      final timerText =
                                          _reservationTimer(item);

                                      final card = LandlordApartmentCard(
                                        title: item.title,
                                        address: item.address,
                                        priceText:
                                            "₱ ${item.monthly.toStringAsFixed(0)} / Month",
                                        imageUrl: item.imageUrl,
                                        isFavorited: fav,
                                        isBookmarked: bm,
                                        onFavoriteToggle: () =>
                                            toggleFavorite(item.id),
                                        onBookmarkPressed: () =>
                                            toggleBookmark(context, item.id),
                                        onOpen: () => openRoomInfo(item),
                                        onMapTap: () => openMap(item),
                                        showRanking: true,
                                        rank: rank,
                                        matchCount: item.totalSlots > 0
                                            ? item.matchCount
                                            : null,
                                        totalSlots: item.totalSlots > 0
                                            ? item.totalSlots
                                            : null,
                                        matchingScore: item.totalSlots > 0
                                            ? item.matchingScore
                                            : null,
                                        pointsText:
                                            "${item.weightedRaw}/${item.weightedMax}",
                                        hashtags: tags,
                                        heartCount: item.heartCount,
                                        prioritizationScore:
                                            item.prioritizationScore,
                                        finalScore: item.finalScore,
                                        timerText: timerText,
                                      );

                                      final isLast =
                                          index == ranked.length - 1;

                                      return Column(
                                        children: [
                                          card,
                                          if (isLast) _moreApartmentsFooter(),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            )
                          : (ranked.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Text(
                                      'No rooms found.',
                                      style: TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: (endIndex - startIndex) + 1,
                                  itemBuilder: (context, index) {
                                    final pageCount = endIndex - startIndex;

                                    if (index < pageCount) {
                                      final item = ranked[startIndex + index];
                                      final fav = _favorite[item.id] ?? false;
                                      final bm = _bookmark[item.id] ?? false;

                                      final tags = _buildHashtags(
                                        item.prefDisplayLabels,
                                        item.incDisplayLabels,
                                        item.address,
                                      );

                                      final timerText =
                                          _reservationTimer(item);

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 12),
                                        child: LandlordApartmentCard(
                                          title: item.title,
                                          address: item.address,
                                          priceText:
                                              "₱ ${item.monthly.toStringAsFixed(0)} / Month",
                                          imageUrl: item.imageUrl,
                                          isFavorited: fav,
                                          isBookmarked: bm,
                                          onFavoriteToggle: () =>
                                              toggleFavorite(item.id),
                                          onBookmarkPressed: () =>
                                              toggleBookmark(context, item.id),
                                          onOpen: () => openRoomInfo(item),
                                          onMapTap: () => openMap(item),
                                          showRanking: false,
                                          rank: null,
                                          hashtags: tags,
                                          heartCount: item.heartCount,
                                          timerText: timerText,
                                        ),
                                      );
                                    } else {
                                      return _buildPagination(totalPages);
                                    }
                                  },
                                )),
                    ),
                  ],
                )),
      bottomNavigationBar: const LandlordBottomNav(
        currentIndex: 2, // Apartment tab
      ),
    );
  }

  Widget _buildPagination(int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
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
              iconSize: 28,
              color: const Color(0xFF4B5563),
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
                  duration: const Duration(milliseconds: 220),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: isSelected
                        ? const Color(0xFF2563EB)
                        : const Color(0xFFE5E7EB),
                    boxShadow: isSelected
                        ? const [
                            BoxShadow(
                              color: Color(0x402563EB),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : [],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    "${index + 1}",
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF374151),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
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
              iconSize: 28,
              color: const Color(0xFF4B5563),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ Recommended card UI UPDATED to accept timerText (same as CODE 1)
class _RecommendationCard extends StatelessWidget {
  final String title;
  final String address;
  final double monthly;
  final String? imageUrl;

  final bool isFavorited;
  final bool isBookmarked;
  final int heartCount;
  final List<String> hashtags;

  final String timerText;

  final VoidCallback onOpen;
  final VoidCallback onMapTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onBookmarkPressed;

  const _RecommendationCard({
    required this.title,
    required this.address,
    required this.monthly,
    required this.imageUrl,
    required this.isFavorited,
    required this.isBookmarked,
    required this.heartCount,
    required this.hashtags,
    required this.timerText,
    required this.onOpen,
    required this.onMapTap,
    required this.onFavoriteToggle,
    required this.onBookmarkPressed,
  });

  Widget _timerCapsule() {
    if (timerText.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.70),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        timerText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 130,
                  width: double.infinity,
                  child: (imageUrl != null && imageUrl!.isNotEmpty)
                      ? Image.network(imageUrl!, fit: BoxFit.cover)
                      : Image.asset('assets/images/roompano.png',
                          fit: BoxFit.cover),
                ),
                Positioned(
                  top: 10,
                  left: 10,
                  child: _timerCapsule(),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.white.withOpacity(0.95),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: onFavoriteToggle,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          isFavorited ? Icons.favorite : Icons.favorite_border,
                          color: isFavorited
                              ? Colors.redAccent
                              : const Color(0xFF9CA3AF),
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: Color(0xFF9CA3AF)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '₱${monthly.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Color(0xFF3B82F6),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const TextSpan(
                          text: ' /month',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
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

// ✅ Landlord card upgraded to match CODE 1 capabilities (ranking + timer)
class LandlordApartmentCard extends StatelessWidget {
  final String title;
  final String address;
  final String priceText;
  final String? imageUrl;

  final bool isFavorited;
  final bool isBookmarked;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onBookmarkPressed;
  final VoidCallback onOpen;
  final VoidCallback onMapTap;

  final bool showRanking;
  final int? rank;
  final int? matchCount;
  final int? totalSlots;

  final double? matchingScore;
  final double? priorityScore; // kept for compatibility (not shown)
  final double? prioritizationScore;
  final double? finalScore;

  final String? pointsText;

  final List<String> hashtags;

  final int heartCount;

  final String? timerText;

  const LandlordApartmentCard({
    super.key,
    required this.title,
    required this.address,
    required this.priceText,
    required this.imageUrl,
    required this.isFavorited,
    required this.isBookmarked,
    required this.onFavoriteToggle,
    required this.onBookmarkPressed,
    required this.onOpen,
    required this.onMapTap,
    this.showRanking = false,
    this.rank,
    this.matchCount,
    this.totalSlots,
    this.matchingScore,
    this.priorityScore,
    this.prioritizationScore,
    this.finalScore,
    this.pointsText,
    this.hashtags = const [],
    this.heartCount = 0,
    this.timerText,
  });

  Widget _timerCapsule() {
    final t = timerText ?? '';
    if (t.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF111827).withOpacity(0.80),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        t,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);
    const cardColor = Color(0xFFD7E0E6);

    final showScoreChip = showRanking && finalScore != null;

    return GestureDetector(
      onTap: onOpen,
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        elevation: 3,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: (imageUrl != null && imageUrl!.isNotEmpty)
                      ? Image.network(imageUrl!, fit: BoxFit.cover)
                      : Image.asset('assets/images/roompano.png',
                          fit: BoxFit.cover),
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
                            Color.fromARGB(120, 0, 0, 0),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ✅ show "Top" capsule ONLY for Top 1-3
                if (showRanking && rank != null && rank! <= 3)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Top $rank',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                if (showScoreChip)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFF10B981)),
                      ),
                      child: Text(
                        'Final: ${finalScore!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                else
                  Positioned(
                    top: 10,
                    right: 10,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onFavoriteToggle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isFavorited
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isFavorited
                                  ? Colors.redAccent
                                  : Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              heartCount.toString(),
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
                  ),
              ],
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              color: cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _timerCapsule(),
                      if (showRanking && !showScoreChip) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: onFavoriteToggle,
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Icon(
                              isFavorited
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: isFavorited
                                  ? Colors.redAccent
                                  : textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (showRanking &&
                      matchCount != null &&
                      totalSlots != null &&
                      matchingScore != null)
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline,
                            size: 16, color: Color(0xFF10B981)),
                        const SizedBox(width: 6),
                        Text(
                          'Matches $matchCount of $totalSlots preferences (Matching: ${matchingScore!.toStringAsFixed(2)})',
                          style: const TextStyle(
                              color: textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  if (showRanking && pointsText != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.score,
                            size: 16, color: Color(0xFF2563EB)),
                        const SizedBox(width: 6),
                        Text(
                          'Weighted points: $pointsText',
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (showRanking && prioritizationScore != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rate_rounded,
                            size: 16, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 6),
                        Text(
                          'Prioritization score: ${prioritizationScore!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (showRanking) const SizedBox(height: 6),
                  Text(
                    priceText,
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
                      const Icon(Icons.location_on_outlined,
                          color: textSecondary, size: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: textSecondary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (hashtags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: hashtags
                          .map(
                            (t) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
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
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: onMapTap,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          foregroundColor: const Color(0xFF111827),
                        ),
                        icon: const Icon(Icons.location_pin,
                            size: 18, color: Color(0xFFEF4444)),
                        label: const Text(
                          'View on map',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: onBookmarkPressed,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isBookmarked
                                ? const Color(0xFFE0FCE3)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isBookmarked
                                    ? Icons.bookmark
                                    : Icons.bookmark_border,
                                size: 18,
                                color: isBookmarked
                                    ? const Color(0xFF16A34A)
                                    : textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isBookmarked ? 'Bookmarked' : 'Bookmark',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isBookmarked
                                      ? const Color(0xFF166534)
                                      : textSecondary,
                                ),
                              ),
                            ],
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
    );
  }
}

class _RoomItem {
  final String id;
  final String title;
  final String address;
  final double monthly;
  final String? imageUrl;

  final DateTime createdAt;
  final bool isReserved;
  final DateTime? reservationCreatedAt;

  Set<String> prefLabels;
  Set<String> incLabels;

  Set<String> prefDisplayLabels;
  Set<String> incDisplayLabels;

  int matchCount;
  int totalSlots;

  int weightedRaw;
  int weightedMax;

  double matchingScore;
  double priorityScore;
  double prioritizationScore;
  double finalScore;

  int heartCount;

  _RoomItem({
    required this.id,
    required this.title,
    required this.address,
    required this.monthly,
    required this.imageUrl,
    required this.createdAt,
    this.isReserved = false,
    this.reservationCreatedAt,
    this.prefLabels = const <String>{},
    this.incLabels = const <String>{},
    this.prefDisplayLabels = const <String>{},
    this.incDisplayLabels = const <String>{},
    this.matchCount = 0,
    this.totalSlots = 0,
    this.weightedRaw = 0,
    this.weightedMax = 0,
    this.matchingScore = 0.0,
    this.priorityScore = 0.0,
    this.prioritizationScore = 0.0,
    this.finalScore = 0.0,
    this.heartCount = 0,
  });
}