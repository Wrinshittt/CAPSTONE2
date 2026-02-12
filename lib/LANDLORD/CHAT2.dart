import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/APARTMENT.dart';
import 'package:smart_finder/LANDLORD/TOTALROOM.dart';
import 'package:smart_finder/LANDLORD/LSETTINGS.dart';
import 'package:smart_finder/LANDLORD/LOGIN.dart';
import 'package:smart_finder/LANDLORD/TIMELINE.dart';
import 'package:smart_finder/LANDLORD/TENANTS.dart';

import 'package:smart_finder/services/chat_service.dart';
import 'package:smart_finder/LANDLORD/chatL.dart' show LandlordChatScreen;

// ⬇️ NEW: shared landlord bottom navigation
import 'landlord_bottom_nav.dart';

/// ✅ Global in-memory cache of conversations that were opened (treated as read)
/// This survives navigation between pages as long as the app stays in memory.
final Set<String> _locallyClearedConversations = {};

class ListChat extends StatefulWidget {
  const ListChat({super.key});

  @override
  State<ListChat> createState() => _ListChatState();
}

class _ListChatState extends State<ListChat> {
  final _sb = Supabase.instance.client;
  final _chat = ChatService(Supabase.instance.client);

  String searchQuery = '';
  int _selectedIndex = 4;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  RealtimeChannel? _channel;
  bool _navigating = false; // tap guard

  // cache: tenant_id -> {name, avatarUrl}
  final Map<String, Map<String, String>> _tenants = {};

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
    setState(() => _loading = true);
    final me = _sb.auth.currentUser?.id;
    if (me == null) {
      setState(() {
        _rows = [];
        _loading = false;
      });
      return;
    }

    final data = await _sb
        .from('landlord_inbox')
        .select(
          'conversation_id, landlord_id, tenant_id, last_message, last_time, unread_for_landlord',
        )
        .eq('landlord_id', me)
        .order('last_time', ascending: false);

    final rows = List<Map<String, dynamic>>.from(data ?? const []);

    // Build tenant cache (name + avatar public URL from bucket)
    final ids = <String>{
      for (final r in rows)
        if ((r['tenant_id'] ?? '').toString().isNotEmpty)
          r['tenant_id'].toString(),
    }.toList();

    if (ids.isNotEmpty) {
      final users = await _sb
          .from('users')
          .select('id, full_name, first_name, last_name')
          .inFilter('id', ids);

      for (final u in (users as List? ?? const [])) {
        final id = (u['id'] ?? '').toString();
        final full =
            (u['full_name'] ?? '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}')
                .toString()
                .trim();

        final storage = _sb.storage.from('avatars');
        final jpg = storage.getPublicUrl('$id.jpg');
        final png = storage.getPublicUrl('$id.png');
        final avatarUrl = jpg.isNotEmpty ? jpg : png;

        _tenants[id] = {
          'name': full.isEmpty ? 'Tenant' : full,
          'avatarUrl': avatarUrl,
        };
      }
    }

    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  void _subscribe() {
    final ch = _sb.channel('inbox-landlord');
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

  // 🔻 NEW: Logout confirmation dialog (same style as other landlord pages)
  Future<void> _showLogoutConfirmation() async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Log out'),
            content: const Text(
              'Are you sure you want to log out of Smart Finder?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Log out',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldLogout) return;
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
      (r) => false,
    );
  }

  void _onNavTap(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);

    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Dashboard()),
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Timeline()),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Apartment()),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Tenants()),
      );
    } else if (index == 4) {
      // stay
    } else if (index == 5) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TotalRoom()),
      );
    } else if (index == 6) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LandlordSettings()),
      );
    } else if (index == 7) {
      // 🔁 use confirmation instead of direct logout
      _showLogoutConfirmation();
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
      final tenantName =
          _tenants[(row['tenant_id'] ?? '').toString()]?['name'] ?? '';
      return msg.contains(s) ||
          cid.contains(s) ||
          tenantName.toLowerCase().contains(s);
    }).toList();

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        title: const Text(
          'CHAT',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF04354B),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),

      // ✅ Pull-to-refresh (same pattern as TOTALROOM.dart)
      body: RefreshIndicator(
        color: const Color(0xFF04354B),
        onRefresh: () async {
          await _load();
        },
        child: Column(
          children: [
            // Top panel with search
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
                          'View and respond to tenant conversations.',
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
                        hintText: 'Search chats by name or message...',
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
              ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                shrinkWrap: true,
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ],
              ),

            if (!_loading)
              Expanded(
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Container(
                                padding: const EdgeInsets.all(18),
                                constraints:
                                    const BoxConstraints(maxWidth: 420),
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
                                      'When tenants message you, their chats will appear here.',
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
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
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

                          final cid = (row['conversation_id'] ?? '').toString();

                          final unreadRaw =
                              int.tryParse('${row['unread_for_landlord'] ?? 0}') ??
                                  0;

                          // ✅ If this conversation is in the "locally cleared" set,
                          // treat it as read in the UI, even if the DB still shows unread.
                          final bool isLocallyCleared =
                              _locallyClearedConversations.contains(cid);
                          final int unread = isLocallyCleared ? 0 : unreadRaw;
                          final bool hasUnread = unread > 0;

                          final tenantId = (row['tenant_id'] ?? '').toString();
                          final info = _tenants[tenantId] ??
                              const {'name': 'Tenant', 'avatarUrl': ''};
                          final titleName = info['name'] ?? 'Tenant';
                          final avatarUrl = info['avatarUrl'] ?? '';

                          final avatar = (avatarUrl.startsWith('http'))
                              ? NetworkImage(avatarUrl)
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

                                // ✅ Persist "read" state in Supabase
                                try {
                                  await _sb
                                      .from('landlord_inbox')
                                      .update({'unread_for_landlord': 0})
                                      .eq('conversation_id', cid);
                                } catch (_) {
                                  // ignore backend error here; we'll still update UI
                                }

                                // ✅ Mark this conversation as cleared locally
                                setState(() {
                                  _locallyClearedConversations.add(cid);
                                  for (final r in _rows) {
                                    if ((r['conversation_id'] ?? '')
                                            .toString() ==
                                        cid) {
                                      r['unread_for_landlord'] = 0;
                                    }
                                  }
                                });

                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => LandlordChatScreen(
                                      conversationId: cid,
                                      peerName: titleName,
                                      peerAvatarUrl: avatarUrl,
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
                                      backgroundImage: avatar,
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
                                                  titleName,
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
      ),

      // 🔽 Use shared landlord bottom navigation (Message tab = index 4)
      bottomNavigationBar: const LandlordBottomNav(currentIndex: 4),
    );
  }
}
