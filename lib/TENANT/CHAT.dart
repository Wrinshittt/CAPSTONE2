// TENANT/chat.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smart_finder/services/chat_service.dart';
import 'package:smart_finder/LANDLORD/profile.dart';

// ✅ make sure this path matches your file name
import 'package:smart_finder/TENANT/OFFLINE-CHAT.dart';

class ChatScreenTenant extends StatefulWidget {
  final String conversationId;
  final String peerName;
  final String? peerAvatarUrl;
  final String? landlordPhone;

  const ChatScreenTenant({
    super.key,
    required this.conversationId,
    required this.peerName,
    this.peerAvatarUrl,
    this.landlordPhone,
  });

  @override
  State<ChatScreenTenant> createState() => _ChatScreenTenantState();
}

class _ChatScreenTenantState extends State<ChatScreenTenant> {
  final _controller = TextEditingController();
  final _listController = ScrollController();

  late final SupabaseClient _sb;
  late final ChatService _chat;

  String _meId = '';
  String _meName = 'You';

  String? _landlordPhone;

  String? _avatarUrl;
  int _avatarVersion = 0;
  String? _landlordName;
  String? _landlordId;

  final Map<String, String> _avatarCache = {};
  String? _myAvatarUrl;

  bool _fetchingPhone = false;
  bool _fetchingHeader = false;

  Object? _editingMessageId;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _sb = Supabase.instance.client;
    _chat = ChatService(_sb);

    _meId = _sb.auth.currentUser?.id ?? '';
    _chat.markRead(conversationId: widget.conversationId, isLandlord: false);

    _landlordPhone = widget.landlordPhone;
    _avatarUrl = widget.peerAvatarUrl;
    _landlordName = widget.peerName;

    _loadMyName();
    _primeMyAvatar();

