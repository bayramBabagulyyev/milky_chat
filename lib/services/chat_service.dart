import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/peer.dart';
import 'network_service.dart';

/// HTTP-based messaging service. Each client runs an HTTP server.
class ChatService {
  static const _uuid = Uuid();
  static const int defaultPort = 50555;

  final String myId;
  final String myName;

  HttpServer? _server;
  int _port = defaultPort;

  int get port => _port;

  // peerId -> list of messages
  final Map<String, List<ChatMessage>> _conversations = {};
  final StreamController<MapEntry<String, ChatMessage>> _messageController =
      StreamController.broadcast();

  Stream<MapEntry<String, ChatMessage>> get messageStream =>
      _messageController.stream;

  // Track unread counts per peer
  final Map<String, int> _unreadCounts = {};
  final StreamController<Map<String, int>> _unreadController =
      StreamController.broadcast();
  Stream<Map<String, int>> get unreadStream => _unreadController.stream;

  /// Called when a remote peer sends a /discover request to us.
  void Function(Peer)? onPeerDiscovered;

  ChatService({required this.myId, required this.myName});

  List<ChatMessage> getMessages(String peerId) =>
      _conversations[peerId] ?? [];

  int getUnreadCount(String peerId) => _unreadCounts[peerId] ?? 0;

  void clearUnread(String peerId) {
    _unreadCounts[peerId] = 0;
    _unreadController.add(Map.from(_unreadCounts));
  }

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, defaultPort);
      _port = defaultPort;
    } catch (_) {
      // Port already in use, bind to a random available port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _port = _server!.port;
    }

    _server!.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'POST' && request.uri.path == '/discover') {
        await _handleDiscover(request);
      } else if (request.method == 'POST' && request.uri.path == '/message') {
        await _handleMessage(request);
      } else if (request.uri.path == '/alive') {
        await _handleAlive(request);
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    } catch (_) {
      try {
        request.response.statusCode = 500;
        await request.response.close();
      } catch (_) {}
    }
  }

  /// Handle POST /discover — a remote peer is asking if we are MilkyChat.
  /// We save the sender's info and respond with our own.
  Future<void> _handleDiscover(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final data = jsonDecode(body) as Map<String, dynamic>;

    final peer = Peer(
      id: data['id'] as String,
      name: data['name'] as String,
      ip: data['ip'] as String,
      port: data['port'] as int,
    );
    onPeerDiscovered?.call(peer);

    final network = NetworkService();
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'id': myId,
        'name': myName,
        'ip': network.localIp,
        'port': _port,
      }));
    await request.response.close();
  }

  /// Handle /alive — lightweight liveness probe. Used by other peers to check
  /// whether this MilkyChat instance is still online (by name or by IP).
  /// Responds with this user's id/name/ip without registering anyone as a peer.
  Future<void> _handleAlive(HttpRequest request) async {
    final network = NetworkService();
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'alive': true,
        'id': myId,
        'name': myName,
        'ip': network.localIp,
        'port': _port,
      }));
    await request.response.close();
  }

  /// Handle POST /message — a remote peer sends us a chat message.
  /// Body shape: {senderId, senderName, message, datetime, ip}
  /// Response shape: {getterId, getterName, ip}
  Future<void> _handleMessage(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final msg = ChatMessage.fromWireJson(json, myId);
    final peerId = msg.senderId;

    _conversations.putIfAbsent(peerId, () => []);
    _conversations[peerId]!.add(msg);

    _unreadCounts[peerId] = (_unreadCounts[peerId] ?? 0) + 1;
    _unreadController.add(Map.from(_unreadCounts));

    _messageController.add(MapEntry(peerId, msg));

    final network = NetworkService();
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({
        'getterId': myId,
        'getterName': myName,
        'ip': network.localIp ?? '',
      }));
    await request.response.close();
  }

  /// Send a text message to a peer via HTTP POST.
  /// On success, the sender also saves the message to its own chat history.
  Future<bool> sendMessage(Peer peer, String text) async {
    final network = NetworkService();
    final msg = ChatMessage(
      id: _uuid.v4(),
      senderId: myId,
      senderName: myName,
      senderIp: network.localIp ?? '',
      content: text,
      timestamp: DateTime.now(),
      type: MessageType.text,
      isMe: true,
    );

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);

      final request = await client.postUrl(
        Uri.parse('http://${peer.ip}:${peer.port}/message'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(msg.toWireJson()));

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      // Drain so the recipient's {getterId, getterName, ip} ack is consumed.
      await utf8.decoder.bind(response).join();
      client.close(force: true);

      if (response.statusCode != 200) {
        throw HttpException('status ${response.statusCode}');
      }

      // Sender stores the message in its own chat only after a successful ack.
      _conversations.putIfAbsent(peer.id, () => []);
      _conversations[peer.id]!.add(msg);
      _messageController.add(MapEntry(peer.id, msg));

      return true;
    } catch (_) {
      final errorMsg = ChatMessage(
        id: _uuid.v4(),
        senderId: myId,
        senderName: 'System',
        senderIp: network.localIp ?? '',
        content: 'Message delivery failed. Is ${peer.name} still online?',
        timestamp: DateTime.now(),
        type: MessageType.system,
        isMe: true,
      );
      _conversations.putIfAbsent(peer.id, () => []);
      _conversations[peer.id]!.add(errorMsg);
      _messageController.add(MapEntry(peer.id, errorMsg));
      return false;
    }
  }

  void dispose() {
    _server?.close();
    _messageController.close();
    _unreadController.close();
  }
}
