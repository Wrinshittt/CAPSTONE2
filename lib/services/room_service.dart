// services/room_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoomService {
  final SupabaseClient _sb = Supabase.instance.client;
  RealtimeChannel? _channel;

  /// Live list of the current landlord's rooms.
  /// Emits [] immediately so the UI never hangs showing a spinner.
  Stream<List<Map<String, dynamic>>> streamMyRooms() {
    final ctrl = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> loadAndSubscribe() async {
      try {
        final uid = _sb.auth.currentUser?.id;

        // emit quickly so StreamBuilder has data
        ctrl.add(const []);

        if (uid == null) {
          // not logged in — just stay at []
          return;
        }

        // initial load
        final init = await _sb
            .from('rooms')
            .select()
            .eq('landlord_id', uid)
            .order('created_at', ascending: false);

        final initial = (init as List).cast<Map<String, dynamic>>();
        if (!ctrl.isClosed) ctrl.add(initial);

        // realtime subscription narrowed to this landlord
        _channel?.unsubscribe();
        _channel = _sb.channel('rooms_for_$uid')
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
              final list = (fresh as List).cast<Map<String, dynamic>>();
              if (!ctrl.isClosed) ctrl.add(list);
            },
          )
          ..subscribe();
      } catch (e) {
        if (!ctrl.isClosed) ctrl.addError(e);
      }
    }

    // start work when someone listens
    ctrl.onListen = loadAndSubscribe;

    // clean up
    ctrl.onCancel = () {
      _channel?.unsubscribe();
    };

    return ctrl.stream;
  }

  Future<Map<String, dynamic>> createRoom({
    required String apartmentName,
    required String location,
    required num monthlyPayment,
    int? floorNumber,
    String? description,
  }) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) throw Exception('Not logged in');

    final row = await _sb
        .from('rooms')
        .insert({
          'landlord_id': uid,
          'apartment_name': apartmentName,
          'location': location,
          'monthly_payment': monthlyPayment,
          if (floorNumber != null) 'floor_number': floorNumber,
          if (description != null) 'description': description,
        })
        .select()
        .single();

    return (row as Map).cast<String, dynamic>();
  }

  Future<void> setAvailability({
    required String roomId,
    required String availability, // 'available' | 'not_available'
  }) async {
    await _sb
        .from('rooms')
        .update({'availability_status': availability})
        .eq('id', roomId);
  }

  Future<void> addTenantToRoom({
    required String roomId,
    required String fullName,
    String? phone,
    DateTime? startDate,
  }) async {
    final landlordId = _sb.auth.currentUser?.id;
    if (landlordId == null) throw Exception('Not logged in');

    final startIso = (startDate ?? DateTime.now()).toIso8601String();

    try {
      await _sb.from('room_tenants').insert({
        'room_id': roomId,
        'full_name': fullName,
        if (phone != null) 'phone': phone,
        'start_date': startIso,
        'landlord_id': landlordId,
      });
    } catch (_) {
      // Safe ignore if the auxiliary table doesn't exist.
    }

    await _sb
        .from('rooms')
        .update({'availability_status': 'not_available'})
        .eq('id', roomId);
  }

  void dispose() {
    _channel?.unsubscribe();
  }
}
