# ClawReach 🦊📱

A Flutter mobile client for [OpenClaw](https://github.com/openclaw/openclaw) — connect your phone as a node with chat, camera, voice notes, fitness tracking, smart home integration, and offline push notifications.

## Features

### Chat
- **Real-time chat** with your OpenClaw AI assistant
- **Push notifications** - Receive notifications when app is closed (FCM)
- **Session history syncing** - Full conversation history from all clients (webchat, Signal, etc.)
- **Offline message cache** - Last 100 messages cached locally for offline viewing
- **Voice notes** with automatic transcription (server-side or on-device fallback)
- **Photo sharing** — camera or gallery (single + multi-select up to 10)
- **Long-press context menu** - copy, select text, share media
- **Streaming message display** with typing indicators
- **Message queue** - Send messages while offline, auto-deliver when reconnected

### Push Notifications (v1.1.0+)
- **Firebase Cloud Messaging (FCM)** integration for reliable offline delivery
- **Background notifications** - Receive messages when app is killed/swiped away
- **Smart delivery** - Only sends push when ClawReach is offline
- **Auto-reconnect** - Tap notification to open app and resume conversation
- **Full history on open** - See complete conversation context from notification

### Fitness Tracker
- **GPS activity tracking** - Hike, Run, Walk, Bike, Ski, Swim, Kayak, Other
- **One-tap start** from activity card grid
- **Live stats** - distance, duration, pace, speed
- **Auto GPX export** on stop with Android share sheet
- **Mini map preview** (non-interactive) + tap for full detail view
- **Background tracking** — chat while recording
- **Offline-first** - works without cell reception
- **Activity sync** to gateway on completion (or queued for later)

### Node Capabilities
- **Ed25519 challenge-response authentication**
- **Device pairing** with approval flow
- **Camera snap** (front/back)
- **Canvas/A2UI rendering** via WebView (with postMessage bridge for web platform)
- **Location sharing**
- **Push notifications** via FCM
- **Auto-reconnect** with exponential backoff
- **Session history fetching** - Sync messages from other clients on connect

### Compatibility
ClawReach auto-detects server capabilities and degrades gracefully:

| Feature | Custom Setup | Vanilla OpenClaw |
|---------|-------------|-----------------|
| Photos | Full quality (1920px/80%) | Auto-compressed (800px/50%) to fit 512KB WebSocket limit |
| Voice notes | Server transcription (faster-whisper) | Audio attachment fallback |
| Fitness sync | Agent logs activity | Silent skip (data saved locally) |
| Push notifications | FCM bridge required | Skipped gracefully |
| Session history | Full sync | Cached messages only |
| Chat | Full featured | Full featured |

> **Note:** [PR #6805](https://github.com/openclaw/openclaw/pull/6805) increases the gateway WebSocket payload limit to 6MB, enabling full-quality photo support on vanilla installs.

## What's New in v1.1.2

### 🎉 Session History Fetching
- **Full conversation sync** - ClawReach now fetches the last 50 messages from the gateway when connecting
- **Cross-client visibility** - See messages sent from webchat, Signal, and other clients
- **Smart merging** - Deduplicates and sorts messages chronologically with local cache
- **Complete context** - Tap a notification and see the full conversation thread

### Technical Improvements
- Uses `sessions.history` WebSocket request to gateway
- Merges server history with offline cache on every connect
- Maintains chronological order across all message sources
- Automatic deduplication by message ID

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
│   ├── gateway_service.dart           # WebSocket connection (chat + history fetching)
│   ├── node_connection_service.dart   # WebSocket connection (node)
│   ├── crypto_service.dart            # Ed25519 key management
│   ├── chat_service.dart              # Chat state, history sync, file sending
│   ├── capability_service.dart        # Server feature detection
│   ├── message_cache.dart             # Offline message persistence (SharedPreferences)
│   ├── message_queue.dart             # Offline message queue
│   ├── fcm_service.dart               # Firebase Cloud Messaging integration
│   ├── hike_service.dart              # GPS tracking + activity storage
│   ├── camera_service.dart            # Camera snap handling (mobile + web)
│   ├── canvas_service.dart            # Canvas/A2UI rendering
│   ├── location_service.dart          # Location sharing (mobile + web)
│   ├── notification_service.dart      # Local notifications
│   └── cached_tile_provider.dart      # Offline map tile cache
├── screens/
│   ├── home_screen.dart               # Main chat + media UI
│   ├── settings_screen.dart           # Gateway config + validation
│   └── hike_screen.dart               # Fitness tracker UI
└── widgets/
    ├── chat_bubble.dart               # Message bubble + context menu
    ├── activity_map.dart              # Map with GPS trail overlay
    ├── canvas_overlay.dart            # A2UI canvas WebView (with postMessage bridge)
    └── connection_badge.dart          # Connection status indicator
```

## Setup

### Prerequisites
- Flutter SDK 3.10+
- Android device or emulator (iOS support coming soon)
- OpenClaw gateway running and accessible

### Install
```bash
git clone https://github.com/cortexuvula/clawreach.git
cd clawreach
flutter pub get
flutter run
```

Or download the latest APK from [Releases](https://github.com/cortexuvula/clawreach/releases).

### Connect
1. Open the app → Settings (gear icon)
2. Enter gateway URL: `ws://<your-gateway-ip>:18789`
3. Optional: Tailscale fallback URL for better reliability
4. Enter gateway token
5. Save → device will auto-pair (approve in OpenClaw)

### Optional: Push Notifications (FCM)
For offline push notifications when the app is closed:

1. **Set up Firebase** - Create a Firebase project and download `google-services.json`
2. **Run FCM bridge** - Start the FCM bridge service on your OpenClaw host:
   ```bash
   node ~/clawd/scripts/fcm-bridge.js
   ```
3. **Auto-push daemon** (optional) - For automatic push delivery:
   ```bash
   systemctl --user start fcm-auto-push.service
   ```

ClawReach will auto-register its FCM token with the bridge on connect.

### Optional: Server-Side Transcription
For high-quality voice note transcription, run a [faster-whisper](https://github.com/SYSTRAN/faster-whisper) server on port 8014 of your gateway host. ClawReach auto-detects it on connect.

## Device Pairing

When ClawReach first connects, the gateway requires pairing approval. Here's how it works:

### Normal Flow (when working)
1. ClawReach connects → gateway creates pending pairing request
2. Your AI agent sees the request via `nodes pending`
3. Agent approves it → device is paired → ClawReach reconnects automatically

### Known Issue (OpenClaw ≤ 2026.1.30)

> **⚠️ The `nodes pending` and `nodes approve` agent tools may not see pairing requests from new devices.** This is tracked in [openclaw/openclaw#6836](https://github.com/openclaw/openclaw/issues/6836) with a fix in [PR #6846](https://github.com/openclaw/openclaw/pull/6846).

The gateway has two separate pairing stores (`devices/` and `nodes/`) that don't communicate. When a new device connects, the pending request goes to `devices/pending.json`, but the agent tools only read from `nodes/pending.json`.

**Workaround until the fix is merged:**

**Option A: Manual approval**
```bash
# 1. Find the pending request (includes the device's public key)
cat ~/.openclaw/devices/pending.json

# 2. Copy the entry to paired.json with the publicKey
# (the publicKey MUST match — an empty string won't work)
python3 -c "
import json, secrets, time
with open('$HOME/.openclaw/devices/pending.json') as f:
    pending = json.load(f)
with open('$HOME/.openclaw/devices/paired.json') as f:
    paired = json.load(f)

for rid, req in list(pending.items()):
    did = req['deviceId']
    now = int(time.time() * 1000)
    paired[did] = {
        'deviceId': did,
        'publicKey': req['publicKey'],  # Critical — must match!
        'displayName': req.get('displayName', 'ClawReach'),
        'platform': req.get('platform', 'Android'),
        'clientId': req.get('clientId', ''),
        'clientMode': req.get('clientMode', 'node'),
        'role': req.get('role', 'node'),
        'roles': ['operator', 'node'],
        'scopes': req.get('scopes', []),
        'remoteIp': req.get('remoteIp', ''),
        'tokens': {
            'node': {'token': secrets.token_hex(16), 'role': 'node', 'scopes': [], 'createdAtMs': now},
            'operator': {'token': secrets.token_hex(16), 'role': 'operator', 'scopes': ['operator.admin'], 'createdAtMs': now},
        },
        'createdAtMs': now, 'approvedAtMs': now,
    }
    del pending[rid]
    print(f'Approved: {req.get(\"displayName\", did[:16])}')

with open('$HOME/.openclaw/devices/pending.json', 'w') as f:
    json.dump(pending, f, indent=2)
with open('$HOME/.openclaw/devices/paired.json', 'w') as f:
    json.dump(paired, f, indent=2)
print('Done — restart gateway to apply')
"

# 3. Restart the gateway
openclaw gateway restart
```

**Option B: Apply the fix**

If you're building OpenClaw from source, cherry-pick the fix from [PR #6846](https://github.com/openclaw/openclaw/pull/6846) which bridges the two pairing stores.

### Re-pairing After App Reinstall

Each install of ClawReach generates a new cryptographic keypair, which means a new device ID. After reinstalling or clearing app data, you'll need to pair again. Old entries in `paired.json` for previous installs can be safely removed.

## Protocol

ClawReach implements the OpenClaw node protocol:

1. **Connect** — WebSocket to `ws://gateway:port`
2. **Challenge** — Server sends `connect.challenge` with nonce
3. **Auth** — Client signs nonce with Ed25519 private key
4. **Pair** — If new device, server creates pending request; client retries until approved
5. **Connected** — Bidirectional messaging: camera snaps, location, canvas, chat, fitness sync
6. **History Sync** — Request session history via `sessions.history` WebSocket request
7. **FCM Registration** — Register push notification token with FCM bridge (if available)

## Performance & Offline Support

### Message Caching
- Last 100 messages cached locally in SharedPreferences
- Automatic cache on every message sent/received
- Loaded on app startup for offline viewing

### Message Queue
- Messages sent while offline are queued automatically
- Auto-delivered when connection restored
- Persistent across app restarts

### Session History
- Fetches last 50 messages from gateway on connect
- Merges with local cache (no duplicates)
- Shows messages from all clients (webchat, Signal, etc.)

### Push Notifications
- FCM delivers notifications when app is closed
- Tapping notification opens app with full history
- Smart delivery - only pushes when offline

## Version History

- **v1.1.2** (2026-02-07) - Session history fetching from gateway
- **v1.1.1** (2026-02-07) - Fixed offline message cache loading
- **v1.1.0** (2026-02-07) - FCM push notifications, removed background service
- **v1.0.9** (2026-02-07) - Fixed FCM bridge URL derivation
- **v1.0.8** (2026-02-07) - FCM integration
- **v1.0.7** (2026-02-06) - Performance optimizations, camera/location web support
- **v1.0.6** (2026-02-05) - Canvas postMessage bridge for web platform

## Built By

Andre & Fred 🦊

## License

MIT