    if (_landlordPhone == null || _landlordPhone!.trim().isEmpty) {
      _fetchPhone();
    }
    if (_avatarUrl == null || _avatarUrl!.trim().isEmpty) {
      _fetchHeaderAvatar();
    } else {
      if (_landlordId != null && _avatarUrl != null && _avatarUrl!.isNotEmpty) {
        _avatarCache[_landlordId!] = _avatarUrl!;
      }
    }
  }

  Future<void> _loadMyName() async {
    if (_meId.isEmpty) return;
    try {
      final row = await _sb
          .from('users')
          .select('full_name, first_name, last_name')
          .eq('id', _meId)
          .maybeSingle();

      if (!mounted || row == null) return;

      final full =
          (row['full_name'] ??
                  '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}')
              .toString()
              .trim();

      if (full.isNotEmpty) setState(() => _meName = full);
    } catch (_) {}
  }

  Future<void> _primeMyAvatar() async {
    if (_meId.isEmpty) return;
    _myAvatarUrl = _avatarUrlFor(_meId);
    if (_myAvatarUrl != null && _myAvatarUrl!.isNotEmpty) {
      _avatarCache[_meId] = _myAvatarUrl!;
      if (mounted) setState(() {});
    }
  }

  String _avatarUrlFor(String userId) {
    final storage = _sb.storage.from('avatars');
    final jpg = storage.getPublicUrl('$userId.jpg');
    final png = storage.getPublicUrl('$userId.png');
    return jpg.isNotEmpty ? jpg : png;
  }

  Widget _bubbleAvatar(String userId, {double size = 28}) {
    final url = _avatarCache[userId] ?? _avatarUrlFor(userId);
    _avatarCache[userId] = url;

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: Colors.white,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.person, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Future<void> _fetchHeaderAvatar() async {
    if (_fetchingHeader) return;
    setState(() => _fetchingHeader = true);

    try {
      final parties = await _chat.getConversationParties(widget.conversationId);
      final String? landlordId = parties['landlord_id'] as String?;

      if (landlordId != null) {
        final storage = _sb.storage.from('avatars');
        final jpg = storage.getPublicUrl('$landlordId.jpg');

        if (!mounted) return;
        setState(() {
          _avatarUrl = '$jpg?v=$_avatarVersion';
          _landlordId = landlordId;
          _avatarCache[landlordId] = _avatarUrl!;
        });

        await _fetchLandlordName(landlordId);
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _fetchingHeader = false);
    }
  }

  Future<void> _fetchPhone() async {
    if (_fetchingPhone) return;
    setState(() => _fetchingPhone = true);

    try {
      final parties = await _chat.getConversationParties(widget.conversationId);
      final String? landlordId = parties['landlord_id'] as String?;

      if (landlordId != null) {
        final phone = await _chat.getLandlordPhone(landlordId);
        if (mounted) {
          setState(() {
            _landlordPhone = phone;
            _landlordId = landlordId;
          });
        }
        await _fetchLandlordName(landlordId);
      }
    } finally {
      if (mounted) setState(() => _fetchingPhone = false);
    }
  }

  Future<void> _fetchLandlordName(String landlordId) async {
    try {
      final row = await _sb
          .from('users')
          .select('full_name, first_name, last_name')
          .eq('id', landlordId)
          .maybeSingle();

      if (!mounted || row == null) return;

      final full =
          (row['full_name'] ??
                  '${row['first_name'] ?? ''} ${row['last_name'] ?? ''}')
              .toString()
              .trim();

      if (full.isNotEmpty) setState(() => _landlordName = full);
    } catch (_) {}
  }

  String _fmtLocal(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('MMM d, yyyy • hh:mm a').format(dt);
    } catch (_) {
      return '';
    }
  }

  Future<void> _sendOrUpdate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final me = _sb.auth.currentUser?.id;
    if (me == null) return;

    if (_sending) return;
    _sending = true;

    try {
      if (_editingMessageId != null) {
        await _chat.updateMessage(messageId: _editingMessageId!, newBody: text);
        if (!mounted) return;
        setState(() => _editingMessageId = null);
        _controller.clear();
      } else {
        await _chat.send(
          conversationId: widget.conversationId,
          senderId: me,
          body: text,
          viaSms: false,
        );
        _controller.clear();

        await Future.delayed(const Duration(milliseconds: 140));
        if (_listController.hasClients) {
          _listController.jumpTo(_listController.position.maxScrollExtent);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    } finally {
      _sending = false;
      if (mounted) setState(() {});
    }
  }

  void _startEditing(Object messageId, String currentText) {
    setState(() {
      _editingMessageId = messageId;
      _controller.text = currentText;
    });
  }

  void _cancelEditing() {
    setState(() => _editingMessageId = null);
    _controller.clear();
  }

  Future<void> _openLandlordProfile() async {
    String? landlordId = _landlordId;

    if (landlordId == null) {
      try {
        final parties = await _chat.getConversationParties(
          widget.conversationId,
        );
        landlordId = parties['landlord_id'] as String?;
        if (mounted) setState(() => _landlordId = landlordId);
      } catch (_) {}
    }

    if (!mounted || landlordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open landlord profile.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => Adminprofile(landlordId)),
    );
  }

  // ✅ OFFLINE button → offline_chat.dart
  void _openOfflineChat() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfflineChatScreenTenant(
          conversationId: widget.conversationId,
          peerName: widget.peerName,
          peerAvatarUrl: _avatarUrl ?? widget.peerAvatarUrl,
          landlordPhone: _landlordPhone ?? widget.landlordPhone,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = _sb.auth.currentUser?.id ?? '';

    final landlordName = (_landlordName ?? widget.peerName).trim().isEmpty
        ? 'Landlord'
        : (_landlordName ?? widget.peerName).trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF04395E),
        foregroundColor: Colors.white,
        title: InkWell(
          onTap: _openLandlordProfile,
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: ClipOval(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                        ? Image.network(
                            _avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.person, color: Colors.grey),
                          )
                        : const Icon(Icons.person, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  landlordName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _openOfflineChat,
              icon: const Icon(Icons.cloud_off, color: Colors.white),
              label: const Text(
                'OFFLINE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              _landlordPhone ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _chat.streamMessages(widget.conversationId),
              builder: (context, snap) {
                final data = List<Map<String, dynamic>>.from(
                  snap.data ?? const [],
                );

                data.sort((a, b) {
                  final aT =
                      DateTime.tryParse(a['created_at'] ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
                  final bT =
                      DateTime.tryParse(b['created_at'] ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
                  return aT.compareTo(bT);
                });

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_listController.hasClients) {
                    _listController.jumpTo(
                      _listController.position.maxScrollExtent,
                    );
                  }
                });

                return ListView.builder(
                  controller: _listController,
                  padding: const EdgeInsets.all(10),
                  itemCount: data.length,
                  itemBuilder: (context, index) {
                    final m = data[index];

                    final senderId =
                        (m['sender_user_id'] ?? m['sender_id'])?.toString() ??
                        '';
                    final isMe = senderId == me;

                    final stamp = _fmtLocal(m['created_at']);
                    final isDeleted = (m['is_deleted'] ?? false) == true;
                    final wasEdited = (m['edited_at'] as String?) != null;

                    Offset? pressPosition;

                    Widget bubbleContent() {
                      if (isDeleted) {
                        return Text(
                          'Message deleted',
                          style: TextStyle(
                            color: isMe ? Colors.white70 : Colors.grey,
                            fontStyle: FontStyle.italic,
                            fontSize: 15,
                          ),
                        );
                      }

                      return Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Text(
                            (m['body'] ?? '') as String,
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                stamp,
                                style: TextStyle(
                                  color: isMe
                                      ? Colors.white70
                                      : Colors.grey.shade600,
                                  fontSize: 13,
                                ),
                              ),
                              if (wasEdited) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '(edited)',
                                  style: TextStyle(
                                    color: isMe ? Colors.white70 : Colors.grey,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      );
                    }

                    Widget bubble() {
                      return GestureDetector(
                        onLongPressStart: isMe && !isDeleted
                            ? (details) async {
                                pressPosition = details.globalPosition;
                                final overlay =
                                    Overlay.of(
                                          context,
                                        ).context.findRenderObject()
                                        as RenderBox;

                                final offset = pressPosition!;
                                final rr = RelativeRect.fromLTRB(
                                  offset.dx,
                                  offset.dy,
                                  overlay.size.width - offset.dx,
                                  overlay.size.height - offset.dy,
                                );

                                final action = await showMenu<String>(
                                  context: context,
                                  position: rr,
                                  items: const [
                                    PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Edit'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete'),
                                    ),
                                  ],
                                );

                                if (action == 'edit') {
                                  _startEditing(
                                    m['id'],
                                    (m['body'] ?? '') as String,
                                  );
                                } else if (action == 'delete') {
                                  final sure = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Delete message?'),
                                      content: const Text(
                                        'This will delete the message for everyone.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (sure == true) {
                                    try {
                                      await _chat.softDeleteMessage(
                                        messageId: m['id'],
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text('Delete failed: $e'),
                                        ),
                                      );
                                    }
                                  }
                                }
                              }
                            : null,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.72,
                          ),
                          decoration: BoxDecoration(
                            color: isMe
                                ? const Color(0xFF04395E)
                                : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(isMe ? 16 : 0),
                              bottomRight: Radius.circular(isMe ? 0 : 16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: bubbleContent(),
                        ),
                      );
                    }

                    final row = Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: isMe
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      children: isMe
                          ? [
                              Flexible(child: bubble()),
                              const SizedBox(width: 8),
                              _bubbleAvatar(me),
                            ]
                          : [
                              _bubbleAvatar(senderId),
                              const SizedBox(width: 8),
                              Flexible(child: bubble()),
                            ],
                    );

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: row,
                    );
                  },
                );
              },
            ),
          ),

          if (_editingMessageId != null)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.black54),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Edit message',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _cancelEditing,
                    borderRadius: BorderRadius.circular(20),
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFECECEC),
                      child: Icon(Icons.close, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _sendOrUpdate,
                    borderRadius: BorderRadius.circular(20),
                    child: const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFECECEC),
                      child: Icon(Icons.check, color: Colors.black87),
                    ),
                  ),
                ],
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
                        hintText: _editingMessageId != null
                            ? 'Update your message…'
                            : 'Type a message…',
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
                      onSubmitted: (_) => _sendOrUpdate(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: const Color(0xFF04395E),
                    child: IconButton(
                      icon: Icon(
                        _editingMessageId != null ? Icons.check : Icons.send,
                        color: Colors.white,
                      ),
                      onPressed: _sending ? null : _sendOrUpdate,
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
