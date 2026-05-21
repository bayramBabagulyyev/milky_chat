import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/peer.dart';
import 'network_service.dart';

/// Lightweight result of a /alive probe.
class AliveResult {
  final bool alive;
  final String? id;
  final String? name;
  final String? ip;
  final int? port;

  const AliveResult({
    required this.alive,
    this.id,
    this.name,
    this.ip,
    this.port,
  });

  static const AliveResult dead = AliveResult(alive: false);
}

/// HTTP-based peer discovery. Scans all IPs in the local subnet.
class DiscoveryService {
  static const int defaultPort = 50555;

  final String myId;
  final String myName;
  final int myPort;
  final NetworkService _network = NetworkService();

  final Map<String, Peer> _peers = {};
  final StreamController<Map<String, Peer>> _peersController =
      StreamController.broadcast();

  Stream<Map<String, Peer>> get peersStream => _peersController.stream;
  Map<String, Peer> get peers => Map.unmodifiable(_peers);

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  DiscoveryService({
    required this.myId,
    required this.myName,
    required this.myPort,
  });

  Future<void> start() async {
    await _network.init();
  }

  /// Add a discovered peer (called from both scanning and incoming requests).
  void addPeer(Peer peer) {
    if (peer.id == myId) return;

    final isNew = !_peers.containsKey(peer.id);
    _peers[peer.id] = peer;
    _peers[peer.id]!.lastSeen = DateTime.now();
    _peers[peer.id]!.isOnline = true;

    if (isNew) {
      _peersController.add(Map.unmodifiable(_peers));
    }
  }

  /// Scan all IPs (1–254) in the local /24 subnet for MilkyChat peers.
  Future<void> scanNetwork() async {
    if (_network.localIp == null || _isScanning) return;

    _isScanning = true;

    final parts = _network.localIp!.split('.');
    final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';

    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      if (ip == _network.localIp) continue;
      futures.add(_probeIp(ip));
    }

    await Future.wait(futures);
    _isScanning = false;
  }

  /// Probe a single IP address to check if MilkyChat is running.
  Future<void> probeIp(String ip) async {
    await _probeIp(ip);
  }

  /// Lightweight liveness check against a single IP's /alive endpoint.
  /// Does NOT register the remote as a peer — use [probeIp] for that.
  Future<AliveResult> checkAlive(String ip, {int port = defaultPort}) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);

      final request = await client
          .getUrl(Uri.parse('http://$ip:$port/alive'))
          .timeout(const Duration(seconds: 2));

      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );

      if (response.statusCode != 200) {
        await response.drain();
        client.close(force: true);
        return AliveResult.dead;
      }

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 2));
      client.close(force: true);

      final data = jsonDecode(body) as Map<String, dynamic>;
      return AliveResult(
        alive: data['alive'] == true,
        id: data['id'] as String?,
        name: data['name'] as String?,
        ip: data['ip'] as String? ?? ip,
        port: data['port'] as int? ?? port,
      );
    } catch (_) {
      return AliveResult.dead;
    }
  }

  /// Verify a known peer is still alive and update its online flag.
  /// Returns the alive result.
  Future<AliveResult> checkPeerAlive(Peer peer) async {
    final result = await checkAlive(peer.ip, port: peer.port);
    final existing = _peers[peer.id];
    if (existing != null) {
      existing.isOnline = result.alive;
      if (result.alive) existing.lastSeen = DateTime.now();
      _peersController.add(Map.unmodifiable(_peers));
    }
    return result;
  }

  Future<void> _probeIp(String ip) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 1);

      final request = await client
          .postUrl(Uri.parse('http://$ip:$defaultPort/discover'))
          .timeout(const Duration(seconds: 2));

      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'id': myId,
        'name': myName,
        'ip': _network.localIp,
        'port': myPort,
      }));

      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );

      if (response.statusCode == 200) {
        final body = await utf8.decoder
            .bind(response)
            .join()
            .timeout(const Duration(seconds: 2));
        final data = jsonDecode(body) as Map<String, dynamic>;

        final peer = Peer(
          id: data['id'] as String,
          name: data['name'] as String,
          ip: data['ip'] as String? ?? ip,
          port: data['port'] as int? ?? defaultPort,
        );
        addPeer(peer);
      } else {
        await response.drain();
      }

      client.close(force: true);
    } catch (_) {
      // IP doesn't have MilkyChat running, or unreachable — ignore
    }
  }

  void dispose() {
    _peersController.close();
  }
}
