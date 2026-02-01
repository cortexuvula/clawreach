# ClawReach 🦊📱

A Flutter client for [OpenClaw](https://github.com/openclaw/openclaw) gateway — connect your phone as a node with camera, microphone, and notification capabilities.

## Features (Planned)

### v1.0 — Core Connection
- [ ] WebSocket connection to OpenClaw gateway
- [ ] Ed25519 key generation & challenge-response auth
- [ ] Device pairing flow (auto-approve or manual)
- [ ] Settings UI (gateway URL, token, node name)
- [ ] Connection status indicator
- [ ] Basic chat/message display
- [ ] Push notifications

### v2.0 — Capabilities
- [ ] Camera snap (front/back)
- [ ] Screen recording
- [ ] Voice wake (speech recognition → command dispatch)
- [ ] Canvas rendering (WebView)
- [ ] Location sharing

### v3.0 — Polish
- [ ] Background service (persistent connection)
- [ ] Battery optimization
- [ ] Auto-reconnect with backoff
- [ ] Notification actions (reply inline)
- [ ] Biometric auth for sensitive operations

## Architecture

```
lib/
├── main.dart                 # App entry point
├── models/
│   ├── gateway_config.dart   # Connection settings model
│   └── message.dart          # Message/event models
├── services/
│   ├── gateway_service.dart  # WebSocket connection manager
│   ├── crypto_service.dart   # Ed25519 key management
│   └── pairing_service.dart  # Device pairing flow
├── screens/
│   ├── home_screen.dart      # Main screen with connection status
│   ├── settings_screen.dart  # Gateway URL, token, preferences
│   └── chat_screen.dart      # Message display
├── widgets/
│   └── connection_badge.dart # Green/red connection indicator
└── crypto/
    └── ed25519.dart          # Ed25519 helpers
```

## Protocol

ClawReach implements the OpenClaw node protocol:

1. **Connect** — WebSocket to `wss://gateway:port/ws/node`
2. **Challenge** — Server sends `connect.challenge` with nonce
3. **Auth** — Client signs nonce with Ed25519 private key, sends `connect` with public key + signature
4. **Paired** — Server approves device, connection established
5. **Messaging** — Bidirectional JSON messages over WebSocket

## Development

```bash
flutter pub get
flutter run
```

## Built By

Andre & Fred 🦊 — because waiting on upstream PRs is no fun.

## License

MIT
