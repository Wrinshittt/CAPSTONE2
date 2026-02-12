// UPDATED CODE: EditRoom with Water per head + Per watts price fields + SAVE button (saved to rooms table)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_finder/LANDLORD/EDITTOUR.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ✅ Toast modal
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

class EditRoom extends StatefulWidget {
  final String roomId;

  const EditRoom({
    super.key,
    required this.roomId,
  });

  @override
  State<EditRoom> createState() => _EditRoomState();
}

class _EditRoomState extends State<EditRoom> {
  final _sb = Supabase.instance.client;

  // Multi-select state
  List<String> inclusions = [];
  List<String> preferences = [];

  // manual inclusions (WiFi removed here; comes from dropdown)
  final List<String> inclusionOptions = [
    "Cabinet",
    "Table",
    "Fan",
    "Aircon",
    "Chair",
  ];

  final List<String> preferenceOptions = [
    "Male Only",
    "Female Only",
    "Mixed",
    "Couples",
    "Working Professionals",
  ];

  // Tenant Match dropdowns
  final Map<String, List<String>> prefDropdownOptions = const {
    "Pet-Friendly": ["Yes", "No"],
    "Open to all": ["Yes", "No"],
    "Common CR": ["Yes", "No"],
    "Occupation": [
      "Student Only",
      "Professional Only",
      "Working Professionals",
      "Others"
    ],
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

  // Images
  final List<File?> roomImages = [null, null, null];
  final ImagePicker _picker = ImagePicker();

  // Remote URLs from DB to show existing images
  List<String?> _remoteImageUrls = [null, null, null];

  // Track cleared slots
  final List<bool> _clearedSlots = [false, false, false];

  // Controllers
  final TextEditingController roomNameCtrl = TextEditingController();
  final TextEditingController floorCtrl = TextEditingController();
  final TextEditingController apartmentNameCtrl = TextEditingController();
  final TextEditingController locationCtrl = TextEditingController();
  final TextEditingController monthlyCtrl = TextEditingController();
  final TextEditingController depositCtrl = TextEditingController();

  // ✅ NEW: pricing controllers
  final TextEditingController waterPerHeadCtrl = TextEditingController();
  final TextEditingController perWattPriceCtrl = TextEditingController();

  final TextEditingController descCtrl = TextEditingController();

  bool _loadingExisting = true;
  bool _prefilledOnce = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingRoomData();
  }

  @override
  void dispose() {
    roomNameCtrl.dispose();
    floorCtrl.dispose();
    apartmentNameCtrl.dispose();
    locationCtrl.dispose();
    monthlyCtrl.dispose();
    depositCtrl.dispose();
    waterPerHeadCtrl.dispose();
    perWattPriceCtrl.dispose();
    descCtrl.dispose();
    super.dispose();
  }

  String _orEq(String column, List<String> values) =>
      values.map((v) => "$column.eq.$v").join(',');

  double? _toDoubleOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final cleaned = t.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<Map<String, String>> _ensureOptionIds({
    required String table,
    required List<String> names,
  }) async {
    final uniqueNames =
        names.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
    if (uniqueNames.isEmpty) return {};

    final existing = await _sb
        .from(table)
        .select('id,name')
        .or(_orEq('name', uniqueNames)) as List;

    final Map<String, String> byName = {
      for (final r in existing) (r['name'] as String): (r['id'] as String),
    };

    final missing = uniqueNames.where((n) => !byName.containsKey(n)).toList();
    if (missing.isNotEmpty) {
      final inserted = await _sb
          .from(table)
          .insert(missing.map((n) => {'name': n}).toList())
          .select('id,name') as List;
      for (final r in inserted) {
        byName[r['name'] as String] = r['id'] as String;
      }
    }

    return byName;
  }

