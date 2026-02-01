import 'package:flutter_test/flutter_test.dart';
import 'package:clawreach/models/gateway_config.dart';
import 'package:clawreach/models/message.dart';

void main() {
  group('GatewayConfig', () {
    test('generates correct WS URL from HTTPS', () {
      final config = GatewayConfig(url: 'https://example.com:3000', token: 'test');
      expect(config.wsUrl, 'wss://example.com:3000/ws/node');
    });

    test('generates correct WS URL from HTTP', () {
      final config = GatewayConfig(url: 'http://example.com:3000', token: 'test');
      expect(config.wsUrl, 'ws://example.com:3000/ws/node');
    });

    test('serializes to JSON', () {
      final config = GatewayConfig(url: 'https://gw.example.com', token: 'abc123');
      final json = config.toJson();
      expect(json['url'], 'https://gw.example.com');
      expect(json['token'], 'abc123');
    });

    test('deserializes from JSON', () {
      final config = GatewayConfig.fromJson({'url': 'https://test.com', 'token': 'xyz'});
      expect(config.url, 'https://test.com');
      expect(config.token, 'xyz');
      expect(config.nodeName, 'ClawReach');
    });
  });

  group('GatewayConnectionState', () {
    test('has all expected states', () {
      expect(GatewayConnectionState.values.length, 5);
      expect(GatewayConnectionState.values, contains(GatewayConnectionState.connected));
      expect(GatewayConnectionState.values, contains(GatewayConnectionState.disconnected));
    });
  });
}
