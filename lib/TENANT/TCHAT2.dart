// TENANT/TCHAT2.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_finder/TENANT/CHAT.dart';

import 'package:smart_finder/TENANT/TAPARTMENT.dart';
import 'package:smart_finder/TENANT/TSETTINGS.dart';
import 'package:smart_finder/TENANT/TMYROOM.dart';
import 'package:smart_finder/TENANT/TLOGIN.dart';
import 'package:smart_finder/BOOKMARK.dart';

// 🔹 Shared tenant bottom navigation
import 'package:smart_finder/TENANT/TBOTTOMNAV.dart';

/// ✅ Global in-memory cache of conversations that were opened (treated as read)
/// This survives navigation between pages as long as the app stays in memory.
final Set<String> _locallyClearedTenantConversations = {};

class TenantListChat extends StatefulWidget {
  const TenantListChat({super.key});

  @override
  State<TenantListChat> createState() => _TenantListChatState();
}

class _TenantListChatState extends State<TenantListChat> {
  final _sb = Supabase.instance.client;

  String searchQuery = '';

  /// 🔹 Message tab index for tenant nav
  int _selectedIndex = TenantNavIndex.message;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  /// landlord_id -> { name, avatar_url }
  final Map<String, Map<String, String?>> _landlords = {};

  RealtimeChannel? _channel;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _sb.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) {
        setState(() {
          _rows = [];
          _loading = false;
        });
        return;
      }

      // Pull tenant inbox rows
      final data = await _sb
          .from('tenant_inbox')
          .select(
            'conversation_id, tenant_id, landlord_id, last_message, last_time, unread_for_tenant',
          )
          .eq('tenant_id', me)
          .order('last_time', ascending: false);

      final list = List<Map<String, dynamic>>.from(data as List);
      _rows = list;

      // Bulk-fetch landlord display info (name) then build avatar URL from bucket
      final ids = list
          .map((r) => r['landlord_id'])
          .where((e) => e != null)
          .map((e) => e.toString())
          .toSet()
          .toList();

      _landlords.clear();

      if (ids.isNotEmpty) {
        final u =
            await _sb.from('users').select('id, full_name').inFilter('id', ids);

        final storage = _sb.storage.from('avatars');
        for (final row in (u as List)) {
          final id = row['id'].toString();
          final name = (row['full_name'] as String?)?.trim();
          final jpg = storage.getPublicUrl('$id.jpg');
          _landlords[id] = {
            'name': name,
            'avatar_url': jpg, // UI will fallback to icon if missing
          };
        }
      }

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load chats: $e';
        _loading = false;
      });
    }
  }

  void _subscribe() {
    final ch = _sb.channel('inbox-tenant');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (_) => _load(),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (_) => _load(),
    );

    ch.subscribe();
    _channel = ch;
  }

  String _formatWhen(DateTime? utc) {
    if (utc == null) return '';
    final t = utc.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(t.year, t.month, t.day);

    if (date == today) return DateFormat('hh:mm a').format(t);
    if (date == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (now.difference(t).inDays < 7) return DateFormat('EEE').format(t);
    return DateFormat('MMM d').format(t);
  }

  // 🔹 Use shared TenantNavIndex for all navigation
  void _onBottomNavSelected(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);

    if (index == TenantNavIndex.apartment) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantApartment()),
      );
    } else if (index == TenantNavIndex.message) {
      // already on Message → do nothing
    } else if (index == TenantNavIndex.settings) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantSettings()),
      );
    } else if (index == TenantNavIndex.myRoom) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MyRoom()),
      );
    } else if (index == TenantNavIndex.bookmark) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Bookmark()),
      );
    } else if (index == TenantNavIndex.logout) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginT()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color pageBg = Color(0xFFF3F4F6);
    const Color appBarColor = Color(0xFF04395E);
    const Color textPrimary = Color(0xFF111827);
    const Color textSecondary = Color(0xFF6B7280);

    final filtered = _rows.where((row) {
      final s = searchQuery.toLowerCase();
      final msg = (row['last_message'] ?? '').toString().toLowerCase();
      final cid = (row['conversation_id'] ?? '').toString().toLowerCase();
      final lid = (row['landlord_id'] ?? '').toString();
      final lname = (_landlords[lid]?['name'] ?? '').toLowerCase();
      return msg.contains(s) || cid.contains(s) || lname.contains(s);
    }).toList();

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'CHAT',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
        backgroundColor: appBarColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Top panel with description + search
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(20),
              ),
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
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 18,
                      color: Color(0xFF9CA3AF),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Chat with landlords and view your conversations.',
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
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
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.search,
                        color: appBarColor,
                      ),
                      hintText: 'Search chats by landlord or message...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 0,
                      ),
                    ),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),

          if (!_loading && _error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),

          if (!_loading && _error == null)
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          constraints: const BoxConstraints(maxWidth: 420),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 36,
                                color: appBarColor,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'No conversations yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'When you message landlords, your chats will appear here.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: textSecondary,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = filtered[index];
                        final last = (row['last_message'] ?? '').toString();

                        DateTime? t;
                        if (row['last_time'] != null) {
                          try {
                            t = DateTime.parse(row['last_time'].toString());
                          } catch (_) {}
                        }

                        final cid =
                            (row['conversation_id'] ?? '').toString();

                        final unreadRaw =
                            int.tryParse('${row['unread_for_tenant'] ?? 0}') ??
                                0;

                        // ✅ Respect local cache so the highlight stays cleared after returning
                        final bool isCleared =
                            _locallyClearedTenantConversations.contains(cid);
                        final int unread = isCleared ? 0 : unreadRaw;
                        final bool hasUnread = unread > 0;

                        final lid = (row['landlord_id'] ?? '').toString();
                        final lInfo = _landlords[lid] ?? const {};
                        final lname = (lInfo['name']?.isNotEmpty == true)
                            ? lInfo['name']!
                            : 'Landlord';
                        final lavatar = lInfo['avatar_url'];

                        final avatarProvider = (lavatar != null &&
                                lavatar.isNotEmpty)
                            ? NetworkImage(lavatar)
                            : const AssetImage('assets/images/mykel.png')
                                as ImageProvider;

                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () async {
                            if (_navigating) return;
                            _navigating = true;
                            try {
                              if (cid.isEmpty) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Missing conversation id'),
                                  ),
                                );
                                return;
                              }

                              // 🔄 Persist unread count to 0 on the backend
                              try {
                                await _sb
                                    .from('tenant_inbox')
                                    .update({'unread_for_tenant': 0})
                                    .eq('conversation_id', cid);
                              } catch (_) {
                                // ignore backend error here; we'll still update UI
                              }

                              // ✅ Mark as cleared locally for this session
                              setState(() {
                                _locallyClearedTenantConversations.add(cid);
                                for (final r in _rows) {
                                  if ((r['conversation_id'] ?? '')
                                          .toString() ==
                                      cid) {
                                    r['unread_for_tenant'] = 0;
                                  }
                                }
                              });

                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreenTenant(
                                    conversationId: cid,
                                    peerName: lname,
                                    peerAvatarUrl: lavatar,
                                    landlordPhone: null,
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Open chat failed: $e'),
                                ),
                              );
                            } finally {
                              _navigating = false;
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundImage: avatarProvider,
                                    onBackgroundImageError: (_, __) {},
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                lname,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontWeight: hasUnread
                                                      ? FontWeight.w700
                                                      : FontWeight.w600,
                                                  fontSize: 14.5,
                                                  color: textPrimary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatWhen(t),
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          last,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: hasUnread
                                                ? textPrimary
                                                : textSecondary,
                                            fontWeight: hasUnread
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (hasUnread) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '$unread',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),

      // 🔹 Shared tenant bottom navigation
      bottomNavigationBar: TenantBottomNav(
        currentIndex: _selectedIndex,
        onItemSelected: _onBottomNavSelected,
      ),
    );
  }
}
