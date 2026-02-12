// landlord_rooms_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../services/room_service.dart';

// Avoid class-name collisions with detail pages
import 'roomavail.dart' as avail;
import 'roomnotavail.dart' as notavail;

class LandlordRoomsPage extends StatefulWidget {
  const LandlordRoomsPage({super.key});

  @override
  State<LandlordRoomsPage> createState() => _LandlordRoomsPageState();
}

class _LandlordRoomsPageState extends State<LandlordRoomsPage> {
  final RoomService _service = RoomService();
  late final Stream<List<Map<String, dynamic>>> _stream;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _stream = _service.streamMyRooms(); // emits [] immediately, then live data
  }

  @override
  void dispose() {
    _service.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- helpers ----------
  String _resolveStatus(Map<String, dynamic> r) {
    final a = (r['availability_status'] ?? '').toString();
    if (a == 'available' || a == 'not_available') return a;
    final s = (r['status'] ?? '').toString().toLowerCase();
    return (s == 'available') ? 'available' : 'not_available';
  }

  bool _isVacant(Map<String, dynamic> r) => _resolveStatus(r) == 'available';
  String _label(Map<String, dynamic> r) => _isVacant(r) ? 'VACANT' : 'OCCUPIED';

  void _openRoom(Map<String, dynamic> row) {
    final status = _resolveStatus(row);
    final hasId = row['id'] != null && row['id'].toString().trim().isNotEmpty;
    if (!hasId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Missing room id.')));
      return;
    }

    final page = (status == 'not_available')
        ? notavail.RoomNotAvailable(roomData: row)
        : avail.RoomAvailable(roomData: row);

    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003B5C),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'TOTAL ROOMS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        initialData: const [], // prevents endless spinner
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load rooms:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          final rooms = snap.data ?? const [];
          if (rooms.isEmpty) {
            return const _EmptyState();
          }

          final total = rooms.length;

          return ListView(
            controller: _scrollController,
            children: [
              // total count (optional)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8,
                ),
                child: Text(
                  'Total: $total',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // ----- GRID CARDS -----
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(10.0),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 15,
                  mainAxisSpacing: 20,
                ),
                itemCount: rooms.length,
                itemBuilder: (context, index) {
                  final r = rooms[index];
                  final isVacant = _isVacant(r);
                  final label = _label(r);

                  // Big text on card
                  final bigLabel = (r['apartment_name'] ?? r['id'] ?? 'Room')
                      .toString();

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B8D93),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(2, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Stack(
                            children: [
                              // green/red dot
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: isVacant
                                        ? const Color.fromARGB(255, 62, 255, 69)
                                        : Colors.red,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 3,
                                        offset: const Offset(1, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              // (Removed the occupied date/time overlay)

                              // center icon + labels
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.home_rounded,
                                      size: 70,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      bigLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: isVacant
                                            ? Colors.greenAccent
                                            : Colors.redAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // bottom "More Info" bar
                        Container(
                          height: 38,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                              bottomRight: Radius.circular(12),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _openRoom(r),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(
                                  Icons.info_outline,
                                  size: 18,
                                  color: Colors.blue,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  "More Info",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'No rooms yet.\nCreate a room in AddRoom to see it here.\n'
          'New rooms default to “available”.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14),
        ),
      ),
    );
  }
}
