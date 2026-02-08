import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// A discovered OpenClaw gateway on the network.
class DiscoveredGateway {
  final String host;
  final int port;
  final String? name;
  final String source; // 'mdns' or 'scan'

  const DiscoveredGateway({
    required this.host,
    required this.port,
    this.name,
    required this.source,
  });

  String get wsUrl => 'ws://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredGateway && host == other.host && port == other.port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '${name ?? host}:$port ($source)';
}

/// Discovers OpenClaw gateways via mDNS and network scanning.
class DiscoveryService {
  static const _serviceType = '_openclaw._tcp';
  static const _defaultPort = 18789;
  static const _scanTimeoutMs = 500; // Per-host connection timeout

  /// Discover gateways. Tries mDNS first, falls back to subnet scan.
  /// Returns results as they are found via the stream.
  static Stream<DiscoveredGateway> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async* {
    final seen = <String>{};

    // Phase 1: mDNS discovery
    debugPrint('🔍 Starting mDNS discovery for $_serviceType...');
    await for (final gw in _discoverMdns(timeout: const Duration(seconds: 5))) {
      final key = '${gw.host}:${gw.port}';
      if (seen.add(key)) {
        yield gw;
      }
    }

    // Phase 2: Subnet port scan fallback
    debugPrint('🔍 Starting subnet port scan fallback...');
    await for (final gw in _scanSubnet()) {
      final key = '${gw.host}:${gw.port}';
      if (seen.add(key)) {
        yield gw;
      }
    }
  }

  /// Discover via mDNS (multicast DNS).
  static Stream<DiscoveredGateway> _discoverMdns({
    required Duration timeout,
  }) async* {
    final MDnsClient client = MDnsClient();
    try {
      await client.start();

      // Look up PTR records for the service type
      final deadline = DateTime.now().add(timeout);

      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('$_serviceType.local'),
      ).timeout(timeout, onTimeout: (sink) => sink.close())) {
        if (DateTime.now().isAfter(deadline)) break;

        debugPrint('🔍 mDNS PTR: ${ptr.domainName}');

        // Resolve SRV record for the service instance
        String? host;
        int port = _defaultPort;
        String? name = ptr.domainName.replaceAll('.$_serviceType.local', '');

        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        ).timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
          port = srv.port;
          // Resolve the hostname to an IP
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          ).timeout(const Duration(seconds: 2), onTimeout: (sink) => sink.close())) {
            host = ip.address.address;
            break;
          }
          break;
        }

        if (host != null) {
          debugPrint('🔍 mDNS found: $name at $host:$port');
          yield DiscoveredGateway(
            host: host,
            port: port,
            name: name,
            source: 'mdns',
          );
        }
      }
    } catch (e) {
      debugPrint('🔍 mDNS error: $e');
    } finally {
      client.stop();
    }
  }

  /// Scan common ports on the local subnet as a fallback.
  static Stream<DiscoveredGateway> _scanSubnet() async* {
    final localIp = await _getLocalIp();
    if (localIp == null) {
      debugPrint('🔍 Cannot determine local IP for subnet scan');
      return;
    }

    // Extract subnet prefix (e.g., 192.168.1.)
    final parts = localIp.split('.');
    if (parts.length != 4) return;
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';

    debugPrint('🔍 Scanning subnet $prefix* on port $_defaultPort...');

    // Scan common IPs: .1 (router), .2-.20 (common server range),
    // plus host portion of our own IP ± a few
    final targets = <int>{};
    // Common server addresses
    for (int i = 1; i <= 30; i++) {
      targets.add(i);
    }
    // Around our own IP
    final selfOctet = int.tryParse(parts[3]) ?? 0;
    for (int i = -5; i <= 5; i++) {
      final octet = selfOctet + i;
      if (octet >= 1 && octet <= 254) targets.add(octet);
    }
    // Common high addresses
    targets.addAll([100, 200, 250, 254]);

    // Scan in parallel batches
    const batchSize = 20;
    final targetList = targets.toList()..sort();

    for (int i = 0; i < targetList.length; i += batchSize) {
      final batch = targetList.sublist(
        i,
        (i + batchSize).clamp(0, targetList.length),
      );

      final futures = batch.map((octet) async {
        final host = '$prefix$octet';
        try {
          final socket = await Socket.connect(
            host,
            _defaultPort,
            timeout: Duration(milliseconds: _scanTimeoutMs),
          );
          await socket.close();
          return DiscoveredGateway(
            host: host,
            port: _defaultPort,
            source: 'scan',
          );
        } catch (_) {
          return null;
        }
      });

      final results = await Future.wait(futures);
      for (final gw in results) {
        if (gw != null) {
          debugPrint('🔍 Port scan found: ${gw.host}:${gw.port}');
          yield gw;
        }
      }
    }
  }

  /// Get the device's local IP address.
  static Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        // Skip loopback and docker/virtual interfaces
        if (iface.name.startsWith('lo') ||
            iface.name.startsWith('docker') ||
            iface.name.startsWith('veth')) {
          continue;
        }
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('🔍 Failed to get local IP: $e');
    }
    return null;
  }
}
