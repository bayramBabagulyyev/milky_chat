import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/peer.dart';
import '../services/milky_provider.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() => _searchQuery = query);

    if (query.isEmpty) return;

    // Auto-open chat when the typed text exactly matches a peer's name or IP.
    // Verify the peer is still alive via /alive before opening the chat.
    final provider = context.read<MilkyProvider>();
    final peers = provider.peers.values.where((p) => p.isOnline).toList();
    final exactMatch = peers.where(
      (p) => p.name.toLowerCase() == query || p.ip == query,
    );
    if (exactMatch.length == 1) {
      _openPeerIfAlive(exactMatch.first);
    }
  }

  Future<void> _openPeerIfAlive(Peer peer) async {
    final provider = context.read<MilkyProvider>();
    final alive = await provider.checkPeerAlive(peer);
    if (!mounted) return;
    if (!alive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${peer.name} is offline')),
      );
      return;
    }
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _isSearching = false;
    });
    provider.setActivePeer(peer.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
    );
  }

  Future<void> _scanNetwork() async {
    setState(() => _isScanning = true);
    final provider = context.read<MilkyProvider>();
    await provider.refreshDiscovery();
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  void _showConnectByIpDialog() {
    final ipController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect by IP'),
        content: TextField(
          controller: ipController,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '192.168.1.100',
            labelText: 'IP Address',
            prefixIcon: const Icon(Icons.lan),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: (_) {
            _connectToIp(ipController.text.trim());
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              _connectToIp(ipController.text.trim());
              Navigator.of(ctx).pop();
            },
            icon: const Icon(Icons.search),
            label: const Text('Find'),
          ),
        ],
      ),
    );
  }

  Future<void> _connectToIp(String ip) async {
    if (ip.isEmpty) return;
    final provider = context.read<MilkyProvider>();
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Checking $ip is alive...'),
        duration: const Duration(seconds: 2),
      ),
    );
    final found = await provider.probeIp(ip);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(found ? 'Found device at $ip' : 'No device alive at $ip'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search by name or IP...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                  border: InputBorder.none,
                ),
              )
            : const Row(
                children: [
                  Icon(Icons.chat_bubble_rounded, size: 24),
                  SizedBox(width: 8),
                  Text('MilkyChat'),
                ],
              ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          // Search toggle button
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            tooltip: _isSearching ? 'Close search' : 'Search users',
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          // Connect by IP button
          IconButton(
            icon: const Icon(Icons.lan),
            tooltip: 'Connect by IP address',
            onPressed: _showConnectByIpDialog,
          ),
          // Scan network button
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.wifi_find),
            tooltip: 'Scan for users on network',
            onPressed: _isScanning ? null : _scanNetwork,
          ),
          Consumer<MilkyProvider>(
            builder: (_, provider, __) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  provider.myName,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<MilkyProvider>(
        builder: (context, provider, _) {
          var onlinePeers = provider.peers.values
              .where((p) => p.isOnline)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

          // Filter by search query (name or IP)
          if (_searchQuery.isNotEmpty) {
            onlinePeers = onlinePeers
                .where((p) =>
                    p.name.toLowerCase().contains(_searchQuery) ||
                    p.ip.contains(_searchQuery))
                .toList();
          }

          if (provider.peers.values.where((p) => p.isOnline).isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_find,
                      size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'Searching for peers...',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make sure other devices are running MilkyChat\non the same network',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanNetwork,
                    icon: const Icon(Icons.wifi_find),
                    label: Text(_isScanning ? 'Scanning...' : 'Scan Network'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }

          if (_searchQuery.isNotEmpty && onlinePeers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_search,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No users found for "$_searchQuery"',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: onlinePeers.length,
            itemBuilder: (context, index) {
              final peer = onlinePeers[index];
              return _PeerTile(peer: peer);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _scanNetwork,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        icon: _isScanning
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.wifi_find),
        label: Text(_isScanning ? 'Scanning...' : 'Find Devices'),
      ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final Peer peer;

  const _PeerTile({required this.peer});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MilkyProvider>();
    final unread = provider.getUnreadCount(peer.id);
    final messages = provider.getMessagesFor(peer.id);
    final lastMsg = messages.isNotEmpty ? messages.last : null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.deepPurple.shade100,
        child: Text(
          peer.name.isNotEmpty ? peer.name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.deepPurple.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              peer.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (lastMsg != null)
            Text(
              _formatTime(lastMsg.timestamp),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Expanded(
            child: Text(
              lastMsg?.content ?? peer.ip,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      trailing: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: peer.isOnline ? Colors.green : Colors.grey,
          shape: BoxShape.circle,
        ),
      ),
      onTap: () {
        provider.setActivePeer(peer.id);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatScreen(peer: peer),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (time.day == now.day &&
        time.month == now.month &&
        time.year == now.year) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day}/${time.month}';
  }
}
