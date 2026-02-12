// available_room.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// IMPORTANT: make sure the path/case matches the real file on disk.
// If your file is lib/LANDLORD/ROOMAVAIL.dart, keep it as below.
// If it's lib/LANDLORD/roomavail.dart, change the path to that exact case.
import 'package:smart_finder/LANDLORD/ROOMAVAIL.dart' as ra;

class AvailableRoom extends StatefulWidget {
  const AvailableRoom({super.key});

  @override
  State<AvailableRoom> createState() => _AvailableRoomState();
}

class _AvailableRoomState extends State<AvailableRoom> {
  final SupabaseClient _sb = Supabase.instance.client;

  // pagination
  int currentPage = 0;
  final int cardsPerPage = 8;
  final ScrollController _scrollController = ScrollController();

  late final Stream<List<Map<String, dynamic>>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _streamVacantRoomsForMe();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ---------- Helpers ----------
  String _resolveStatus(Map<String, dynamic> r) {
    final a = (r['availability_status'] ?? '').toString();
    if (a == 'available' || a == 'not_available') return a;
    final s = (r['status'] ?? '').toString().toLowerCase();
    return s == 'available' ? 'available' : 'not_available';
  }

  // ---------- Data: Vacant rooms only for current landlord (realtime) ----------
  Stream<List<Map<String, dynamic>>> _streamVacantRoomsForMe() async* {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      // not logged in
      yield const [];
      return;
    }

    // initial fetch
    final init = await _sb
        .from('rooms')
        .select()
        .eq('landlord_id', uid)
        .order('created_at', ascending: false);

    List<Map<String, dynamic>> cache =
        (init as List).cast<Map<String, dynamic>>()
          ..retainWhere((r) => _resolveStatus(r) == 'available');

    final ctrl = StreamController<List<Map<String, dynamic>>>.broadcast();
    ctrl.add(cache);

    // realtime: any change to rooms for this landlord → refresh + re-filter
    final ch = _sb.channel('available_rooms_for_$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'landlord_id',
          value: uid,
        ),
        callback: (payload) async {
          final fresh = await _sb
              .from('rooms')
              .select()
              .eq('landlord_id', uid)
              .order('created_at', ascending: false);
          cache = (fresh as List).cast<Map<String, dynamic>>()
            ..retainWhere((r) => _resolveStatus(r) == 'available');
          if (!ctrl.isClosed) ctrl.add(cache);
        },
      )
      ..subscribe();

    ctrl.onCancel = () => ch.unsubscribe();
    yield* ctrl.stream;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF003B5C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04354B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "AVAILABLE ROOMS",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        initialData: const [],
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load rooms:\n${snap.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final rooms = snap.data ?? const [];
          if (rooms.isEmpty) {
            return const Center(
              child: Text(
                'No vacant rooms for this landlord.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          // pagination math
          final totalPages = (rooms.length / cardsPerPage).ceil();
          final startIndex = (currentPage * cardsPerPage).clamp(
            0,
            rooms.length,
          );
          final endIndex = (startIndex + cardsPerPage).clamp(0, rooms.length);

          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(12.0),
            children: [
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: endIndex - startIndex,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 15,
                  crossAxisSpacing: 15,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final room = rooms[startIndex + index];
                  final roomLabel = (room['id'] ?? room['room'] ?? 'Room')
                      .toString();

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF7B8D93),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
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
                              // green status dot
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: const Color.fromARGB(
                                      255,
                                      62,
                                      255,
                                      69,
                                    ),
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
                                      roomLabel,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      "VACANT",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: Colors.greenAccent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // More Info bar
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
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  // Use the alias to disambiguate and guarantee resolution
                                  builder: (_) =>
                                      ra.RoomAvailable(roomData: room),
                                ),
                              );
                            },
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
              _buildPagination(totalPages),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPagination(int totalPages) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          IconButton(
            onPressed: currentPage > 0
                ? () {
                    setState(() {
                      currentPage--;
                      _scrollController.jumpTo(0);
                    });
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
            iconSize: 30,
            color: Colors.white,
          ),
          ...List.generate(totalPages, (index) {
            final isSelected = index == currentPage;
            return GestureDetector(
              onTap: () {
                setState(() {
                  currentPage = index;
                  _scrollController.jumpTo(0);
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isSelected
                      ? const Color.fromARGB(255, 214, 214, 214)
                      : Colors.white10,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 2)
                      : null,
                  boxShadow: isSelected
                      ? const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  "${index + 1}",
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          IconButton(
            onPressed: () {
              if (currentPage < totalPages - 1) {
                setState(() {
                  currentPage++;
                  _scrollController.jumpTo(0);
                });
              }
            },
            icon: const Icon(Icons.chevron_right),
            iconSize: 30,
            color: Colors.white,
          ),
        ],
      ),
    );
  }
}