  /// Loads existing room data and PREFILLS controllers + inclusions + preferences
  Future<void> _loadExistingRoomData() async {
    if (!mounted) return;
    setState(() => _loadingExisting = true);

    try {
      // ✅ UPDATED: include water_per_head, per_watt_price
      final room = await _sb
          .from('rooms')
          .select(
            'floor_number, apartment_name, location, monthly_payment, advance_deposit, '
            'water_per_head, per_watt_price, '
            'description, room_name',
          )
          .eq('id', widget.roomId)
          .maybeSingle();

      if (room == null) {
        debugPrint('EditRoom: rooms row not found for id=${widget.roomId}');
      } else {
        if (!_prefilledOnce) {
          floorCtrl.text = (room['floor_number'] ?? '').toString();
          apartmentNameCtrl.text = (room['apartment_name'] ?? '').toString();
          locationCtrl.text = (room['location'] ?? '').toString();
          monthlyCtrl.text = (room['monthly_payment'] ?? '').toString();
          depositCtrl.text = (room['advance_deposit'] ?? '').toString();
          descCtrl.text = (room['description'] ?? '').toString();
          roomNameCtrl.text = (room['room_name'] ?? '').toString();

          // ✅ NEW: prefill pricing
          waterPerHeadCtrl.text = (room['water_per_head'] ?? '').toString();
          perWattPriceCtrl.text = (room['per_watt_price'] ?? '').toString();

          // override apartment name with latest from landlord_profile
          try {
            final uid = _sb.auth.currentUser?.id;
            if (uid != null) {
              final profile = await _sb
                  .from('landlord_profile')
                  .select('apartment_name')
                  .eq('user_id', uid)
                  .maybeSingle();

              final profileApt =
                  (profile?['apartment_name'] ?? '').toString().trim();
              if (profileApt.isNotEmpty) {
                apartmentNameCtrl.text = profileApt;
              }
            }
          } catch (e, st) {
            debugPrint(
                'Failed to override apartment_name from landlord_profile: $e\n$st');
          }

          _prefilledOnce = true;
        }
      }

      // Inclusions
      final loadedInclusions = <String>[];
      try {
        final incRows = await _sb
            .from('room_inclusions')
            .select('inclusion_options(name)')
            .eq('room_id', widget.roomId);

        for (final row in (incRows as List? ?? const [])) {
          final rel = row['inclusion_options'];
          if (rel is Map && rel['name'] != null) {
            final name = rel['name'].toString().trim();
            if (name.isNotEmpty) loadedInclusions.add(name);
          }
        }
      } catch (e, st) {
        debugPrint('Failed to load inclusions: $e\n$st');
      }

      // Preferences
      final loadedPreferences = <String>[];
      try {
        final prefRows = await _sb
            .from('room_preferences')
            .select('preference_options(name)')
            .eq('room_id', widget.roomId);

        for (final row in (prefRows as List? ?? const [])) {
          final rel = row['preference_options'];
          if (rel is Map && rel['name'] != null) {
            final name = rel['name'].toString().trim();
            if (name.isNotEmpty) loadedPreferences.add(name);
          }
        }
      } catch (e, st) {
        debugPrint('Failed to load preferences: $e\n$st');
      }

      // Images
      final imgs = await _sb
          .from('room_images')
          .select('image_url, sort_order')
          .eq('room_id', widget.roomId)
          .order('sort_order', ascending: true);

      final urls = List<String?>.filled(3, null);
      for (final row in (imgs as List? ?? const [])) {
        final url = row['image_url']?.toString();
        if (url == null) continue;

        final so = row['sort_order'];
        final idx = (so is int) ? so : (int.tryParse(so?.toString() ?? '') ?? 0);
        if (idx >= 0 && idx < 3) urls[idx] = url;
      }

      // Prefill Tenant Match dropdowns
      final newPrefValues = Map<String, String>.from(prefDropdownValues);

      newPrefValues['WiFi'] = loadedInclusions.contains('WiFi') ? 'Yes' : 'No';
      newPrefValues['Common CR'] =
          loadedInclusions.contains('Common CR') ? 'Yes' : 'No';

      newPrefValues['Pet-Friendly'] =
          loadedPreferences.contains('Pet-Friendly') ? 'Yes' : 'No';
      newPrefValues['Open to all'] =
          loadedPreferences.contains('Open to all') ? 'Yes' : 'No';

      if (loadedPreferences.contains('Non-Smoker Only')) {
        newPrefValues['Smoking'] = 'Non-Smoker Only';
      } else if (loadedPreferences.contains('Smoker Allowed')) {
        newPrefValues['Smoking'] = 'Smoker Allowed';
      }

      final occOptions = prefDropdownOptions['Occupation'] ?? const <String>[];
      String occVal = newPrefValues['Occupation'] ?? 'Others';
      for (final o in occOptions) {
        if (loadedPreferences.contains(o)) {
          occVal = o;
          break;
        }
      }
      newPrefValues['Occupation'] = occVal;

      final locOptions = prefDropdownOptions['Location'] ?? const <String>[];
      String locVal = newPrefValues['Location'] ?? 'Any';
      for (final o in locOptions) {
        if (loadedPreferences.contains(o)) {
          locVal = o;
          break;
        }
      }
      newPrefValues['Location'] = locVal;

      if (!mounted) return;
      setState(() {
        inclusions = loadedInclusions;
        preferences = loadedPreferences;
        _remoteImageUrls = urls;
        prefDropdownValues = newPrefValues;
        _clearedSlots[0] = _clearedSlots[1] = _clearedSlots[2] = false;
      });
    } catch (e, st) {
      debugPrint('Failed to load existing room data: $e\n$st');
    } finally {
      if (!mounted) return;
      setState(() => _loadingExisting = false);
    }
  }

