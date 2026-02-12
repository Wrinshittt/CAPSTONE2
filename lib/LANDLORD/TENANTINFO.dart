import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_finder/LANDLORD/chatL.dart' show LandlordChatScreen;

class Tenantinfo extends StatefulWidget {
  const Tenantinfo({super.key, required this.tenantData});

  /// Row stub from the list (must include at least id, room_id, landlord_id)
  final Map<String, dynamic> tenantData;

  @override
  State<Tenantinfo> createState() => _TenantinfoState();
}

class _TenantinfoState extends State<Tenantinfo> {
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _tenant; // fresh room_tenants row
  Map<String, dynamic>? _room; // fresh rooms row
  bool _loading = true;
  bool _openingChat = false;
  bool _deactivating = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // ----------------- data -----------------

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final landlordId = _sb.auth.currentUser?.id;
      if (landlordId == null) {
        _toast('Not signed in.');
        setState(() => _loading = false);
        return;
      }

      final incoming = widget.tenantData;
      final tenantRowId = (incoming['id'] ?? '').toString();
      final roomIdHint = (incoming['room_id'] ?? '').toString();

      Map<String, dynamic>? freshTenant;
      if (tenantRowId.isNotEmpty) {
        final t = await _sb
            .from('room_tenants')
            .select(
              'id, room_id, landlord_id, tenant_user_id, full_name, email, phone, '
              'address, parent_contact, room_no, floor_no, start_date, end_date, '
              'status, profile_image_url',
            )
            .eq('id', tenantRowId)
            .eq('landlord_id', landlordId)
            .maybeSingle();

        if (t is Map<String, dynamic>) freshTenant = t;
      }

      Map<String, dynamic>? freshRoom;
      final rid = (freshTenant?['room_id'] ?? roomIdHint).toString();
      if (rid.isNotEmpty) {
        final r = await _sb
            .from('rooms')
            .select(
              'id, apartment_name, floor_number, location, monthly_payment, availability_status',
            )
            .eq('id', rid)
            .maybeSingle();
        if (r is Map<String, dynamic>) freshRoom = r;
      }

      setState(() {
        _tenant = freshTenant ?? Map<String, dynamic>.from(widget.tenantData);
        _room = freshRoom;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String _fmtDate(dynamic iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      return DateFormat('yyyy-MM-dd').format(d);
    } catch (_) {
      return iso.toString();
    }
  }

  // ----------------- actions -----------------

  Future<void> _openMessage() async {
    if (_openingChat) return;
    setState(() => _openingChat = true);
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) {
        _toast('Not signed in.');
        return;
      }

      // Require a real linked user for the tenant to actually receive the chat.
      final tenantUserId = (_tenant?['tenant_user_id'] ?? '').toString().trim();
      if (tenantUserId.isEmpty) {
        _toast(
          'Link this tenant to a real account (tenant_user_id) before messaging.',
        );
        return;
      }

      // Non-null cid
      String cid = '';

      // Try existing conversation
      final existing = await _sb
          .from('conversations')
          .select('id')
          .eq('landlord_id', me)
          .eq('tenant_id', tenantUserId)
          .limit(1)
          .maybeSingle();

      if (existing is Map<String, dynamic> && existing['id'] != null) {
        cid = existing['id'].toString();
      } else {
        // Minimal insert — add any required columns your schema needs
        final ins = await _sb
            .from('conversations')
            .insert({
              'landlord_id': me,
              'tenant_id': tenantUserId,
              // include optional columns only if your table requires them
              // 'title': 'Landlord ↔ Tenant',
              // 'other_party_phone': '', // only if NOT NULL in your schema
            })
            .select('id')
            .maybeSingle();

        if (ins is Map<String, dynamic> && ins['id'] != null) {
          cid = ins['id'].toString();
        }
      }

      if (cid.isEmpty) {
        _toast('Could not open/create conversation.');
        return;
      }

      final peerName = (_tenant?['full_name'] ?? 'Tenant').toString();

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LandlordChatScreen(
            conversationId: cid,
            peerName: peerName,
            peerImageAsset: 'assets/images/mykel.png',
          ),
        ),
      );
    } catch (e) {
      _toast('Open chat failed: $e');
    } finally {
      if (mounted) setState(() => _openingChat = false);
    }
  }

  Future<void> _deactivateTenant() async {
    if (_deactivating) return;
    setState(() => _deactivating = true);
    try {
      final tenantRowId = (_tenant?['id'] ?? '').toString();
      final roomId = (_tenant?['room_id'] ?? '').toString();
      if (tenantRowId.isEmpty || roomId.isEmpty) {
        _toast('Missing tenant or room id.');
        return;
      }

      // Write the terminal status 'ended' (now allowed by your CHECK)
      await _sb
          .from('room_tenants')
          .update({
            'status': 'ended',
            'end_date': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', tenantRowId);

      // Flip room back to available (trigger may also do this)
      await _sb
          .from('rooms')
          .update({'availability_status': 'available'})
          .eq('id', roomId);

      _toast('Tenant deactivated, room is now vacant.');
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Deactivate failed: $e');
    } finally {
      if (mounted) setState(() => _deactivating = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF002D4C),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final t = _tenant ?? {};
    final r = _room ?? {};

    final name = (t['full_name'] ?? '—').toString();
    final email = (t['email'] ?? '—').toString();
    final phone = (t['phone'] ?? '—').toString();
    final parent = (t['parent_contact'] ?? '—').toString();
    final addr = (t['address'] ?? '—').toString();

    final start = t['start_date'] != null ? _fmtDate(t['start_date']) : '—';
    final end = t['end_date'] != null ? _fmtDate(t['end_date']) : '—';
    final status = (t['status'] ?? '—').toString();

    final roomNo = (t['room_no'] ?? r['id'] ?? '—').toString();
    final floor = (t['floor_no'] ?? r['floor_number'] ?? '—').toString();
    final apt = (r['apartment_name'] ?? '—').toString();
    final monthly = (r['monthly_payment'] ?? '—').toString();

    final profileUrl = (t['profile_image_url'] ?? '').toString();

    return Scaffold(
      backgroundColor: const Color(0xFF002D4C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'TENANT INFORMATION',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatarCircle(name, profileUrl.isEmpty ? null : profileUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          email,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 120,
                              height: 40,
                              child: ElevatedButton(
                                onPressed: _openingChat ? null : _openMessage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5A7689),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _openingChat ? 'Opening…' : 'Message',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 120,
                              height: 40,
                              child: ElevatedButton(
                                onPressed: _deactivating
                                    ? null
                                    : _deactivateTenant,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF5A7689),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _deactivating ? 'Working…' : 'Deactivate',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
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
              const SizedBox(height: 32),

              Row(
                children: [
                  Expanded(child: _field('Move-In', start)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Move-Out', end)),
                ],
              ),
              _field('Address', addr),
              _field('Phone Number', phone),
              _field('Parent Contact', parent),
              Row(
                children: [
                  Expanded(child: _field('Apartment', apt)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Floor No.', floor)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: _field('Room No.', roomNo)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      'Monthly Rent',
                      monthly == '—' ? '—' : '₱$monthly',
                    ),
                  ),
                ],
              ),
              _field('Status', status),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------- small UI bits -----------------

  Widget _avatarCircle(String name, String? profileUrl) {
    if (profileUrl != null && profileUrl.trim().isNotEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(profileUrl),
      );
    }
    return CircleAvatar(
      radius: 50,
      backgroundColor: Colors.white,
      child: Text(
        _initials(name),
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '—';
    if (parts.length == 1) {
      final s = parts.first;
      return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
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
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
