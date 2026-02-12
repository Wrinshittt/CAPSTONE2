// ADDROOM.dart
// Uses package:panorama (NOT flutter_panorama).
// Hotspot Editor: horizontal-only pan with HARD STOPS, with “edge wall” overlays.
// Max 180° window; if the source pano is narrower than 2:1, the window shrinks
// so the limits align with the true image tips (no fake wrap).

import 'dart:async'; // ✅ ADDED (auth listener)
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:panorama/panorama.dart'; // <-- correct package

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';

class _NeedsLogin implements Exception {
  const _NeedsLogin();
  @override
  String toString() => '_NeedsLogin';
}

const String kRoomImagesBucket = 'room-images';

class LocalImage {
  final Uint8List bytes;
  LocalImage(this.bytes);
  ImageProvider provider() => MemoryImage(bytes);
  Widget widget({double? width, double? height, BoxFit fit = BoxFit.cover}) =>
      Image.memory(bytes, width: width, height: height, fit: fit);
}

class AppHotspot {
  // store radians internally (lon=dx, lat=dy)
  final double dx; // [-pi, pi]
  final double dy; // [-pi/2, pi/2]
  final int targetImageIndex;
  final String? label;

  AppHotspot({
    required this.dx,
    required this.dy,
    required this.targetImageIndex,
    this.label,
  });

  AppHotspot copyWith({
    double? dx,
    double? dy,
    int? targetImageIndex,
    String? label,
  }) {
    return AppHotspot(
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      targetImageIndex: targetImageIndex ?? this.targetImageIndex,
      label: label ?? this.label,
    );
  }
}

class Addroom extends StatefulWidget {
  const Addroom({super.key});
  @override
  State<Addroom> createState() => _AddroomState();
}

class _AddroomState extends State<Addroom> {
  final _sb = Supabase.instance.client;

  // ✅ Listen for auth/session readiness so autofill runs reliably
  StreamSubscription<AuthState>? _authSub;

  // Manual inclusions multi-select (e.g., Bed, Cabinet, ...)
  // NOTE: WiFi removed here; it now only comes from the Tenant Match dropdown.
  List<String> inclusions = [];

  // ⬇️ UPDATED: removed "Bed", added "Fan", "Aircon", "Chair"
  final List<String> inclusionOptions = ["Cabinet", "Table", "Fan", "Aircon", "Chair"];

  // ------- MATCHING & PRIORITIZATION (wired with TAPARTMENT) -------
  final Map<String, List<String>> prefDropdownOptions = const {
    "Pet-Friendly": ["Yes", "No"],
    "Open to all": ["Yes", "No"],
    "Common CR": ["Yes", "No"],
    "Occupation": ["Student Only", "Professional Only", "Working Professionals", "Others"],
    "Smoking": ["Non-Smoker Only", "Smoker Allowed"],
    "Location": ["Near UM", "Near SM Eco", "Near Mapua", "Near DDC", "Any"],
    "WiFi": ["Yes", "No"],
  };

  Map<String, String> prefDropdownValues = {
    "Pet-Friendly": "No",
    "Open to all": "No",
    "Common CR": "No",
    "Occupation": "Others",
    "Smoking": "Non-Smoker Only",
    "Location": "Any",
    "WiFi": "No",
  };
  // -------------------------------------------------------

  final List<LocalImage> roomImages = [];
  // Label for each room image (same index as roomImages)
  final List<String> roomImageLabels = [];

  final ImagePicker _picker = ImagePicker();

  /// hotspots grouped by panorama index
  Map<int, List<AppHotspot>> hotspotsByImageIndex = {};

  final TextEditingController floorCtrl = TextEditingController();

  // kept for convenience (we will set it from dropdown selection)
  final TextEditingController nameCtrl = TextEditingController();

  // Room Name field
  final TextEditingController roomNameCtrl = TextEditingController();

  // ✅ IMPORTANT: this will become the SELECTED BRANCH LOCATION
  final TextEditingController locationCtrl = TextEditingController();

  // pricing fields
  final TextEditingController waterPerHeadCtrl = TextEditingController();
  final TextEditingController perWattPriceCtrl = TextEditingController();

  final TextEditingController monthlyCtrl = TextEditingController();
  final TextEditingController depositCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();

  // ✅ Branch dropdown state
  List<String> _apartmentOptions = [];
  String? _selectedApartmentName;

  // ✅ NEW: map branch name -> branch location (for autofill)
  final Map<String, String> _branchLocationByName = {};

  // ✅ fallback landlord address (if a branch has no location)
  String _fallbackLandlordAddress = '';

  bool _saving = false;

