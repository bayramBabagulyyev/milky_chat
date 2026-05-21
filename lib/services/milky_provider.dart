import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/peer.dart';
import 'chat_service.dart';
import 'discovery_service.dart';
import 'network_service.dart';

export 'discovery_service.dart' show AliveResult;

/// Central state manager for MilkyChat.
class MilkyProvider extends ChangeNotifier {
  static const _uuid = Uuid();

  late String _myId;
  late String _myName;
  late ChatService _chatService;
  late DiscoveryService _discoveryService;

  String get myId => _myId;
  String get myName => _myName;

  Map<String, Peer> _peers = {};
  Map<String, Peer> get peers => _peers;

  String? _activePeerId;
  String? get activePeerId => _activePeerId;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  StreamSubscription? _peersSub;
  StreamSubscription? _messageSub;
  StreamSubscription? _unreadSub;

  Map<String, int> _unreadCounts = {};
  Map<String, int> get unreadCounts => _unreadCounts;

  List<ChatMessage> get activeMessages =>
      _activePeerId != null ? _chatService.getMessages(_activePeerId!) : [];

  Future<void> init(String displayName) async {
    final prefs = await SharedPreferences.getInstance();
    _myId = prefs.getString('milky_id') ?? _uuid.v4();
    await prefs.setString('milky_id', _myId);

    _myName = displayName;
    await prefs.setString('milky_name', _myName);

    // Initialize network first so all services can use the local IP
    final network = NetworkService();
    await network.init();

    // Start the HTTP server (handles /discover and /message)
    _chatService = ChatService(myId: _myId, myName: _myName);
    await _chatService.start();

    // Start discovery service
    _discoveryService = DiscoveryService(
      myId: _myId,
      myName: _myName,
      myPort: _chatService.port,
    );
    await _discoveryService.start();

    // When someone sends POST /discover to our HTTP server, add them as a peer
    _chatService.onPeerDiscovered = (peer) {
      _discoveryService.addPeer(peer);
      _peers = _discoveryService.peers;
      notifyListeners();
    };

    _peersSub = _discoveryService.peersStream.listen((peers) {
      _peers = peers;
      notifyListeners();
    });

    _messageSub = _chatService.messageStream.listen((entry) {
      notifyListeners();
    });

    _unreadSub = _chatService.unreadStream.listen((counts) {
      _unreadCounts = counts;
      notifyListeners();
    });

    _isInitialized = true;
    notifyListeners();
  }

  static Future<String?> getSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('milky_name');
  }

  void setActivePeer(String? peerId) {
    _activePeerId = peerId;
    if (peerId != null) {
      _chatService.clearUnread(peerId);
    }
    notifyListeners();
  }

  Future<bool> sendMessage(String text) async {
    if (_activePeerId == null) return false;
    final peer = _peers[_activePeerId];
    if (peer == null) return false;
    return await _chatService.sendMessage(peer, text);
  }

  /// Scan the entire local subnet for MilkyChat peers.
  Future<void> refreshDiscovery() async {
    await _discoveryService.scanNetwork();
  }

  /// Probe a specific IP address to find a peer directly.
  /// First does a lightweight /alive check; only runs full /discover if alive.
  Future<bool> probeIp(String ip) async {
    final alive = await _discoveryService.checkAlive(ip);
    if (!alive.alive) return false;
    await _discoveryService.probeIp(ip);
    return true;
  }

  /// Check whether an arbitrary IP is alive (no registration as a peer).
  Future<AliveResult> checkAlive(String ip) =>
      _discoveryService.checkAlive(ip);

  /// Verify a known peer is alive and update its online flag.
  Future<bool> checkPeerAlive(Peer peer) async {
    final result = await _discoveryService.checkPeerAlive(peer);
    return result.alive;
  }

  List<ChatMessage> getMessagesFor(String peerId) =>
      _chatService.getMessages(peerId);

  int getUnreadCount(String peerId) => _chatService.getUnreadCount(peerId);

  @override
  void dispose() {
    _peersSub?.cancel();
    _messageSub?.cancel();
    _unreadSub?.cancel();
    _discoveryService.dispose();
    _chatService.dispose();
    super.dispose();
  }
}
