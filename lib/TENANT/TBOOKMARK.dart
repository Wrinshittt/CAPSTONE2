// lib/TENANT/TBOOKMARK.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ⬇️ Tenant bottom nav + index constants
import 'package:smart_finder/TENANT/TBOTTOMNAV.dart';

// ⬇️ Tenant screens for navigation
import 'package:smart_finder/TENANT/TAPARTMENT.dart';
import 'package:smart_finder/TENANT/TCHAT2.dart';
import 'package:smart_finder/TENANT/TSETTINGS.dart';
import 'package:smart_finder/TENANT/TMYROOM.dart';
import 'package:smart_finder/TENANT/TLOGIN.dart';

// ⬇️ Tenant TOUR page
import 'package:smart_finder/TENANT/TOUR.dart' show Tour;

class TenantBookmark extends StatefulWidget {
  const TenantBookmark({super.key});

  @override
  State<TenantBookmark> createState() => _TenantBookmarkState();
}

class _TenantBookmarkState extends State<TenantBookmark> {
  final _sb = Supabase.instance.client;

  final List<_BookmarkItem> _bookmarks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBookmarks();
  }

  // ✅ Same style as TAPARTMENT.dart "auto-dismiss toast modal"
  void _showInfoDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor:
          const Color.fromARGB(255, 57, 57, 57).withOpacity(0.10), // dim
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
  }

  // ✅ Confirmation modal for removing bookmark
  Future<bool> _confirmRemove(BuildContext context, _BookmarkItem item) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.30),
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Remove bookmark?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Are you sure you want to remove "${item.title}" from your bookmarks?',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _fetchBookmarks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
          _bookmarks.clear();
          _error = 'You need to be logged in to view bookmarks.';
        });
        return;
      }

      // Load bookmarks + room data (using join via foreign key)
      final List<dynamic> data = await _sb
          .from('room_bookmarks')
          .select('''
            room_id,
            created_at,
            rooms!inner (
              id,
              apartment_name,
              location,
              monthly_payment,
              room_images ( image_url, sort_order )
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      _bookmarks.clear();

      for (final row in data) {
        final room = row['rooms'];
        if (room == null) continue;

        final String id = room['id'].toString();
        final String title =
            ((room['apartment_name'] ?? '').toString().trim().isNotEmpty)
                ? room['apartment_name'] as String
                : 'Apartment';

        final String address = (room['location'] ?? '—').toString();
        final double monthly = (room['monthly_payment'] is num)
            ? (room['monthly_payment'] as num).toDouble()
            : double.tryParse(room['monthly_payment']?.toString() ?? '0') ?? 0.0;

        // Thumbnail (first image by sort_order)
        String? thumb;
        final imgs = (room['room_images'] as List?) ?? const [];
        if (imgs.isNotEmpty) {
          imgs.sort((a, b) => ((a['sort_order'] ?? 0) as int)
              .compareTo((b['sort_order'] ?? 0) as int));
          thumb = imgs.first['image_url'] as String?;
        }

        _bookmarks.add(
          _BookmarkItem(
            id: id,
            title: title,
            address: address,
            monthly: monthly,
            imageUrl: thumb,
          ),
        );
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load bookmarks: $e';
      });
    }
  }

  // Tenant: always open TENANT Tour
  void _openTour(_BookmarkItem item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Tour(
          initialIndex: 0,
          roomId: item.id,
          titleHint: item.title,
          addressHint: item.address,
          monthlyHint: item.monthly,
          conversationId: '',
          peerName: '',
        ),
      ),
    );
  }

  void _removeBookmark(_BookmarkItem item) async {
    final user = _sb.auth.currentUser;
    if (user == null) return;

    // ✅ Confirmation modal first
    final ok = await _confirmRemove(context, item);
    if (!ok) return;

    try {
      await _sb
          .from('room_bookmarks')
          .delete()
          .eq('user_id', user.id)
          .eq('room_id', item.id);

      setState(() {
        _bookmarks.removeWhere((b) => b.id == item.id);
      });

      // ✅ Change message to match TAPARTMENT.dart style (modal, not snackbar)
      _showInfoDialog(context, 'Bookmark removed.');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove bookmark: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _onBottomNavTap(int index) {
    if (index == TenantNavIndex.apartment) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantApartment()),
      );
    } else if (index == TenantNavIndex.message) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantListChat()),
      );
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
      // already here
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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'BOOKMARKS',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF04354B)),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                )
              : _bookmarks.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.bookmark_border,
                              size: 40,
                              color: Color(0xFF9CA3AF),
                            ),
                            SizedBox(height: 10),
                            Text(
                              'No bookmarked apartments yet',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Tap the bookmark icon on an apartment to save it here for quick access.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      itemCount: _bookmarks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _bookmarks[index];
                        return _BookmarkCard(
                          item: item,
                          onRemove: () => _removeBookmark(item),
                          onOpen: () => _openTour(item),
                        );
                      },
                    ),
      // ⬇️ Tenant bottom navigation (Bookmark tab)
      bottomNavigationBar: TenantBottomNav(
        currentIndex: TenantNavIndex.bookmark,
        onItemSelected: _onBottomNavTap,
      ),
    );
  }
}

/* ----------------------------- MODELS + CARD ----------------------------- */

class _BookmarkItem {
  final String id;
  final String title;
  final String address;
  final double monthly;
  final String? imageUrl;

  _BookmarkItem({
    required this.id,
    required this.title,
    required this.address,
    required this.monthly,
    required this.imageUrl,
  });
}

class _BookmarkCard extends StatelessWidget {
  final _BookmarkItem item;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  const _BookmarkCard({
    super.key,
    required this.item,
    required this.onRemove,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    const textPrimary = Color(0xFF111827);
    const textSecondary = Color(0xFF6B7280);
    const cardColor = Color(0xFFD7E0E6); // match TenantApartmentCard

    return GestureDetector(
      onTap: onOpen,
      child: Card(
        margin: const EdgeInsets.only(bottom: 6),
        elevation: 3,
        color: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // IMAGE + OVERLAYS
            Stack(
              children: [
                SizedBox(
                  height: 170,
                  width: double.infinity,
                  child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      ? Image.network(item.imageUrl!, fit: BoxFit.cover)
                      : Image.asset(
                          'assets/images/roompano.png',
                          fit: BoxFit.cover,
                        ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color.fromARGB(120, 0, 0, 0),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // "Bookmarked" pill top-left
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.bookmark,
                          size: 14,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Bookmarked',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Remove shortcut button (top-right)
                Positioned(
                  top: 10,
                  right: 10,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Color(0xFFB91C1C),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Remove',
                            style: TextStyle(
                              color: Color(0xFFB91C1C),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // DETAILS
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              color: cardColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.bookmark,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Price
                  Text(
                    '₱ ${item.monthly.toStringAsFixed(0)} / Month',
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Location
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: textSecondary,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Actions row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: onOpen,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                        ),
                        icon: const Icon(
                          Icons.visibility_outlined,
                          size: 18,
                          color: Color(0xFF04354B),
                        ),
                        label: const Text(
                          'View details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF04354B),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: onRemove,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          foregroundColor: const Color(0xFFB91C1C),
                        ),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                        ),
                        label: const Text(
                          'Remove',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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
      ),
    );
  }
}