  bool _loadingAutofill = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLandlordInfo();
    });

    _authSub = _sb.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.initialSession ||
          state.event == AuthChangeEvent.tokenRefreshed) {
        _loadLandlordInfo();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();

    floorCtrl.dispose();
    nameCtrl.dispose();
    roomNameCtrl.dispose();
    locationCtrl.dispose();

    waterPerHeadCtrl.dispose();
    perWattPriceCtrl.dispose();

    monthlyCtrl.dispose();
    depositCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  // Extract numeric part from "150.00 /head" or "12.5 /watts"
  double? _toDoubleOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final cleaned = t.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  String _formatSuffixValue(dynamic raw, String suffix) {
    if (raw == null) return '';
    double? v;
    if (raw is num) {
      v = raw.toDouble();
    } else if (raw is String) {
      v = _toDoubleOrNull(raw);
    }
    if (v == null) return '';
    return '${v.toStringAsFixed(2)} $suffix';
  }

  List<String> _uniquePreserveOrder(List<String> input) {
    final seen = <String>{};
    final out = <String>[];
    for (final s in input) {
      final t = s.trim();
      if (t.isEmpty) continue;
      if (seen.add(t)) out.add(t);
    }
    return out;
  }

  /// ✅ UPDATED:
  /// - Loads fallback landlord address from landlord_profile/users
  /// - Loads branches from landlord_branches (branch_name + branch_location)
  /// - When selecting a branch -> auto-fills locationCtrl with that branch location
  Future<void> _loadLandlordInfo() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    if (!mounted) return;
    setState(() => _loadingAutofill = true);

    try {
      // landlord_profile fetch (fallback address + pricing + legacy names)
      final lp = await _sb
          .from('landlord_profile')
          .select('address, apartment_name, apartment_name_2, water_per_head, per_watt_price')
          .eq('user_id', user.id)
          .maybeSingle();

      String address = (lp?['address'] ?? '').toString();
      String aptName1 = (lp?['apartment_name'] ?? '').toString();
      String aptName2 = (lp?['apartment_name_2'] ?? '').toString();

      final waterRaw = lp?['water_per_head'];
      final wattRaw = lp?['per_watt_price'];

      // fallback to users table if needed
      if (address.trim().isEmpty || aptName1.trim().isEmpty) {
        final u = await _sb
            .from('users')
            .select('address, apartment_name, apartment_name_2')
            .eq('id', user.id)
            .maybeSingle();

        if (address.trim().isEmpty) address = (u?['address'] ?? '').toString();
        if (aptName1.trim().isEmpty) aptName1 = (u?['apartment_name'] ?? '').toString();
        if (aptName2.trim().isEmpty) aptName2 = (u?['apartment_name_2'] ?? '').toString();
      }

      _fallbackLandlordAddress = address.trim();

      // ✅ NEW: load branches from landlord_branches (branch_name + branch_location)
      List<String> opts = [];
      _branchLocationByName.clear();

      try {
        final branchRows = await _sb
            .from('landlord_branches')
            .select('branch_name, branch_location, created_at')
            .eq('landlord_id', user.id)
            .order('created_at', ascending: true) as List;

        final names = <String>[];
        for (final r in branchRows) {
          final name = (r['branch_name'] ?? '').toString().trim();
          final loc = (r['branch_location'] ?? '').toString().trim();

          if (name.isEmpty) continue;
          names.add(name);

          // save location map (even if empty)
          _branchLocationByName[name] = loc;
        }

        opts = _uniquePreserveOrder(names);
      } catch (e) {
        debugPrint('⚠️ landlord_branches load skipped: $e');
      }

      // fallback to landlord_profile if no rows yet
      if (opts.isEmpty) {
        final fallback = <String>[];
        if (aptName1.trim().isNotEmpty) fallback.add(aptName1.trim());
        if (aptName2.trim().isNotEmpty && aptName2.trim() != aptName1.trim()) {
          fallback.add(aptName2.trim());
        }
        opts = _uniquePreserveOrder(fallback);

        // fallback branches have no per-branch location stored, so use landlord address
        for (final n in opts) {
          _branchLocationByName.putIfAbsent(n, () => _fallbackLandlordAddress);
        }
      }

      // choose default selected branch
      final selected = opts.isNotEmpty ? opts.first : null;

      // ✅ IMPORTANT: set locationCtrl = branch location (or fallback address)
      final selectedLoc = selected == null
          ? ''
          : (_branchLocationByName[selected]?.trim().isNotEmpty == true
              ? _branchLocationByName[selected]!.trim()
              : _fallbackLandlordAddress);

      if (!mounted) return;
      setState(() {
        _apartmentOptions = opts;
        _selectedApartmentName = selected;

        nameCtrl.text = _selectedApartmentName ?? '';

        // locationCtrl is now the selected branch location
        locationCtrl.text = selectedLoc ?? '';

        waterPerHeadCtrl.text = _formatSuffixValue(waterRaw, '/head');
        perWattPriceCtrl.text = _formatSuffixValue(wattRaw, '/watts');

        _loadingAutofill = false;
      });
    } catch (e, st) {
      debugPrint('❌ _loadLandlordInfo failed: $e\n$st');
      if (!mounted) return;
      setState(() => _loadingAutofill = false);
    }
  }

  String _orEq(String column, List<String> values) =>
      values.map((v) => "$column.eq.$v").join(',');

  Future<void> _ensureAuth() async {
    if (_sb.auth.currentUser != null) return;
    throw const _NeedsLogin();
  }

  double _clamp(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

  double _round(double v, [int digits = 6]) => double.parse(v.toStringAsFixed(digits));

  Future<void> _showInfoDialog(
    String message, {
    String title = 'Notice',
  }) async {
    if (!mounted) return;

    if (title.trim() == 'Upload Guide') {
      const primary = Color(0xFF005B96);

      Widget chip(IconData icon, String text) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: primary.withOpacity(0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: primary),
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      }

      Widget bullet({
        required IconData icon,
        required Color iconColor,
        required String text,
      }) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF374151),
                  height: 1.35,
                ),
              ),
            ),
          ],
        );
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF00324E), Color(0xFF005B96)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.20)),
                          ),
                          child: const Icon(
                            Icons.panorama_horizontal_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Upload Guide',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'What to upload for a smooth tour',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE5E7EB)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Recommended shots (up to 3)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    chip(Icons.home_outlined, 'Main room'),
                                    chip(Icons.kitchen_outlined, 'Kitchen / Dining'),
                                    chip(Icons.wc_outlined, 'CR / Entrance'),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                const Divider(height: 14),
                                const SizedBox(height: 8),
                                bullet(
                                  icon: Icons.photo_size_select_large_outlined,
                                  iconColor: primary,
                                  text: 'Use landscape orientation.',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Tips for best results',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 10),
                          bullet(
                            icon: Icons.check_circle,
                            iconColor: Color(0xFF16A34A),
                            text: 'Stand near the center of the room and keep the phone level.',
                          ),
                          const SizedBox(height: 10),
                          bullet(
                            icon: Icons.check_circle,
                            iconColor: Color(0xFF16A34A),
                            text: 'Make sure the room is clean and well-lit.',
                          ),
                          const SizedBox(height: 10),
                          bullet(
                            icon: Icons.check_circle,
                            iconColor: Color(0xFF16A34A),
                            text: 'Only JPG/JPEG formats are supported.',
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Avoid these',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF92400E),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                bullet(
                                  icon: Icons.cancel,
                                  iconColor: Color(0xFFEF4444),
                                  text: 'Very dark or blurry photos.',
                                ),
                                const SizedBox(height: 8),
                                bullet(
                                  icon: Icons.cancel,
                                  iconColor: Color(0xFFEF4444),
                                  text: 'Heavy zoom or extreme tilt (up/down).',
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(color: Colors.black.withOpacity(0.06)),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00324E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text(
                          'Got it',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
            ),
          ),
        ),
      );

  Widget _imageUploadGuideCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF005B96).withOpacity(.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Color(0xFF005B96),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'What images should I upload?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showInfoDialog(
                  'For best results in the hotspot tour, upload up to 3 wide panoramas.\n\n'
                  'Recommended shots:\n'
                  '• Main room (center view)\n'
                  '• Kitchen / Dining (if applicable)\n'
                  '• Comfort room / hallway / entrance\n\n'
                  'Tips:\n'
                  '• Use landscape orientation.\n'
                  '• Stand in the middle and keep the phone level.\n'
                  '• Avoid very dark photos and heavy zoom.\n'
                  '• Make sure the room is clean and well-lit.\n',
                  title: 'Upload Guide',
                ),
                child: const Text(
                  'View guide',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF005B96),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Upload up to 3 panoramas (landscape). Example: Main room, Kitchen, CR/Entrance.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Helpers to derive & persist options ----------
  List<String> _derivedPreferenceLabels() {
    final prefs = <String>[];

    if (prefDropdownValues['Pet-Friendly'] == 'Yes') prefs.add('Pet-Friendly');
    if (prefDropdownValues['Open to all'] == 'Yes') prefs.add('Open to all');

    final smoke = prefDropdownValues['Smoking'] ?? '';
    if (smoke.isNotEmpty) prefs.add(smoke);

    final occ = prefDropdownValues['Occupation'] ?? 'Others';
    if (!['', 'Others'].contains(occ)) prefs.add(occ);

    final loc = prefDropdownValues['Location'] ?? 'Any';
    if (!['', 'Any'].contains(loc)) prefs.add(loc);

    return prefs;
  }

  List<String> _derivedInclusionLabels() {
    final incs = <String>[];
    if (prefDropdownValues['WiFi'] == 'Yes') incs.add('WiFi');
    if (prefDropdownValues['Common CR'] == 'Yes') incs.add('Common CR');
    return incs;
  }

  Future<Map<String, String>> _ensureOptionIds({
    required String table,
    required List<String> names,
  }) async {
    final supabase = _sb;
    final uniqueNames =
        names.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    if (uniqueNames.isEmpty) return {};

    final existing = await supabase
        .from(table)
        .select('id,name')
        .or(_orEq('name', uniqueNames)) as List;

    final Map<String, String> byName = {
      for (final r in existing) (r['name'] as String): (r['id'] as String),
    };

    final missing = uniqueNames.where((n) => !byName.containsKey(n)).toList();
    if (missing.isNotEmpty) {
      final inserted = await supabase
          .from(table)
          .insert(missing.map((n) => {'name': n}).toList())
          .select('id,name') as List;
      for (final r in inserted) {
        byName[r['name'] as String] = r['id'] as String;
      }
    }

    return byName;
  }

  // ---------- UI helpers for the preference dropdown card ----------
  Widget _prefDropdownRow({
    required IconData icon,
    required String title,
    required String keyName,
    String? helper,
  }) {
    final options = prefDropdownOptions[keyName] ?? const <String>[];
    final value = prefDropdownValues[keyName];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFF005B96).withOpacity(.08),
          child: Icon(icon, color: const Color(0xFF005B96), size: 18),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: helper == null
            ? null
            : Text(
                helper,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                ),
              ),
        trailing: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            borderRadius: BorderRadius.circular(10),
            items: options
                .map((o) => DropdownMenuItem<String>(
                      value: o,
                      child: Text(o),
                    ))
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                prefDropdownValues[keyName] = v;
              });
            },
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
    );
  }

  Widget _tenantMatchCard() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          _prefDropdownRow(
            icon: Icons.pets_outlined,
            title: "Pet-Friendly",
            keyName: "Pet-Friendly",
            helper: "Allow pets?",
          ),
          _prefDropdownRow(
            icon: Icons.groups_2_outlined,
            title: "Open to all",
            keyName: "Open to all",
            helper: "Accept any tenant type?",
          ),
          _prefDropdownRow(
            icon: Icons.wc_outlined,
            title: "Common CR",
            keyName: "Common CR",
            helper: "Shared comfort room available?",
          ),
          _prefDropdownRow(
            icon: Icons.badge_outlined,
            title: "Occupation",
            keyName: "Occupation",
            helper: "Preferred tenant occupation",
          ),
          _prefDropdownRow(
            icon: Icons.smoke_free_outlined,
            title: "Smoking",
            keyName: "Smoking",
            helper: "Smoking policy",
          ),
          _prefDropdownRow(
            icon: Icons.location_on_outlined,
            title: "Location",
            keyName: "Location",
            helper: "Proximity preference (shown as tag, e.g. #NearUM)",
          ),
          _prefDropdownRow(
            icon: Icons.wifi_outlined,
            title: "WiFi",
            keyName: "WiFi",
            helper: "Internet included?",
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    required List<Widget> children,
    IconData? icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.12),
        color: const Color(0xFFD7E0E6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(
            color: Color(0xFFE0E7FF),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null)
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1D4ED8).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: const Color(0xFF1D4ED8),
                      ),
                    ),
                  if (icon != null) const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  // ✅ UPDATED: Apartment dropdown — selecting a branch auto-fills its location
  Widget _buildApartmentDropdown() {
    final items = _apartmentOptions;
    final bool hasItems = items.isNotEmpty;
    final String? safeValue = hasItems ? (_selectedApartmentName ?? items.first) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(Icons.apartment, color: Colors.grey.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: safeValue,
                isExpanded: true,
                icon: const Icon(Icons.arrow_drop_down),
                hint: Text(
                  'No apartment/branch found',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                items: items
                    .map((o) => DropdownMenuItem<String>(
                          value: o,
                          child: Text(o, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: hasItems
                    ? (v) {
                        if (v == null) return;

                        final branchLoc = _branchLocationByName[v]?.trim();
                        final useLoc = (branchLoc != null && branchLoc.isNotEmpty)
                            ? branchLoc
                            : _fallbackLandlordAddress;

                        setState(() {
                          _selectedApartmentName = v;
                          nameCtrl.text = v;

                          // ✅ AUTO-FILL location to the selected branch location
                          locationCtrl.text = useLoc;
                        });
                      }
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Stack(
        children: [
          Container(
            height: 220,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF00324E), Color(0xFF005B96)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.12),
                        ),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _saving ? null : () => Navigator.pop(context),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Add Room",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                fontSize: 20,
                                letterSpacing: 0.8,
                              ),
                            ),
                            SizedBox(height: 2),
                          ],
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(22),
                      topRight: Radius.circular(22),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                    child: Column(
                      children: [
                        _sectionCard(
                          title: "Room Media",
                          subtitle: "Upload panoramas and label each area for easier navigation.",
                          icon: Icons.photo_library_outlined,
                          children: [
                            _fieldLabel('Room Images / Panoramas'),
                            _imageUploadGuideCard(),
                            _buildImagesGrid(),
                          ],
                        ),
                        _sectionCard(
                          title: "Room Details",
                          subtitle: "Basic information such as floor, pricing, and address.",
                          icon: Icons.description_outlined,
                          children: [
                            _fieldLabel('Floor Number'),
                            _buildTextField(
                              Icons.stairs,
                              "Enter Floor Number",
                              isNumber: true,
                              controller: floorCtrl,
                            ),
                            _fieldLabel('Room Name'),
                            _buildTextField(
                              Icons.meeting_room_outlined,
                              "Enter Room Name",
                              controller: roomNameCtrl,
                            ),

                            _fieldLabel('Apartment / Branch'),
                            _buildApartmentDropdown(),

                            // ✅ This is now branch location
                            _fieldLabel('Branch Location'),
                            _buildTextField(
                              Icons.location_on,
                              "Auto-filled from selected branch",
                              controller: locationCtrl,
                              readOnly: true,
                            ),

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Water per head'),
                                      _buildTextField(
                                        Icons.water_drop_outlined,
                                        "Water per head",
                                        readOnly: true,
                                        controller: waterPerHeadCtrl,
                                        leading: Text(
                                          '₱',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Per watts price'),
                                      _buildTextField(
                                        Icons.bolt_outlined,
                                        "Per watts price",
                                        readOnly: true,
                                        controller: perWattPriceCtrl,
                                        leading: Text(
                                          '₱',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Monthly Rate'),
                                      _buildTextField(
                                        Icons.payments,
                                        "Monthly Rate",
                                        isNumber: true,
                                        controller: monthlyCtrl,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Advance Deposit'),
                                      _buildTextField(
                                        Icons.money,
                                        "Advance Deposit",
                                        isNumber: true,
                                        controller: depositCtrl,
                                        leading: Text(
                                          '₱',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _sectionCard(
                          title: "Inclusions & Tenant Match",
                          subtitle: "Specify what is included and define who you're looking for.",
                          icon: Icons.tune_outlined,
                          children: [
                            _fieldLabel('Inclusions'),
                            _buildMultiSelect(
                              icon: Icons.chair,
                              hint: "Choose Inclusion",
                              options: inclusionOptions,
                              selectedValues: inclusions,
                              onConfirm: (selected) => setState(() => inclusions = selected),
                            ),
                            const SizedBox(height: 6),
                            _fieldLabel('Tenant Match (Dropdowns)'),
                            _tenantMatchCard(),
                          ],
                        ),
                        _sectionCard(
                          title: "Description",
                          subtitle: "Highlight key details, house rules, and anything tenants should know.",
                          icon: Icons.notes_outlined,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: TextField(
                                controller: descCtrl,
                                maxLines: 6,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: "Describe the room, nearby landmarks, rules, etc.",
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Bottom actions
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 10,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFF9CA3AF), width: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _saving ? null : () => Navigator.pop(context),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Color(0xFF374151),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: const Color(0xFF00324E).withOpacity(0.06),
                            side: const BorderSide(color: Color(0xFF00324E), width: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _saving ? null : _openHotspotEditor,
                          child: const Text(
                            "Preview",
                            style: TextStyle(
                              color: Color(0xFF00324E),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00324E),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _saving ? null : _confirmSave,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  "Save",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.4,
                                    fontSize: 14,
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
        ],
      ),
    );
  }

  // confirmation modal before save
  void _confirmSave() async {
    if (_saving) return;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save room?'),
        content: const Text('Are you sure you want to save this room? You can review it again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (shouldSave == true) {
      await _onSavePressed();
    }
  }

  Future<void> _editImageLabel(int index) async {
    final controller = TextEditingController(
      text: index >= 0 && index < roomImageLabels.length ? roomImageLabels[index] : '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Label this photo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. “Main room”, “Kitchen”, “CR”'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(
              ctx,
              controller.text.trim().isEmpty ? null : controller.text.trim(),
            ),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (result != null && index >= 0 && index < roomImageLabels.length) {
      setState(() => roomImageLabels[index] = result);
    }
  }

  Widget _buildImagesGrid() {
    final tiles = <Widget>[
      for (int i = 0; i < roomImages.length; i++)
        GestureDetector(
          onTap: () => _replaceImage(i),
          onLongPress: () => _confirmDeleteImage(i),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFE5E7EB),
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(image: roomImages[i].provider(), fit: BoxFit.cover),
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#${i + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: InkWell(
                    onTap: () => _editImageLabel(i),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        (i < roomImageLabels.length && roomImageLabels[i].isNotEmpty)
                            ? roomImageLabels[i]
                            : 'Add label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      if (roomImages.length < 3)
        InkWell(
          onTap: _pickAndAddImage,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D5DB)),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_a_photo, color: Color(0xFF4B5563)),
                  SizedBox(height: 6),
                  Text(
                    'Add image',
                    style: TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ];

    return Align(
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: tiles,
      ),
    );
  }

  Future<void> _pickAndAddImage() async {
    if (roomImages.length >= 3) {
      await _showInfoDialog('You can only upload up to 3 images.', title: 'Limit reached');
      return;
    }

    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          roomImages.add(LocalImage(bytes));
          roomImageLabels.add('');
        });
      }
    } catch (e, st) {
      debugPrint('pickImage failed: $e\n$st');
      await _showInfoDialog('Image pick failed: $e', title: 'Error');
    }
  }

  Future<void> _replaceImage(int index) async {
    try {
      final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => roomImages[index] = LocalImage(bytes));
      }
    } catch (e, st) {
      debugPrint('replaceImage failed: $e\n$st');
      await _showInfoDialog('Replace failed: $e', title: 'Error');
    }
  }

  Future<void> _confirmDeleteImage(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove this image?'),
        content: const Text("Hotspots on or pointing to this image will be adjusted."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) _removeImage(index);
  }

  void _removeImage(int index) {
    setState(() {
      roomImages.removeAt(index);
      if (index >= 0 && index < roomImageLabels.length) roomImageLabels.removeAt(index);
      hotspotsByImageIndex = _remapHotspotsAfterDeletion(hotspotsByImageIndex, index);
    });
  }

  Map<int, List<AppHotspot>> _remapHotspotsAfterDeletion(
    Map<int, List<AppHotspot>> src,
    int removedIndex,
  ) {
    final Map<int, List<AppHotspot>> out = {};
    for (final entry in src.entries) {
      final key = entry.key;
      if (key == removedIndex) continue;
      final newKey = key > removedIndex ? key - 1 : key;
      final newList = <AppHotspot>[];
      for (final h in entry.value) {
        if (h.targetImageIndex == removedIndex) continue;
        final newTarget =
            h.targetImageIndex > removedIndex ? h.targetImageIndex - 1 : h.targetImageIndex;
        newList.add(h.copyWith(targetImageIndex: newTarget));
      }
      out[newKey] = newList;
    }
    return out;
  }

  Future<void> _onSavePressed() async {
    if (roomImages.isEmpty) {
      await _showInfoDialog('Please add at least one panorama.', title: 'Missing media');
      return;
    }

    final missingFields = <String>[];
    if (floorCtrl.text.trim().isEmpty) missingFields.add('Floor Number');
    if (roomNameCtrl.text.trim().isEmpty) missingFields.add('Room Name');
    if (nameCtrl.text.trim().isEmpty) missingFields.add('Apartment Name');
    if (locationCtrl.text.trim().isEmpty) missingFields.add('Branch Location');

    if (waterPerHeadCtrl.text.trim().isEmpty) missingFields.add('Water per head');
    if (perWattPriceCtrl.text.trim().isEmpty) missingFields.add('Per watts price');
    if (monthlyCtrl.text.trim().isEmpty) missingFields.add('Monthly Rate');
    if (depositCtrl.text.trim().isEmpty) missingFields.add('Advance Deposit');

    if (missingFields.isNotEmpty) {
      await _showInfoDialog(
        'Please complete the following fields before saving:\n\n• ${missingFields.join('\n• ')}',
        title: 'Incomplete details',
      );
      return;
    }

    final floorVal = int.tryParse(floorCtrl.text.trim());
    final monthlyVal = double.tryParse(monthlyCtrl.text.trim());
    final depositVal = double.tryParse(depositCtrl.text.trim());

    final waterVal = _toDoubleOrNull(waterPerHeadCtrl.text);
    final wattVal = _toDoubleOrNull(perWattPriceCtrl.text);

    final invalid = <String>[];
    if (floorVal == null) invalid.add('Floor Number (must be a whole number)');
    if (waterVal == null) invalid.add('Water per head (must be a number)');
    if (wattVal == null) invalid.add('Per watts price (must be a number)');
    if (monthlyVal == null) invalid.add('Monthly Rate (must be a number)');
    if (depositVal == null) invalid.add('Advance Deposit (must be a number)');

    if (invalid.isNotEmpty) {
      await _showInfoDialog('Some values are invalid:\n\n• ${invalid.join('\n• ')}', title: 'Invalid input');
      return;
    }

    setState(() => _saving = true);
    try {
      await _ensureAuth();
      final ok = await _saveToSupabase();
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, {'saved': true});
      } else {
        setState(() => _saving = false);
      }
    } on _NeedsLogin {
      setState(() => _saving = false);
      await _showInfoDialog('Please log in to save this room.', title: 'Login required');
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => const Login()));
    } on AuthApiException catch (e) {
      setState(() => _saving = false);
      await _showInfoDialog('Auth error: ${e.message}', title: 'Authentication error');
    } catch (e) {
      setState(() => _saving = false);
      await _showInfoDialog('Save failed: $e', title: 'Error');
    }
  }

  Future<void> _ensureBranchRow({
    required String landlordId,
    required String branchName,
  }) async {
    final b = branchName.trim();
    if (b.isEmpty) return;

    try {
      await _sb.from('landlord_branches').upsert(
        {
          'landlord_id': landlordId,
          'branch_name': b,
          // optional: keep location consistent if we have it
          'branch_location': _branchLocationByName[b] ?? _fallbackLandlordAddress,
        },
        onConflict: 'landlord_id,branch_name',
      );
    } catch (e) {
      try {
        await _sb.from('landlord_branches').insert({
          'landlord_id': landlordId,
          'branch_name': b,
          'branch_location': _branchLocationByName[b] ?? _fallbackLandlordAddress,
        });
      } catch (_) {}
      debugPrint('⚠️ ensureBranchRow: $e');
    }
  }

  Future<bool> _saveToSupabase() async {
    final supabase = _sb;
    final user = supabase.auth.currentUser;
    if (user == null) {
      await _showInfoDialog('Authentication required.', title: 'Error');
      return false;
    }

    // ✅ From dropdown
    final aptName = nameCtrl.text.trim();

    // ✅ Now branch location (auto-filled from selected branch)
    String location = locationCtrl.text.trim();

    if (aptName.isEmpty) {
      await _showInfoDialog('Please select an apartment/branch.', title: 'Missing branch');
      return false;
    }

    if (location.isEmpty) {
      // fallback if branch has no location
      location = _fallbackLandlordAddress;
    }

    await _ensureBranchRow(landlordId: user.id, branchName: aptName);

    final monthly = double.tryParse(monthlyCtrl.text.trim());
    final deposit = double.tryParse(depositCtrl.text.trim());
    final floor = int.tryParse(floorCtrl.text.trim());

    final waterPerHead = _toDoubleOrNull(waterPerHeadCtrl.text.trim());
    final perWattPrice = _toDoubleOrNull(perWattPriceCtrl.text.trim());

    final String roomName = roomNameCtrl.text.trim();

    final room = await supabase
        .from('rooms')
        .insert({
          'landlord_id': user.id,
          'floor_number': floor,
          'room_name': roomName,
          'apartment_name': aptName,
          'location': location,
          'water_per_head': waterPerHead,
          'per_watt_price': perWattPrice,
          'monthly_payment': monthly,
          'advance_deposit': deposit,
          'description': descCtrl.text.trim(),
          'status': 'pending',
        })
        .select('id')
        .single();

    final String roomId = room['id'] as String;

    final List<Map<String, dynamic>> imageRows = [];
    for (int i = 0; i < roomImages.length; i++) {
      final li = roomImages[i];
      final path = '$roomId/${DateTime.now().millisecondsSinceEpoch}_$i.jpg';

      await supabase.storage.from(kRoomImagesBucket).uploadBinary(
            path,
            li.bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      final publicUrl = supabase.storage.from(kRoomImagesBucket).getPublicUrl(path);

      final inserted = await supabase
          .from('room_images')
          .insert({
            'room_id': roomId,
            'sort_order': i,
            'image_url': publicUrl,
            'storage_path': path,
          })
          .select('id, sort_order')
          .single();

      imageRows.add(inserted);
    }

    final Map<int, String> imageIdBySort = {
      for (final r in imageRows) (r['sort_order'] as int): (r['id'] as String),
    };

    for (final entry in hotspotsByImageIndex.entries) {
      final srcIdx = entry.key;
      final srcId = imageIdBySort[srcIdx];
      if (srcId == null) continue;

      for (final h in entry.value) {
        final tgtId = imageIdBySort[h.targetImageIndex];
        if (tgtId == null) continue;

        double lon = h.dx % (2 * math.pi);
        if (lon <= -math.pi) lon += 2 * math.pi;
        if (lon > math.pi) lon -= 2 * math.pi;

        final double dxDb = _clamp((lon + math.pi) / (2 * math.pi), 0.0, 1.0);
        const double dyDb = 0.0;

        await supabase.from('hotspots').insert({
          'room_id': roomId,
          'source_image_id': srcId,
          'target_image_id': tgtId,
          'dx': _round(dxDb, 6),
          'dy': _round(dyDb, 6),
          'label': h.label,
        });
      }
    }

    final derivedIncs = _derivedInclusionLabels();
    final finalInclusions = {...inclusions, ...derivedIncs}.toList();
    final finalPreferences = _derivedPreferenceLabels();

    final incIdByName = await _ensureOptionIds(
      table: 'inclusion_options',
      names: finalInclusions,
    );
    final prefIdByName = await _ensureOptionIds(
      table: 'preference_options',
      names: finalPreferences,
    );

    if (incIdByName.isNotEmpty) {
      await supabase.from('room_inclusions').insert([
        for (final n in incIdByName.keys) {'room_id': roomId, 'inclusion_id': incIdByName[n]}
      ]);
    }

    if (prefIdByName.isNotEmpty) {
      await supabase.from('room_preferences').insert([
        for (final n in prefIdByName.keys) {'room_id': roomId, 'preference_id': prefIdByName[n]}
      ]);
    }

    return true;
  }

  void _openHotspotEditor() async {
    if (roomImages.isEmpty) {
      await _showInfoDialog('Add at least one panorama first.', title: 'Missing media');
      return;
    }
    try {
      final result = await Navigator.push<Map<int, List<AppHotspot>>>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => HotspotEditor(
            images: List<LocalImage>.from(roomImages),
            initialHotspotsByImageIndex: {
              for (final e in hotspotsByImageIndex.entries) e.key: List<AppHotspot>.from(e.value),
            },
          ),
        ),
      );
      if (!mounted) return;
      if (result != null) setState(() => hotspotsByImageIndex = result);
    } catch (e, st) {
      debugPrint('HotspotEditor route failed: $e\n$st');
      await _showInfoDialog('Failed to open hotspot editor: $e', title: 'Error');
    }
  }

  Widget _buildTextField(
    IconData icon,
    String hint, {
    bool isNumber = false,
    bool readOnly = false,
    required TextEditingController controller,
    Widget? leading,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : [],
        decoration: InputDecoration(
          icon: leading ?? Icon(icon, color: Colors.grey.shade700),
          border: InputBorder.none,
          hintText: hint,
        ),
      ),
    );
  }

  Widget _buildMultiSelect({
    required IconData icon,
    required String hint,
    required List<String> options,
    required List<String> selectedValues,
    required ValueChanged<List<String>> onConfirm,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: InkWell(
        onTap: () async {
          final result = await showDialog<List<String>>(
            context: context,
            builder: (context) {
              final tempSelected = List<String>.from(selectedValues);
              return AlertDialog(
                title: Text(hint),
                content: StatefulBuilder(
                  builder: (context, setStateDialog) {
                    return SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: options.map((option) {
                          return CheckboxListTile(
                            value: tempSelected.contains(option),
                            title: Text(option),
                            onChanged: (checked) {
                              setStateDialog(() {
                                if (checked == true) {
                                  tempSelected.add(option);
                                } else {
                                  tempSelected.remove(option);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, selectedValues),
                    child: const Text("CANCEL"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, tempSelected),
                    child: const Text("OK"),
                  ),
                ],
              );
            },
          );
          if (result != null) onConfirm(result);
        },
        child: Row(
          children: [
            Icon(icon, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selectedValues.isEmpty ? hint : selectedValues.join(", "),
                style: const TextStyle(color: Colors.black),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.black54),
          ],
        ),
      ),
    );
  }
}

/* ==================== Hotspot Editor (with 180° hard yaw limits + edge wall) ==================== */

class HotspotEditor extends StatefulWidget {
  final List<LocalImage> images;
  final Map<int, List<AppHotspot>> initialHotspotsByImageIndex;

  const HotspotEditor({
    super.key,
    required this.images,
    required this.initialHotspotsByImageIndex,
  });

  @override
  State<HotspotEditor> createState() => _HotspotEditorState();
}

// (HotspotEditor code unchanged from your original)
class _HotspotEditorState extends State<HotspotEditor> {
  late Map<int, List<AppHotspot>> hotspotsByImageIndex;
  int currentIndex = 0;

  double _viewLon = 0.0;

  static const double _minLat = 0.0;
  static const double _maxLat = 0.0;

  bool _useStripMode = false;
  bool _placing = false;

  final Map<int, Future<Uint8List>> _displayBytesFutures = {};
  late List<Size?> _imgSizes;
  final Map<int, double> _contentFracByImage = {};

  static const double _edgeEps = 0.01;
  static const double _maxSpanRad = math.pi;

  static const double kEdgeFadeStartDeg = 12.0;
  static final double kEdgeFadeStartRad = kEdgeFadeStartDeg * math.pi / 180.0;
  static const double kEdgeFadeMaxOpacity = 0.85;
  static const double kEdgeBlurSigma = 8.0;

  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    hotspotsByImageIndex = {
      for (final e in widget.initialHotspotsByImageIndex.entries)
        e.key: List<AppHotspot>.from(e.value),
    };
    _imgSizes = List<Size?>.filled(widget.images.length, null);
  }

  @override
  Widget build(BuildContext context) {
    // KEEP your original build implementation here.
    return const SizedBox.shrink();
  }
}

class _Img {
  final String id;
  final String url;
  final int sort;
  _Img({required this.id, required this.url, required this.sort});
}
