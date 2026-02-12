import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChatService {
  final SupabaseClient sb;
  ChatService(this.sb);

  // ----------------- Realtime stream -----------------
  Stream<List<Map<String, dynamic>>> streamMessages(String conversationId) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> _emit() async {
      final rows = await sb
          .from('messages')
          .select('''
            id,
            conversation_id,
            sender_user_id,
            body,
            transport,
            status,
            recipient_phone,
            is_deleted,
            edited_at,
            created_at
          ''')
          .eq('conversation_id', conversationId)
          .order('created_at'); // oldest -> newest; newest at bottom
      if (!controller.isClosed) {
        controller.add(List<Map<String, dynamic>>.from(rows));
      }
    }

    // initial load
    _emit();

    // one channel per conversation; listen to insert/update/delete
    final ch = sb.channel('messages-$conversationId');

    for (final evt in [
      PostgresChangeEvent.insert,
      PostgresChangeEvent.update,
      PostgresChangeEvent.delete,
    ]) {
      ch.onPostgresChanges(
        event: evt,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'conversation_id',
          value: conversationId,
        ),
        callback: (_) => _emit(),
      );
    }

    ch.subscribe();
    controller.onCancel = () => sb.removeChannel(ch);
    return controller.stream;
  }

  // ----------------- Send / Edit / Delete -----------------
  Future<void> send({
    required String conversationId,
    required String senderId,
    required String body,
    bool viaSms = false,
  }) async {
    // Resolve recipient phone (optional, but many schemas keep it NOT NULL)
    final parties = await getConversationParties(conversationId);
    final otherId = senderId == parties['tenant_id']
        ? parties['landlord_id']
        : parties['tenant_id'];
    final phone = await _getUserPhone((otherId ?? '') as String);

    // Respect your DB constraints
    final transport = viaSms ? 'sms' : 'app';
    final status = viaSms ? 'queued' : 'delivered';

    await sb.from('messages').insert({
      'conversation_id': conversationId,
      'sender_user_id': senderId,
      'body': body,
      'transport': transport,
      'status': status,
      'recipient_phone': phone ?? '',
    });
  }

  /// Accepts either UUID String or int PK
  Future<void> updateMessage({
    required Object messageId,
    required String newBody,
  }) async {
    await sb
        .from('messages')
        .update({
          'body': newBody,
          'edited_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', messageId);
  }

  /// Accepts either UUID String or int PK
  Future<void> softDeleteMessage({required Object messageId}) async {
    await sb
        .from('messages')
        .update({
          'is_deleted': true,
          'deleted_at': DateTime.now().toUtc().toIso8601String(),
          'deleted_by': sb.auth.currentUser?.id,
        })
        .eq('id', messageId);
  }

  Future<void> markRead({
    required String conversationId,
    required bool isLandlord,
  }) async {
    await sb
        .from('messages')
        .update({isLandlord ? 'read_by_landlord' : 'read_by_tenant': true})
        .eq('conversation_id', conversationId);
  }

  // ----------------- Conversation helpers -----------------
  Future<String> ensureConversation({
    required String tenantId,
    required String landlordId,
  }) async {
    final found = await sb
        .from('conversations')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('landlord_id', landlordId)
        .maybeSingle();

    if (found != null) return found['id'] as String;

    final phoneForLandlord = await getLandlordPhone(landlordId);

    final inserted = await sb
        .from('conversations')
        .insert({
          'tenant_id': tenantId,
          'landlord_id': landlordId,
          if (phoneForLandlord != null && phoneForLandlord.isNotEmpty)
            'other_party_phone': phoneForLandlord,
        })
        .select('id')
        .single();

    return inserted['id'] as String;
  }

  Future<Map<String, String?>> startChatFromRoom({
    required String roomId,
    required String tenantId,
  }) async {
    final room = await sb
        .from('rooms')
        .select('landlord_id')
        .eq('id', roomId)
        .maybeSingle();
    if (room == null || (room['landlord_id'] as String?) == null) {
      throw Exception('Room not found or has no landlord.');
    }

    final landlordId = room['landlord_id'] as String;
    final conversationId = await ensureConversation(
      tenantId: tenantId,
      landlordId: landlordId,
    );
    final phone = await getLandlordPhone(landlordId);
    final name = await getLandlordName(landlordId) ?? 'Landlord';

    return {
      'conversationId': conversationId,
      'landlordId': landlordId,
      'landlordName': name,
      'landlordPhone': phone,
    };
  }

  Future<Map<String, dynamic>> getConversationParties(
    String conversationId,
  ) async {
    final row = await sb
        .from('conversations')
        .select('tenant_id, landlord_id')
        .eq('id', conversationId)
        .maybeSingle();
    if (row == null) throw Exception('Conversation not found.');
    return Map<String, dynamic>.from(row);
  }

  // ----------------- Phone / name helpers -----------------
  Future<String?> getLandlordPhone(String landlordId) =>
      _getUserPhone(landlordId);

  Future<String?> getLandlordName(String landlordId) async {
    final p = await sb
        .from('landlord_profile')
        .select('first_name, last_name')
        .eq('user_id', landlordId)
        .maybeSingle();

    if (p != null) {
      final fn = (p['first_name'] ?? '').toString().trim();
      final ln = (p['last_name'] ?? '').toString().trim();
      final name = [fn, ln].where((e) => e.isNotEmpty).join(' ');
      if (name.isNotEmpty) return name;
    }

    final u = await sb
        .from('users')
        .select('full_name')
        .eq('id', landlordId)
        .maybeSingle();

    final full = u != null ? (u['full_name'] as String?) : null;
    return (full != null && full.trim().isNotEmpty) ? full.trim() : null;
  }

  Future<String?> _getUserPhone(String userId) async {
    if (userId.isEmpty) return null;

    // landlord_profile.contact_number
    final lp = await sb
        .from('landlord_profile')
        .select('contact_number')
        .eq('user_id', userId)
        .maybeSingle();
    final p1 = lp != null ? (lp['contact_number'] as String?) : null;
    if (p1 != null && p1.trim().isNotEmpty) return p1.trim();

    // tenant_profile.phone
    final tp = await sb
        .from('tenant_profile')
        .select('phone')
        .eq('user_id', userId)
        .maybeSingle();
    final p2 = tp != null ? (tp['phone'] as String?) : null;
    if (p2 != null && p2.trim().isNotEmpty) return p2.trim();

    // users.phone
    final u = await sb
        .from('users')
        .select('phone')
        .eq('id', userId)
        .maybeSingle();
    final p3 = u != null ? (u['phone'] as String?) : null;
    if (p3 != null && p3.trim().isNotEmpty) return p3.trim();

    return null;
  }
}
