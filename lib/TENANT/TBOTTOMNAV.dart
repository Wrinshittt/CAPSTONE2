// lib/TENANT/TBOTTOMNAV.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/TENANT/TBOOKMARK.dart';

class TenantNavIndex {
  static const int apartment = 0;
  static const int message = 1;
  static const int settings = 2;
  static const int myRoom = 3;
  static const int bookmark = 4;
  static const int logout = 5;
}

class TenantBottomNav extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onItemSelected;

  const TenantBottomNav({
    super.key,
    required this.currentIndex,
    required this.onItemSelected,
  });

  @override
  State<TenantBottomNav> createState() => _TenantBottomNavState();
}

class _TenantBottomNavState extends State<TenantBottomNav> {
  final ScrollController _scrollController = ScrollController();
  final _sb = Supabase.instance.client;

  bool _hasUnreadMessage = false;
  RealtimeChannel? _unreadChannel;

  bool _showScrollHint = false;
  bool _hintOnRight = true;

  // ✅ Track last scroll offset (so we don't rely on userScrollDirection)
  double _lastOffset = 0.0;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_updateScrollHint);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
      _updateScrollHint();
    });

    _loadUnreadFlag();
    _subscribeUnread();
  }

  @override
  void didUpdateWidget(covariant TenantBottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollHint();
    });

    if (widget.currentIndex == TenantNavIndex.message &&
        oldWidget.currentIndex != TenantNavIndex.message) {
      _loadUnreadFlag();
    }
  }

  @override
  void dispose() {
    if (_unreadChannel != null) _sb.removeChannel(_unreadChannel!);
    _scrollController.removeListener(_updateScrollHint);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollHint() {
    if (!_scrollController.hasClients) return;

    final pos = _scrollController.position;
    final max = pos.maxScrollExtent;
    final offset = pos.pixels;

    if (max <= 0) {
      if (_showScrollHint) {
        setState(() {
          _showScrollHint = false;
          _hintOnRight = true;
        });
      }
      _lastOffset = offset;
      return;
    }

    const eps = 2.0;
    final atLeft = offset <= eps;
    final atRight = offset >= (max - eps);

    // ✅ Determine scroll direction using delta (fixes ScrollDirection enum issues)
    final delta = offset - _lastOffset;

    bool newHintOnRight = _hintOnRight;

    // Flip instantly at edges
    if (atRight) {
      newHintOnRight = false; // show on LEFT
    } else if (atLeft) {
      newHintOnRight = true; // show on RIGHT
    } else {
      // In the middle: follow direction
      if (delta > 0) {
        newHintOnRight = true; // scrolling right
      } else if (delta < 0) {
        newHintOnRight = false; // scrolling left
      }
    }

    final newShow = true;

    _lastOffset = offset;

    if (!mounted) return;
    if (newShow != _showScrollHint || newHintOnRight != _hintOnRight) {
      setState(() {
        _showScrollHint = newShow;
        _hintOnRight = newHintOnRight;
      });
    }
  }

  void _scrollToSelected() {
    final double targetOffset = (widget.currentIndex * 88).toDouble();
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadUnreadFlag() async {
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) {
        if (!mounted) return;
        setState(() => _hasUnreadMessage = false);
        return;
      }

      final data = await _sb
          .from('tenant_inbox')
          .select('unread_for_tenant')
          .eq('tenant_id', me);

      final list = List<Map<String, dynamic>>.from(data as List);
      final hasUnread = list.any((r) {
        final v = int.tryParse('${r['unread_for_tenant'] ?? 0}') ?? 0;
        return v > 0;
      });

      if (!mounted) return;
      setState(() => _hasUnreadMessage = hasUnread);
    } catch (_) {}
  }

  void _subscribeUnread() {
    final ch = _sb.channel('tenant-unread-dot');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'tenant_inbox',
      callback: (_) => _loadUnreadFlag(),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'tenant_inbox',
      callback: (_) => _loadUnreadFlag(),
    );

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (_) => _loadUnreadFlag(),
    );
    ch.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (_) => _loadUnreadFlag(),
    );

    ch.subscribe();
    _unreadChannel = ch;
  }

  /// ✅ Confirmation modal copied from LandlordBottomNav and adapted
  Future<bool> _showLogoutConfirmation(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 40),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFEF4444).withOpacity(0.1),
                      ),
                      child: const Icon(
                        Icons.logout_rounded,
                        color: Color(0xFFEF4444),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Log out of Smart Finder?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You will need to sign in again to access your tenant dashboard and messages.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Color(0xFFE5E7EB),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 11),
                            ),
                            child: const Text(
                              'Log out',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ) ??
        false;

    return shouldLogout;
  }

  Future<void> _onTap(int index) async {
    if (index == widget.currentIndex) return;

    // ✅ Intercept Logout to show confirmation modal (like CODE 2)
    if (index == TenantNavIndex.logout) {
      final shouldLogout = await _showLogoutConfirmation(context);
      if (!shouldLogout) return;

      // Let parent handle actual logout navigation / logic
      widget.onItemSelected(index);
      return;
    }

    if (index == TenantNavIndex.bookmark) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantBookmark()),
      );
      return;
    }

    widget.onItemSelected(index);

    if (index == TenantNavIndex.message) {
      _loadUnreadFlag();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
      _updateScrollHint();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (_) {
              _updateScrollHint();
              return false;
            },
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(6, (index) {
                  IconData icon;
                  String label;

                  switch (index) {
                    case TenantNavIndex.apartment:
                      icon = Icons.apartment;
                      label = "Apartment";
                      break;
                    case TenantNavIndex.message:
                      icon = Icons.message;
                      label = "Message";
                      break;
                    case TenantNavIndex.settings:
                      icon = Icons.settings;
                      label = "Settings";
                      break;
                    case TenantNavIndex.myRoom:
                      icon = Icons.door_front_door;
                      label = "My Room";
                      break;
                    case TenantNavIndex.bookmark:
                      icon = Icons.bookmark;
                      label = "Bookmark";
                      break;
                    case TenantNavIndex.logout:
                      icon = Icons.logout;
                      label = "Logout";
                      break;
                    default:
                      icon = Icons.circle;
                      label = "";
                  }

                  final bool isSelected = widget.currentIndex == index;
                  const Color selectedBlue = Color(0xFF2563EB);

                  final bool showUnreadDot =
                      (index == TenantNavIndex.message) && _hasUnreadMessage;

                  return GestureDetector(
                    onTap: () => _onTap(index),
                    child: SizedBox(
                      width: 88,
                      height: 70,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? selectedBlue
                                      : Colors.transparent,
                                  border: isSelected
                                      ? null
                                      : Border.all(
                                          color: Colors.black38,
                                          width: 1,
                                        ),
                                ),
                                alignment: Alignment.center,
                                child: Icon(
                                  icon,
                                  size: 18,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black54,
                                ),
                              ),
                              if (showUnreadDot)
                                Positioned(
                                  top: -2,
                                  right: -2,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: const BoxDecoration(
                                      color: Colors.redAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isSelected ? selectedBlue : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          if (_showScrollHint)
            Positioned(
              left: _hintOnRight ? null : 0,
              right: _hintOnRight ? 0 : null,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: _hintOnRight
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      end: _hintOnRight
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      colors: [
                        Colors.white.withOpacity(0),
                        Colors.white,
                      ],
                    ),
                  ),
                  child: Icon(
                    _hintOnRight
                        ? Icons.keyboard_arrow_right
                        : Icons.keyboard_arrow_left,
                    size: 18,
                    color: Colors.black38,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
