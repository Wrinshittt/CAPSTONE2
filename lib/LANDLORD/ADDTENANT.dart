// addtenant.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenants.dart'; // navigate to the list after save

class AddTenant extends StatefulWidget {
  const AddTenant({
    super.key,
    required this.roomId,
    this.apartmentName,
    this.initialRoomNo,
    this.initialFloorNo,
  });

  final String roomId;
  final String? apartmentName;
  final String? initialRoomNo;
  final String? initialFloorNo;

  @override
  State<AddTenant> createState() => _AddTenantState();
}

class _AddTenantState extends State<AddTenant> {
  final _sb = Supabase.instance.client;

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  final _fullName = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _parent = TextEditingController();
  final _roomNo = TextEditingController();
  final _floorNo = TextEditingController();

  final _picker = ImagePicker();
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    if (widget.initialRoomNo != null) _roomNo.text = widget.initialRoomNo!;
    if (widget.initialFloorNo != null) _floorNo.text = widget.initialFloorNo!;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _address.dispose();
    _email.dispose();
    _phone.dispose();
    _parent.dispose();
    _roomNo.dispose();
    _floorNo.dispose();
    super.dispose();
  }

  // ---- helpers

  String? _validate() {
    if (_fullName.text.trim().isEmpty) return 'Full Name is required.';
    if (_email.text.trim().isNotEmpty && !_email.text.contains('@')) {
      return 'Enter a valid email.';
    }
    return null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickProfileImage() async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (picked != null) setState(() => _profileImage = File(picked.path));
    } catch (e) {
      _toast('Image pick failed: $e');
    }
  }

  Future<String?> _uploadProfileImage({required String roomId}) async {
    if (_profileImage == null) return null;

    try {
      // Path: tenant-photos/room_<roomId>/<millis>.jpg
      final filename =
          'room_$roomId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      final bytes = await _profileImage!.readAsBytes();

      await _sb.storage
          .from('tenant-photos')
          .uploadBinary(
            filename,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );

      // Public URL (requires a SELECT policy on storage.objects or signed URL logic)
      return _sb.storage.from('tenant-photos').getPublicUrl(filename);
    } on StorageException catch (e) {
      _toast('Avatar upload skipped (${e.statusCode}).');
      return null;
    } catch (e) {
      _toast('Avatar upload failed: $e');
      return null;
    }
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      _toast(problem);
      return;
    }

    setState(() => _saving = true);
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) {
        _toast('Not signed in.');
        return;
      }

      // 1) Upload avatar (optional)
      final profileUrl = await _uploadProfileImage(roomId: widget.roomId);

      // 2) Insert tenant
      final payload = <String, dynamic>{
        'room_id': widget.roomId,
        'landlord_id': me, // important for ownership/filters
        'full_name': _fullName.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'parent_contact': _parent.text.trim().isEmpty
            ? null
            : _parent.text.trim(),
        'room_no': _roomNo.text.trim().isEmpty ? null : _roomNo.text.trim(),
        'floor_no': _floorNo.text.trim().isEmpty ? null : _floorNo.text.trim(),
        'profile_image_url': profileUrl, // null is fine if upload blocked
        'status': 'active',
        'start_date': DateTime.now().toUtc().toIso8601String(),
        // 'tenant_user_id': null, // set when you link a real user
      };

      await _sb.from('room_tenants').insert(payload);

      // 3) Mark room occupied (defense-in-depth if you also have a trigger)
      await _sb
          .from('rooms')
          .update({'availability_status': 'not_available'})
          .eq('id', widget.roomId);

      _toast('Tenant added. Room marked not available.');

      // 4) Go to Tenants list
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const Tenants()),
        (route) => false,
      );
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002D4C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.apartmentName == null
              ? 'TENANT INFORMATION'
              : 'TENANT • ${widget.apartmentName}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: _profileImage != null
                                ? FileImage(_profileImage!)
                                : null,
                            child: _profileImage == null
                                ? const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: _pickProfileImage,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                padding: const EdgeInsets.all(5),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _field('Full Name', _fullName, requiredField: true),
                    _field('Address', _address),
                    _field(
                      'Email',
                      _email,
                      keyboard: TextInputType.emailAddress,
                    ),
                    _field(
                      'Phone Number',
                      _phone,
                      keyboard: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                    ),
                    _field(
                      'Parent Contact No.',
                      _parent,
                      keyboard: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(child: _field('Room No.', _roomNo)),
                        const SizedBox(width: 12),
                        Expanded(child: _field('Floor No.', _floorNo)),
                      ],
                    ),

                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5A7689),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          _saving ? 'Saving…' : 'Add Tenant',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            if (_saving) const PositionedFillOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    bool requiredField = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextFormField(
              controller: ctrl,
              keyboardType: keyboard,
              inputFormatters: inputFormatters,
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              validator: requiredField
                  ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class PositionedFillOverlay extends StatelessWidget {
  const PositionedFillOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ColoredBox(
        color: Color(0x33000000),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
