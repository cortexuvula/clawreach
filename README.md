# ClawReach 🦊📱

A Flutter mobile client for [OpenClaw](https://github.com/openclaw/openclaw) — connect your phone as a node with chat, camera, voice notes, fitness tracking, and smart home integration.

## Features

### Chat
- Real-time chat with your OpenClaw AI assistant
- Voice notes with automatic transcription (server-side or on-device fallback)
- Photo sharing — camera or gallery (single + multi-select up to 10)
- Long-press context menu: copy, select text, share media
- Streaming message display with typing indicators

### Fitness Tracker
- GPS activity tracking: Hike, Run, Walk, Bike, Ski, Swim, Kayak, Other
- One-tap start from activity card grid
- Live stats: distance, duration, pace, speed
- Auto GPX export on stop with Android share sheet
- Mini map preview (non-interactive) + tap for full detail view
- Background tracking — chat while recording
- Offline-first: works without cell reception
- Activity sync to gateway on completion (or queued for later)

### Node Capabilities
- Ed25519 challenge-response authentication
- Device pairing with approval flow
- Camera snap (front/back)
- Canvas/A2UI rendering via WebView
- Location sharing
- Push notifications
- Auto-reconnect with backoff

### Compatibility
ClawReach auto-detects server capabilities and degrades gracefully:

| Feature | Custom Setup | Vanilla OpenClaw |
|---------|-------------|-----------------|
| Photos | Full quality (1920px/80%) | Auto-compressed (800px/50%) to fit 512KB WebSocket limit |
| Voice notes | Server transcription (faster-whisper) | Audio attachment fallback |
| Fitness sync | Agent logs activity | Silent skip (data saved locally) |
| Chat | Full featured | Full featured |

> **Note:** [PR #6805](https://github.com/openclaw/openclaw/pull/6805) increases the gateway WebSocket payload limit to 6MB, enabling full-quality photo support on vanilla installs.

## Architecture

```
lib/
├── main.dart                          # App entry, provider wiring
├── models/
│   ├── gateway_config.dart            # Connection settings
│   ├── chat_message.dart              # Chat message + attachments
│   ├── message.dart                   # Gateway event models
│   └── hike_track.dart                # Fitness activity data + GPX
├── services/
│   ├── gateway_service.dart           # WebSocket connection (chat)
│   ├── node_connection_service.dart   # WebSocket connection (node)
│   ├── crypto_service.dart            # Ed25519 key management
│   ├── chat_service.dart              # Chat state + file sending
│   ├── capability_service.dart        # Server feature detection
│   ├── hike_service.dart              # GPS tracking + activity storage
│   ├── camera_service.dart            # Camera snap handling
│   ├── canvas_service.dart            # Canvas/A2UI rendering
│   ├── location_service.dart          # Location sharing
│   ├── notification_service.dart      # Push notifications
│   └── cached_tile_provider.dart      # Offline map tile cache
├── screens/
│   ├── home_screen.dart               # Main chat + media UI
│   ├── settings_screen.dart           # Gateway config + validation
│   └── hike_screen.dart               # Fitness tracker UI
└── widgets/
    ├── chat_bubble.dart               # Message bubble + context menu
    ├── activity_map.dart              # Map with GPS trail overlay
    ├── canvas_overlay.dart            # A2UI canvas WebView
    └── connection_badge.dart          # Connection status indicator
```

## Setup

### Prerequisites
- Flutter SDK 3.10+
- Android device or emulator
- OpenClaw gateway running and accessible

### Install
```bash
git clone https://github.com/cortexuvula/clawreach.git
cd clawreach
flutter pub get
flutter run
```

### Connect
1. Open the app → Settings (gear icon)
2. Enter gateway URL: `ws://<your-gateway-ip>:18789`
3. Enter gateway token
4. Save → device will auto-pair (approve in OpenClaw)

### Optional: Server-Side Transcription
For high-quality voice note transcription, run a [faster-whisper](https://github.com/SYSTRAN/faster-whisper) server on port 8014 of your gateway host. ClawReach auto-detects it on connect.

## Protocol

ClawReach implements the OpenClaw node protocol:

1. **Connect** — WebSocket to `ws://gateway:port/ws/node`
2. **Challenge** — Server sends `connect.challenge` with nonce
3. **Auth** — Client signs nonce with Ed25519 private key
4. **Paired** — Server approves device, bidirectional messaging begins
5. **Events** — Camera snaps, location, canvas, chat, fitness sync

## Built By

Andre & Fred 🦊

## License

MIT
