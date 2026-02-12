import 'package:flutter/material.dart';

import 'package:smart_finder/LANDLORD/CHAT2.dart';
import 'package:smart_finder/LANDLORD/DASHBOARD.dart';
import 'package:smart_finder/LANDLORD/LSETTINGS.dart';
import 'package:smart_finder/LANDLORD/TENANTS.dart';
import 'package:smart_finder/LANDLORD/TIMELINE.dart';
import 'package:smart_finder/LANDLORD/TOTALROOM.dart';
import 'package:smart_finder/LANDLORD/APARTMENT.dart';
import 'package:smart_finder/BOOKMARK.dart';
import 'package:smart_finder/LANDLORD/landlord_notification.dart';
import 'package:smart_finder/LANDLORD/login.dart';

class LandlordBottomNav extends StatefulWidget {
  final int currentIndex;

  const LandlordBottomNav({
    super.key,
    required this.currentIndex,
  });

  @override
  State<LandlordBottomNav> createState() => _LandlordBottomNavState();
}

class _LandlordBottomNavState extends State<LandlordBottomNav> {
  final ScrollController _scrollController = ScrollController();

  // ✅ Scroll indicator state (copied/adapted from CODE 2)
  bool _showScrollHint = false;
  bool _hintOnRight = true;
  double _lastOffset = 0.0;

  @override
  void initState() {
    super.initState();

    _scrollController.addListener(_updateScrollHint);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelected();
      _updateScrollHint();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollHint);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected() {
    if (!_scrollController.hasClients) return;

    final double targetOffset = (widget.currentIndex * 88).toDouble();
    final max = _scrollController.position.maxScrollExtent;

    _scrollController.animateTo(
      targetOffset.clamp(0.0, max),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ✅ Same scroll hint logic as in TenantBottomNav
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

    // Determine scroll direction via delta
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

  Future<void> _showLogoutConfirmation(BuildContext context) async {
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
                      'You will need to sign in again to access your landlord dashboard and messages.',
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

    if (!shouldLogout) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
      (r) => false,
    );
  }

  void _onNavTap(BuildContext context, int index) {
    if (index == widget.currentIndex) return;

    Widget? target;

    switch (index) {
      case 0:
        target = const Dashboard();
        break;
      case 1:
        target = const Timeline();
        break;
      case 2:
        target = const Apartment();
        break;
      case 3:
        target = const Tenants();
        break;
      case 4:
        target = const ListChat();
        break;
      case 5:
        target = const TotalRoom();
        break;
      case 6:
        target = const Bookmark();
        break;
      case 7:
        target = const LandlordSettings();
        break;
      case 8:
        _showLogoutConfirmation(context);
        return;
    }

    if (target != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => target!),
      );
    }
  }

  /// Notification button placed after Bookmark, now styled + highlighted like other icons.
  /// Uses `currentIndex == 9` to mark it as selected.
  Widget _buildNotificationItem(BuildContext context) {
    const Color selectedBlue = Color(0xFF2563EB);
    final bool isSelected = widget.currentIndex == 9;

    return GestureDetector(
      onTap: () {
        if (widget.currentIndex == 9) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const LandlordNotificationsPage(),
          ),
        );
      },
      child: SizedBox(
        width: 88,
        height: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? selectedBlue : Colors.transparent,
                border: isSelected
                    ? null
                    : Border.all(color: Colors.black38, width: 1),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.notifications_none,
                size: 18,
                color: isSelected ? Colors.white : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Notification',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? selectedBlue : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Build nav items so we can inject the notification right after Bookmark (index 6)
    final List<Widget> navItems = [];

    for (int index = 0; index < 9; index++) {
      IconData icon;
      String label;

      switch (index) {
        case 0:
          icon = Icons.dashboard;
          label = "Dashboard";
          break;
        case 1:
          icon = Icons.view_timeline_outlined;
          label = "Timeline";
          break;
        case 2:
          icon = Icons.apartment;
          label = "Apartment";
          break;
        case 3:
          icon = Icons.group;
          label = "Tenants";
          break;
        case 4:
          icon = Icons.message;
          label = "Message";
          break;
        case 5:
          icon = Icons.door_front_door;
          label = "Rooms";
          break;
        case 6:
          icon = Icons.bookmark;
          label = "Bookmark";
          break;
        case 7:
          icon = Icons.settings;
          label = "Settings";
          break;
        case 8:
          icon = Icons.logout;
          label = "Logout";
          break;
        default:
          icon = Icons.circle;
          label = "";
      }

      final bool isSelected = widget.currentIndex == index;
      const Color selectedBlue = Color(0xFF2563EB);

      navItems.add(
        GestureDetector(
          onTap: () => _onNavTap(context, index),
          child: SizedBox(
            width: 88,
            height: 70,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? selectedBlue : Colors.transparent,
                    border: isSelected
                        ? null
                        : Border.all(color: Colors.black38, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 18,
                    color: isSelected ? Colors.white : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? selectedBlue : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Insert notification button immediately after Bookmark (index 6)
      if (index == 6) {
        navItems.add(_buildNotificationItem(context));
      }
    }

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
              child: Row(children: navItems),
            ),
          ),

          // ✅ Scroll hint overlay (same behavior as CODE 2)
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