  // -------------------- SAVE LOGIC --------------------

  Future<void> _saveRoom() async {
    if (_saving) return;
    if (widget.roomId.isEmpty) {
      InfoToastModal.show(context, 'Missing room id.');
      return;
    }

    final floorText = floorCtrl.text.trim();
    final roomName = roomNameCtrl.text.trim();
    final apartmentName = apartmentNameCtrl.text.trim();
    final location = locationCtrl.text.trim();
    final monthlyText = monthlyCtrl.text.trim();
    final depositText = depositCtrl.text.trim();
    final description = descCtrl.text.trim();

    // ✅ NEW pricing texts
    final waterText = waterPerHeadCtrl.text.trim();
    final wattText = perWattPriceCtrl.text.trim();

    if (roomName.isEmpty ||
        apartmentName.isEmpty ||
        location.isEmpty ||
        floorText.isEmpty ||
        monthlyText.isEmpty ||
        depositText.isEmpty) {
      InfoToastModal.show(context, 'Please fill in all required fields.');
      return;
    }

    final floor = int.tryParse(floorText);
    final monthly = double.tryParse(monthlyText);
    final deposit = double.tryParse(depositText);

    // ✅ NEW: parse optional pricing
    final waterVal = _toDoubleOrNull(waterText);
    final wattVal = _toDoubleOrNull(wattText);

    if (floor == null || monthly == null || deposit == null) {
      InfoToastModal.show(context, 'Invalid number values.');
      return;
    }

    if (waterText.isNotEmpty && waterVal == null) {
      InfoToastModal.show(context, 'Invalid Water per head.');
      return;
    }
    if (wattText.isNotEmpty && wattVal == null) {
      InfoToastModal.show(context, 'Invalid Per watts price.');
      return;
    }

    setState(() => _saving = true);

    try {
      // ✅ UPDATED: save water_per_head and per_watt_price to rooms
      await _sb.from('rooms').update({
        'floor_number': floor,
        'room_name': roomName,
        'apartment_name': apartmentName,
        'location': location,
        'monthly_payment': monthly,
        'advance_deposit': deposit,
        'water_per_head': waterVal,
        'per_watt_price': wattVal,
        'description': description,
      }).eq('id', widget.roomId);

      // Inclusions/Preferences link tables
      final originalInclusions = List<String>.from(inclusions);

      final derivedPrefs = _derivedPreferenceLabels();
      final derivedIncs = _derivedInclusionLabels();

      final finalInclusions = {
        ...originalInclusions,
        ...derivedIncs,
      }.toList();

      final finalPreferences = derivedPrefs;

      final incIdByName = await _ensureOptionIds(
        table: 'inclusion_options',
        names: finalInclusions,
      );
      final prefIdByName = await _ensureOptionIds(
        table: 'preference_options',
        names: finalPreferences,
      );

      await _sb.from('room_inclusions').delete().eq('room_id', widget.roomId);
      await _sb.from('room_preferences').delete().eq('room_id', widget.roomId);

      if (incIdByName.isNotEmpty) {
        await _sb.from('room_inclusions').insert([
          for (final n in incIdByName.keys)
            {
              'room_id': widget.roomId,
              'inclusion_id': incIdByName[n],
            }
        ]);
      }

      if (prefIdByName.isNotEmpty) {
        await _sb.from('room_preferences').insert([
          for (final n in prefIdByName.keys)
            {
              'room_id': widget.roomId,
              'preference_id': prefIdByName[n],
            }
        ]);
      }

      await _uploadImages(widget.roomId);

      if (!mounted) return;

      InfoToastModal.show(context, 'Room details saved.');
      Navigator.pop(context);
    } catch (e, st) {
      debugPrint('Failed to save room: $e\n$st');
      if (mounted) {
        InfoToastModal.show(context, 'Failed to save room: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadImages(String roomId) async {
    try {
      final storage = _sb.storage.from('room-images');

      for (var i = 0; i < roomImages.length; i++) {
        final file = roomImages[i];
        if (file == null) continue;

        final pathParts = file.path.split('.');
        final ext = pathParts.length > 1 ? pathParts.last : 'jpg';
        final fileName =
            '$roomId-${DateTime.now().millisecondsSinceEpoch}-$i.$ext';
        final storagePath = '$roomId/$fileName';

        await storage.upload(storagePath, file);
        final publicUrl = storage.getPublicUrl(storagePath);

        await _sb.from('room_images').upsert(
          {
            'room_id': roomId,
            'image_url': publicUrl,
            'storage_path': storagePath,
            'sort_order': i,
          },
          onConflict: 'room_id,sort_order',
        );

        _clearedSlots[i] = false;
      }

      for (var i = 0; i < roomImages.length; i++) {
        if (_clearedSlots[i] && roomImages[i] == null) {
          await _sb
              .from('room_images')
              .delete()
              .eq('room_id', roomId)
              .eq('sort_order', i);
        }
      }
    } catch (e, st) {
      debugPrint('Failed to upload/delete images: $e\n$st');
    }
  }

  // ---------- Helpers derived from Tenant Match ----------

  List<String> _derivedPreferenceLabels() {
    final prefs = <String>[];

    if (prefDropdownValues['Pet-Friendly'] == 'Yes') {
      prefs.add('Pet-Friendly');
    }
    if (prefDropdownValues['Open to all'] == 'Yes') {
      prefs.add('Open to all');
    }

    final smoke = prefDropdownValues['Smoking'] ?? '';
    if (smoke.isNotEmpty) {
      prefs.add(smoke);
    }

    final occ = prefDropdownValues['Occupation'] ?? 'Others';
    if (!['', 'Others'].contains(occ)) {
      prefs.add(occ);
    }

    final loc = prefDropdownValues['Location'] ?? 'Any';
    if (!['', 'Any'].contains(loc)) {
      prefs.add(loc);
    }

    return prefs;
  }

  List<String> _derivedInclusionLabels() {
    final incs = <String>[];

    if (prefDropdownValues['WiFi'] == 'Yes') {
      incs.add('WiFi');
    }
    if (prefDropdownValues['Common CR'] == 'Yes') {
      incs.add('Common CR');
    }

    return incs;
  }

  // ---------- UI helpers ----------

  void _removeImage(int index) {
    setState(() {
      roomImages[index] = null;
      _remoteImageUrls[index] = null;
      _clearedSlots[index] = true;
    });
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

  Widget _buildImagesRow() {
    return Row(
      children: List.generate(3, (index) {
        final localFile = roomImages[index];
        final remoteUrl = _remoteImageUrls[index];
        final hasImage = localFile != null || remoteUrl != null;

        return Expanded(
          child: InkWell(
            onTap: () => _pickImage(index),
            borderRadius: BorderRadius.circular(12),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: Container(
              margin: EdgeInsets.only(right: index < 2 ? 10 : 0),
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD1D5DB)),
                image: localFile != null
                    ? DecorationImage(
                        image: FileImage(localFile), fit: BoxFit.cover)
                    : null,
              ),
              child: Stack(
                children: [
                  if (localFile == null && remoteUrl != null)
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(remoteUrl, fit: BoxFit.cover),
                      ),
                    ),
                  if (!hasImage)
                    const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
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
                  if (hasImage) ...[
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
                          '#${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      left: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  // ---------- Tenant Match UI ----------

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

  // ✅ NEW: Bottom Save Button Bar
  Widget _bottomSaveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: (_saving || _loadingExisting) ? null : _saveRoom,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005B96),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),

      // ✅ NEW: Save button pinned at bottom
      bottomNavigationBar: _bottomSaveBar(),

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              "EDIT ROOM INFO",
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
                    // ✅ UPDATED: extra bottom padding so content won't hide behind Save button
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
                    child: Column(
                      children: [
                        if (_loadingExisting)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 3),
                          ),

                        _sectionCard(
                          title: "Room Media",
                          subtitle: "Upload up to 3 images for this room.",
                          icon: Icons.photo_library_outlined,
                          children: [
                            _fieldLabel('Room Images'),
                            _buildImagesRow(),
                          ],
                        ),

                        _sectionCard(
                          title: "Room Details",
                          subtitle:
                              "Basic details such as floor, room name, pricing, and location.",
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

                            _fieldLabel('Apartment Name'),
                            _buildTextField(
                              Icons.apartment,
                              "Apartment Name",
                              controller: apartmentNameCtrl,
                              readOnly: true,
                            ),

                            _fieldLabel('Location'),
                            _buildTextField(
                              Icons.location_on,
                              "Address",
                              controller: locationCtrl,
                              readOnly: true,
                            ),

                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Monthly Payment'),
                                      _buildTextField(
                                        Icons.payments,
                                        "Enter Monthly Payment",
                                        isNumber: true,
                                        controller: monthlyCtrl,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Advance Deposit'),
                                      _buildTextField(
                                        Icons.money,
                                        "Enter Advance Deposit",
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

                            // ✅ NEW ROW: Water + Watts
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Water per head'),
                                      _buildTextField(
                                        Icons.water_drop_outlined,
                                        "₱ Water per head",
                                        isDecimal: true,
                                        controller: waterPerHeadCtrl,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _fieldLabel('Per watts price'),
                                      _buildTextField(
                                        Icons.bolt_outlined,
                                        "₱ Per watts price",
                                        isDecimal: true,
                                        controller: perWattPriceCtrl,
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
                          subtitle:
                              "Specify what is included and define who you're looking for.",
                          icon: Icons.tune_outlined,
                          children: [
                            _fieldLabel('Inclusions'),
                            _buildMultiSelect(
                              icon: Icons.chair,
                              hint: "Choose Inclusion",
                              options: inclusionOptions,
                              selectedValues: inclusions,
                              onConfirm: (selected) {
                                setState(() => inclusions = selected);
                              },
                            ),
                            const SizedBox(height: 6),
                            _fieldLabel('Tenant Match (Dropdowns)'),
                            _tenantMatchCard(),
                          ],
                        ),

                        _sectionCard(
                          title: "Description",
                          subtitle: "Add notes, rules, nearby landmarks, and more.",
                          icon: Icons.notes_outlined,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: TextField(
                                controller: descCtrl,
                                maxLines: 8,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: "Description...",
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
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(int index) async {
    try {
      final XFile? pickedFile =
          await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          roomImages[index] = File(pickedFile.path);
          _clearedSlots[index] = false;
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  // ✅ UPDATED: supports decimals too + leading widget (₱)
  Widget _buildTextField(
    IconData icon,
    String hint, {
    bool isNumber = false,
    bool isDecimal = false,
    TextEditingController? controller,
    bool readOnly = false,

    // ✅ NEW
    Widget? leading,
  }) {
    final inputFormatters = <TextInputFormatter>[];
    TextInputType keyboardType = TextInputType.text;

    if (isDecimal) {
      keyboardType = const TextInputType.numberWithOptions(decimal: true);
      inputFormatters.add(
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,4}$')),
      );
    } else if (isNumber) {
      keyboardType = TextInputType.number;
      inputFormatters.add(FilteringTextInputFormatter.digitsOnly);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: readOnly ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          // ✅ If leading provided (₱), it replaces the icon slot
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
