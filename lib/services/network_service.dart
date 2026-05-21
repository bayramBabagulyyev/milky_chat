import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:network_info_plus/network_info_plus.dart';

/// Handles local IP detection and network utilities.
class NetworkService {
  static final NetworkService _instance = NetworkService._();
  factory NetworkService() => _instance;
  NetworkService._();

  String? _localIp;
  String? _broadcastAddress;

  String? get localIp => _localIp;
  String? get broadcastAddress => _broadcastAddress;

  Future<void> init() async {
    _localIp = await _getLocalIp();
    if (_localIp != null) {
      final parts = _localIp!.split('.');
      parts[3] = '255';
      _broadcastAddress = parts.join('.');
    }
  }

  Future<String?> _getLocalIp() async {
    try {
      // Try network_info_plus first
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty) return ip;
    } catch (_) {}

    // Fallback: iterate network interfaces
    try {
      for (final iface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      )) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
