import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

enum MessageType { text, file, system }

class ChatMessage {
  static const _uuid = Uuid();
  static final DateFormat wireDateFormat = DateFormat('dd.MM.yyyy HH:mm:ss');

  final String id;
  final String senderId;
  final String senderName;
  final String senderIp;
  final String content;
  final DateTime timestamp;
  final MessageType type;
  final bool isMe;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderIp,
    required this.content,
    required this.timestamp,
    this.type = MessageType.text,
    this.isMe = false,
  });

  /// Wire format sent over HTTP POST /message:
  /// {senderId, senderName, message, datetime, ip}
  Map<String, dynamic> toWireJson() => {
        'senderId': senderId,
        'senderName': senderName,
        'message': content,
        'datetime': wireDateFormat.format(timestamp),
        'ip': senderIp,
      };

  /// Parse an incoming wire payload. `id` is generated locally because the
  /// wire format does not carry one.
  factory ChatMessage.fromWireJson(Map<String, dynamic> json, String myId) {
    final dateStr = json['datetime'] as String?;
    DateTime ts;
    try {
      ts = dateStr != null ? wireDateFormat.parse(dateStr) : DateTime.now();
    } catch (_) {
      ts = DateTime.now();
    }
    final sid = json['senderId'] as String? ?? '';
    return ChatMessage(
      id: _uuid.v4(),
      senderId: sid,
      senderName: json['senderName'] as String? ?? '',
      senderIp: json['ip'] as String? ?? '',
      content: json['message'] as String? ?? '',
      timestamp: ts,
      type: MessageType.text,
      isMe: sid == myId,
    );
  }
}
