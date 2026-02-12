import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalkInTenantProfile extends StatefulWidget {
  const WalkInTenantProfile({
    super.key,
    required this.roomId,
  });

  final String roomId;

  @override
  State<WalkInTenantProfile> createState() => _WalkInTenantProfileState();
}

class _WalkInTenantProfileState extends State<WalkInTenantProfile> {
  final SupabaseClient _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  String _name = '—';
  String _address = '—';
  String _gender = '—';
  String _phone = '—';

  // ✅ NEW: store walk-in uploaded image url
  String? _walkInIdPhotoUrl;

  // ✅ housing details (from rooms table)
  bool _loadingRoom = false;
  Map<String, dynamic>? _room;

  @override
  void initState() {
    super.initState();
    _loadWalkInTenant();
  }

  String _money(dynamic v) {
    if (v == null) return '—';
    final n = (v is num) ? v.toDouble() : double.tryParse('$v');
    if (n == null) return '—';
    return '₱${n.toStringAsFixed(2)}';
  }

  Future<void> _loadRoomDetails() async {
    if (!mounted) return;
    setState(() => _loadingRoom = true);

    try {
      final room = await _sb
          .from('rooms')
          .select('monthly_payment, advance_deposit, room_name, floor_number')
          .eq('id', widget.roomId)
          .maybeSingle();

      if (!mounted) return;
      setState(() {
        _room = room as Map<String, dynamic>?;
        _loadingRoom = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _room = null;
        _loadingRoom = false;
      });
    }
  }

  Future<void> _loadWalkInTenant() async {
    try {
      final row = await _sb
          .from('room_tenants')
          .select(
            'full_name, address, gender, phone, tenant_user_id, walkin_id_photo_url',
          )
          .eq('room_id', widget.roomId)
          .eq('status', 'active')
          .maybeSingle();

      if (!mounted) return;

      // If there is no active tenant row
      if (row == null) {
        setState(() {
          _loading = false;
          _error = 'No active tenant found for this room.';
        });
        return;
      }

      // This page is ONLY for walk-in tenants (tenant_user_id should be null/empty)
      final tenantUserId = (row['tenant_user_id'] ?? '').toString().trim();
      if (tenantUserId.isNotEmpty) {
        setState(() {
          _loading = false;
          _error =
              'This tenant is an app user. Open the app tenant profile instead.';
        });
        return;
      }

      String clean(dynamic v) {
        final s = (v ?? '').toString().trim();
        return s.isEmpty ? '—' : s;
      }

      final img = (row['walkin_id_photo_url'] ?? '').toString().trim();
      final imgUrl = img.isEmpty ? null : img;

      setState(() {
        _name = clean(row['full_name']);
        _address = clean(row['address']);
        _gender = clean(row['gender']);
        _phone = clean(row['phone']);
        _walkInIdPhotoUrl = imgUrl;

        _loading = false;
        _error = null;
      });

      // ✅ Load housing details after tenant loads
      await _loadRoomDetails();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load walk-in tenant: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF04354B);
    const surface = Color(0xFFF5F7FA);

    // ✅ Housing derived values
    final monthlyRent = _room != null ? _money(_room!['monthly_payment']) : '—';
    final advanceDeposit =
        _room != null ? _money(_room!['advance_deposit']) : '—';
    final roomName =
        _room != null ? (_room!['room_name'] ?? '—').toString() : '—';
    final floorNo = _room != null
        ? (_room!['floor_number'] != null
            ? 'Floor ${_room!['floor_number']}'
            : 'Not set')
        : '—';

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: brand,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text(
          'Walk-in Tenant',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 0.4,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const _LoadingState()
            : (_error != null)
                ? _ErrorState(
                    message: _error!,
                    onRetry: _loadWalkInTenant,
                  )
                : RefreshIndicator(
                    color: brand,
                    onRefresh: () async {
                      await _loadWalkInTenant();
                    },
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        _HeaderCard(
                          title: _name,
                          subtitle: 'Walk-in Tenant Profile',
                          icon: Icons.badge_outlined,
                        ),
                        const SizedBox(height: 14),

                        _SectionCard(
                          title: 'Personal Information',
                          children: [
                            _InfoTile(
                              label: 'Name',
                              value: _name,
                              icon: Icons.person_outline_rounded,
                            ),
                            const SizedBox(height: 10),
                            _InfoTile(
                              label: 'Gender',
                              value: _gender,
                              icon: Icons.wc_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        _SectionCard(
                          title: 'Contact',
                          children: [
                            _InfoTile(
                              label: 'Phone Number',
                              value: _phone,
                              icon: Icons.phone_outlined,
                            ),
                            const SizedBox(height: 10),
                            _InfoTile(
                              label: 'Address',
                              value: _address,
                              icon: Icons.location_on_outlined,
                              maxLines: 3,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        _SectionCard(
                          title: 'Housing Details',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _InfoTile(
                                    label: 'Advance / Deposit',
                                    value: _loadingRoom
                                        ? 'Loading…'
                                        : advanceDeposit,
                                    icon: Icons.account_balance_wallet_outlined,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _InfoTile(
                                    label: 'Monthly Rent',
                                    value:
                                        _loadingRoom ? 'Loading…' : monthlyRent,
                                    icon: Icons.payments_outlined,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _InfoTile(
                                    label: 'Room Name',
                                    value: _loadingRoom ? 'Loading…' : roomName,
                                    icon: Icons.meeting_room_outlined,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _InfoTile(
                                    label: 'Floor No.',
                                    value: _loadingRoom ? 'Loading…' : floorNo,
                                    icon: Icons.stairs_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // ✅ NEW: Display uploaded walk-in image at the bottom
                        _SectionCard(
                          title: 'Uploaded ID / Screenshot',
                          children: [
                            _walkInIdPhotoUrl == null
                                ? const _EmptyPhotoBox(
                                    text:
                                        'No image uploaded yet for this walk-in tenant.',
                                  )
                                : _NetworkPhotoBox(url: _walkInIdPhotoUrl!),
                          ],
                        ),

                        const SizedBox(height: 14),

                        const _FooterNote(
                          text:
                              'Tip: Pull down to refresh if you recently updated tenant details.',
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

/// ---------- UI Components ----------

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 34,
        height: 34,
        child: CircularProgressIndicator(
          strokeWidth: 3.2,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF04354B)),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF04354B);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withOpacity(0.06)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 6),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.redAccent,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Retry',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF04354B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: brand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: brand, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF10B981).withOpacity(0.25),
              ),
            ),
            child: const Text(
              'ACTIVE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: Color(0xFF059669),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFF04354B),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    const brand = Color(0xFF04354B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: brand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: brand, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF04354B).withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF04354B).withOpacity(0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFF04354B),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Color(0xFF04354B),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ Simple placeholder box if there is no photo
class _EmptyPhotoBox extends StatelessWidget {
  const _EmptyPhotoBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.07)),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(14),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

/// ✅ Shows the uploaded image (public URL)
class _NetworkPhotoBox extends StatelessWidget {
  const _NetworkPhotoBox({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black.withOpacity(0.07)),
        ),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            );
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'Failed to load image.\nCheck if the URL is public or the bucket policy allows access.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
