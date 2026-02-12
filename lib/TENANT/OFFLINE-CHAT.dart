// TENANT/offline_chat.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum LocalSendStatus { queued, sending, sent, failed }

class LocalQueuedMessage {
  final String localId;
  final String landlordPhone;
  final String tenantPhone;
  final String tenantUserId;
  final String tenantName;
  final String body;
  final DateTime createdAtLocal;
  LocalSendStatus status;
  String? error;

  LocalQueuedMessage({
    required this.localId,
    required this.landlordPhone,
    required this.tenantPhone,
    required this.tenantUserId,
    required this.tenantName,
    required this.body,
    required this.createdAtLocal,
    this.status = LocalSendStatus.queued,
    this.error,
  });
}

class OfflineChatScreenTenant extends StatefulWidget {
  final String conversationId;
  final String peerName;
  final String? peerAvatarUrl;
  final String? landlordPhone;

  const OfflineChatScreenTenant({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.peerAvatarUrl,
    this.landlordPhone,
  });

  @override
  State<OfflineChatScreenTenant> createState() =>
      _OfflineChatScreenTenantState();
}

class _OfflineChatScreenTenantState extends State<OfflineChatScreenTenant> {
  final _controller = TextEditingController();
  final _listController = ScrollController();
  late final SupabaseClient _sb;

  bool _sending = false;
  bool _flushing = false;

  String _tenantPhone = '';
  String _tenantName = 'Tenant';
  String _tenantUserId = '';

  String _landlordPhone = '';

  final List<LocalQueuedMessage> _outbox = [];

  @override
  void initState() {
    super.initState();
    _sb = Supabase.instance.client;

    _landlordPhone = (widget.landlordPhone ?? '').trim();

    final uid = _sb.auth.currentUser?.id;
    _tenantUserId = uid ?? '';

    _loadTenantProfile();
  }

  @override
  void dispose() {
    _controller.dispose();
    _listController.dispose();
    super.dispose();
  }

  Future<void> _loadTenantProfile() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      // ✅ Adjust these columns depending on your users table:
      // If you don't have phone/full_name, update this select().
      final row = await _sb
          .from('users')
          .select('phone, full_name, first_name, last_name')
          .eq('id', uid)
          .maybeSingle();

      final phone = (row?['phone'] ?? '').toString().trim();

      final full =
          (row?['full_name'] ??
                  '${row?['first_name'] ?? ''} ${row?['last_name'] ?? ''}')
              .toString()
              .trim();

      if (!mounted) return;
      setState(() {
        _tenantPhone = phone;
        _tenantName = full.isNotEmpty ? full : 'Tenant';
      });
    } catch (_) {
      // fallback stays
    }
  }

  String _fmtLocalDt(DateTime dt) =>
      DateFormat('MMM d, yyyy • hh:mm a').format(dt.toLocal());

  Future<bool> _hasInternet() async {
    try {
      await _sb.from('users').select('id').limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _queueMessage(String text) {
    final tenantPhone = _tenantPhone.isNotEmpty ? _tenantPhone : 'UNKNOWN';
    final tenantName = _tenantName.isNotEmpty ? _tenantName : 'Tenant';
    final tenantUserId = _tenantUserId;

    final local = LocalQueuedMessage(
      localId: DateTime.now().microsecondsSinceEpoch.toString(),
      landlordPhone: _landlordPhone,
      tenantPhone: tenantPhone,
      tenantUserId: tenantUserId,
      tenantName: tenantName,
      body: text,
      createdAtLocal: DateTime.now(),
      status: LocalSendStatus.queued,
    );

    setState(() => _outbox.add(local));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_listController.hasClients) {
        _listController.jumpTo(_listController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendOrQueue() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    if (_landlordPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Landlord phone not available.')),
      );
      return;
    }

    if (_tenantUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tenant not logged in (missing user id).'),
        ),
      );
      return;
    }

    if (_sending) return;
    _sending = true;

    try {
      _queueMessage(text);
      _controller.clear();

      final online = await _hasInternet();
      if (online) {
        await _flushOutbox();
      }
    } finally {
      _sending = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _flushOutbox() async {
    if (_flushing) return;
    if (_outbox.isEmpty) return;

    final online = await _hasInternet();
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No internet. Messages remain queued.')),
      );
      return;
    }

    _flushing = true;
    try {
      final toSend = _outbox
          .where(
            (m) =>
                m.status == LocalSendStatus.queued ||
                m.status == LocalSendStatus.failed,
          )
          .toList();

      for (final msg in toSend) {
        setState(() {
          msg.status = LocalSendStatus.sending;
          msg.error = null;
        });

        try {
          // ✅ FIX: include tenant_user_id and tenant_name
          final res = await _sb.functions.invoke(
            'send_sms',
            body: {
              "landlord_phone": msg.landlordPhone,
              "tenant_phone": msg.tenantPhone,
              "tenant_user_id": msg.tenantUserId,
              "tenant_name": msg.tenantName,
              "message": msg.body,
            },
          );

          if (res.status != 200) {
            throw Exception(res.data?.toString() ?? 'Edge function failed');
          }

          setState(() => msg.status = LocalSendStatus.sent);

          await Future.delayed(const Duration(milliseconds: 250));
          if (!mounted) return;
          setState(() => _outbox.removeWhere((x) => x.localId == msg.localId));
        } catch (e) {
          setState(() {
            msg.status = LocalSendStatus.failed;
            msg.error = e.toString();
          });
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Widget _statusPill(LocalSendStatus status) {
    final text = switch (status) {
      LocalSendStatus.queued => 'QUEUED',
      LocalSendStatus.sending => 'SENDING',
      LocalSendStatus.sent => 'SENT',
      LocalSendStatus.failed => 'FAILED',
    };

    final icon = switch (status) {
      LocalSendStatus.queued => Icons.schedule,
      LocalSendStatus.sending => Icons.sync,
      LocalSendStatus.sent => Icons.check_circle,
      LocalSendStatus.failed => Icons.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _queuedBubble(LocalQueuedMessage m) {
    final stamp = _fmtLocalDt(m.createdAtLocal);

    return GestureDetector(
      onTap: (m.status == LocalSendStatus.failed)
          ? () async {
              setState(() {
                m.status = LocalSendStatus.queued;
                m.error = null;
              });
              await _flushOutbox();
            }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF04395E),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(0),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              m.body,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stamp,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 8),
                _statusPill(m.status),
              ],
            ),
            if (m.status == LocalSendStatus.failed &&
                (m.error?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  m.error!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleName = widget.peerName.trim().isEmpty
        ? 'Landlord'
        : widget.peerName;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04395E),
        foregroundColor: Colors.white,
        title: Text('$titleName (Offline)'),
        actions: [
          IconButton(
            tooltip: 'Send queued messages',
            icon: const Icon(Icons.sync),
            onPressed: _flushOutbox,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              _landlordPhone,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.orange.shade100,
            child: Row(
              children: [
                const Icon(Icons.cloud_off, color: Colors.deepOrange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Offline queue — these will send as SMS when you are online.',
                    style: TextStyle(
                      color: Colors.deepOrange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _listController,
              padding: const EdgeInsets.all(10),
              itemCount: _outbox.length,
              itemBuilder: (context, i) {
                final m = _outbox[i];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(child: _queuedBubble(m)),
                    const SizedBox(width: 8),
                    const CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, color: Colors.grey, size: 18),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: 'Type an offline message…',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(fontSize: 17),
                      onSubmitted: (_) => _sendOrQueue(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF04395E),
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sending ? null : _sendOrQueue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
