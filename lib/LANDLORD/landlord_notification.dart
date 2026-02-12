// landlord_notifications.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ROOMINFO.dart';
import 'landlord_bottom_nav.dart';

class LandlordNotificationsPage extends StatefulWidget {
  const LandlordNotificationsPage({super.key});

  @override
  State<LandlordNotificationsPage> createState() =>
      _LandlordNotificationsPageState();
}

class _LandlordNotificationsPageState
    extends State<LandlordNotificationsPage> {
  final supabase = Supabase.instance.client;
  String? get _userId => supabase.auth.currentUser?.id;

  RealtimeChannel? _notifChannel;
  final List<Map<String, dynamic>> _notifs = [];
  int _unread = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeNotifications();
  }

  @override
  void dispose() {
    _notifChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    if (_userId == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    try {
      final data = await supabase
          .from('notifications')
          .select('id,title,body,type,is_read,created_at,room_id,user_id')
          .eq('user_id', _userId!)
          .order('created_at', ascending: false)
          .limit(50);

      _notifs
        ..clear()
        ..addAll((data as List).cast<Map<String, dynamic>>());

      _unread = _notifs.where((n) => (n['is_read'] as bool?) == false).length;

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } on PostgrestException catch (e) {
      debugPrint('Load notifications failed: ${e.message}');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Load notifications error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _subscribeNotifications() {
    if (_userId == null) return;
    _notifChannel?.unsubscribe();
    _notifChannel = supabase.channel('notifs-page-${_userId!}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: _userId!,
        ),
        callback: (payload) {
          final rec = Map<String, dynamic>.from(payload.newRecord);
          if (rec['user_id'] != _userId) return;
          setState(() {
            _notifs.insert(0, rec);
            if (((rec['is_read'] as bool?) ?? false) == false) {
              _unread += 1;
            }
          });
        },
      )
      ..subscribe();
  }

  Future<void> _markAllRead() async {
    if (_userId == null) return;
    try {
      await supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _userId!)
          .eq('is_read', false);

      for (var i = 0; i < _notifs.length; i++) {
        _notifs[i] = {..._notifs[i], 'is_read': true};
      }
      _unread = 0;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Mark all read failed: $e');
    }
  }

  Future<void> _openNotification(Map<String, dynamic> n) async {
    if ((n['is_read'] as bool?) == false) {
      try {
        await supabase
            .from('notifications')
            .update({'is_read': true})
            .eq('id', n['id']);
        final idx = _notifs.indexWhere((e) => e['id'] == n['id']);
        if (idx != -1) _notifs[idx] = {..._notifs[idx], 'is_read': true};
        if (_unread > 0) _unread -= 1;
        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('Mark single read failed: $e');
      }
    }

    final roomId = (n['room_id'] as String?)?.trim();
    if (roomId != null && roomId.isNotEmpty && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => Roominfo(roomId: roomId)),
      );
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  String _formatTimestamp(dynamic raw) {
    final dt = _parseDate(raw);
    if (dt == null) return '';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d  $hh:$mm';
  }

  Color _typeAccentColor(String? type) {
    switch (type) {
      case 'room_rejected':
        return const Color(0xFFDC2626); // red
      case 'room_approved':
        return const Color(0xFF16A34A); // green
      case 'booking':
        return const Color(0xFF2563EB); // blue
      default:
        return const Color(0xFF0EA5E9); // teal/blue
    }
  }

  IconData _typeIcon(String? type) {
    switch (type) {
      case 'room_rejected':
        return Icons.report_gmailerrorred_outlined;
      case 'room_approved':
        return Icons.verified_outlined;
      case 'booking':
        return Icons.event_available_outlined;
      default:
        return Icons.notifications_none;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 12),
            Text(
              'No notifications yet',
              style: TextStyle(
                color: Color(0xFF111827),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'You’ll see updates here when there are changes to your rooms, bookings, or tenants.',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final bool read = (n['is_read'] as bool?) ?? false;
    final String? type = n['type'] as String?;
    final Color accent = _typeAccentColor(type);
    final String timestamp = _formatTimestamp(n['created_at']);

    return InkWell(
      onTap: () => _openNotification(n),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: read ? Colors.white : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: read ? const Color(0xFFE5E7EB) : accent.withOpacity(0.35),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color.fromARGB(15, 0, 0, 0),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon on the left
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withOpacity(0.1),
              ),
              child: Icon(
                _typeIcon(type),
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          // e.g. "Your room is approved" comes from notifications.title
                          n['title'] ?? '',
                          style: TextStyle(
                            color: const Color(0xFF111827),
                            fontSize: 14,
                            fontWeight:
                                read ? FontWeight.w600 : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!read)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n['body'] ?? '',
                    style: const TextStyle(
                      color: Color(0xFF4B5563),
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (type != null && type.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            type.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              color: accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const Spacer(),
                      if (timestamp.isNotEmpty)
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 12,
                              color: Color(0xFF9CA3AF),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              timestamp,
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 11,
                              ),
                            ),
                          ],
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

  Widget _buildList() {
    if (_notifs.isEmpty) return _buildEmptyState();

    return RefreshIndicator(
      color: const Color(0xFF04354B),
      backgroundColor: Colors.white,
      onRefresh: _loadNotifications,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _notifs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final n = _notifs[i];
          return _buildNotificationCard(n);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ⬅️ page background set to white
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.notifications_none,
              color: Colors.white,
            ),
            SizedBox(width: 8),
            Text(
              'NOTIFICATIONS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF04354B),
                  ),
                )
              : Container(
                  color: Colors.white, // ⬅️ list background also white
                  child: _buildList(),
                ),
        ),
      ),
      bottomNavigationBar: const LandlordBottomNav(
        currentIndex: 9,
      ),
    );
  }
}
