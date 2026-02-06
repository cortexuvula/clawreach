# ClawReach Web Connection Guide

Complete documentation of how to connect Flutter web apps to OpenClaw Gateway.

**Date:** February 6, 2026  
**Status:** ✅ Working  
**Platform:** Flutter Web + OpenClaw Gateway

---

## Problem Summary

Flutter web apps connecting to OpenClaw Gateway face three main challenges:

1. **Missing web platform support** - `path_provider` APIs don't work on web
2. **WebSocket origin restrictions** - Gateway blocks connections from localhost
3. **Device pairing per session** - Web generates new keys each browser session

---

## Part 1: Flutter Web Compatibility

### Issue: `MissingPluginException` on Web

Flutter plugins like `path_provider` use platform-specific APIs that don't exist on web.

```dart
// ❌ Crashes on web
final dir = await getApplicationCacheDirectory();
```

### Solution: Platform-Specific Code with `kIsWeb`

**Step 1:** Add `kIsWeb` checks to all platform-dependent code

```dart
import 'package:flutter/foundation.dart' show kIsWeb;

Future<void> init() async {
  if (kIsWeb) {
    debugPrint('🗺️ Tile cache: disabled (web platform)');
    return;
  }
  
  // Mobile/desktop code
  final dir = await getApplicationCacheDirectory();
  // ...
}
```

**Step 2:** Provide web alternatives using `SharedPreferences`

```dart
Future<void> _saveTrack() async {
  if (kIsWeb) {
    // Web: save to localStorage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_track', _activeTrack!.toJsonString());
  } else {
    // Mobile/desktop: save to file
    final dir = await _hikesDir();
    final file = File('${dir.path}/${_activeTrack!.id}.json');
    await file.writeAsString(_activeTrack!.toJsonString());
  }
}
```

**Step 3:** Gracefully disable unsupported features

```dart
Future<String?> exportGpx(HikeTrack track) async {
  if (kIsWeb) {
    debugPrint('⚠️ GPX export not supported on web');
    return null; // Graceful failure
  }
  
  // Mobile/desktop: file export
  // ...
}
```

### Files Modified

1. **`lib/services/cached_tile_provider.dart`**
   - Added `kIsWeb` check in `init()`
   - Made cache operations conditional

2. **`lib/services/hike_service.dart`**
   - All file I/O wrapped in `!kIsWeb` checks
   - SharedPreferences used for web storage
   - GPX export disabled on web

3. **`lib/models/hike_track.dart`**
   - Added `copyWith()` method for immutable updates

---

## Part 2: WebSocket Origin Configuration

### Issue: "origin not allowed" Error

OpenClaw Gateway rejects WebSocket connections from localhost by default.

```
❌ Connect error: origin not allowed (open the Control UI from the gateway host 
   or allow it in gateway.controlUi.allowedOrigins)
```

### Root Cause

The wildcard `*` in `allowedOrigins` doesn't actually match localhost origins. Each Flutter dev server port needs explicit approval.

### Solution: Add Explicit Localhost Origins

**Step 1:** Identify the dev server port

Check Chrome's address bar while running `flutter run -d chrome`:
```
http://localhost:46541/
```

**Step 2:** Patch the gateway config

```bash
# Using OpenClaw gateway API
openclaw gateway config.patch << 'EOF'
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": [
        "*",
        "http://localhost",
        "http://127.0.0.1",
        "http://localhost:46541",  // <-- Add your port here
        "http://localhost:*"       // Doesn't work - not a real wildcard
      ]
    }
  }
}
EOF
```

**Step 3:** Restart gateway to apply

```bash
openclaw gateway restart
```

### Flutter DevTools Port Detection

Flutter randomly assigns ports. To avoid repeated config updates:

**Option A:** Auto-approve during development (see Part 3)

**Option B:** Use a fixed port
```bash
flutter run -d chrome --web-port 8080
```

Then add `http://localhost:8080` to config once.

---

## Part 3: Device Pairing Automation

### Issue: "pairing required" Error

Each Flutter web session generates fresh Ed25519 keys, requiring re-pairing every time.

```
❌ Connect error: pairing required
```

### Why This Happens

1. ClawReach generates Ed25519 keypair on first run
2. Keys are saved to `SharedPreferences` (localStorage on web)
3. **BUT**: Clearing browser cache or changing ports = new keys = new pairing request

### Solution: Auto-Approve LAN Pairings

**Step 1:** Create auto-approval script

Already exists: `~/clawd/scripts/approve-device-pairing.sh --auto`

**Step 2:** Run manually during development

```bash
# Check for pending requests
~/clawd/scripts/approve-device-pairing.sh --list

# Auto-approve all LAN requests
~/clawd/scripts/approve-device-pairing.sh --auto

# Restart gateway to apply
openclaw gateway restart
```

**Step 3:** Add to heartbeat for automatic approval

Edit `~/clawd/HEARTBEAT.md`:

```markdown
## Device Pairing (check every heartbeat — do NOT rotate)
- Auto-approve LAN pairing requests: `~/clawd/scripts/approve-device-pairing.sh --auto`
- If any approved, notify Andre on Signal that a device was paired
- Note: Gateway restart needed after approval for it to take effect
```

This runs every hour automatically.

---

## Part 4: PWA Enhancements (Optional)

Make ClawReach installable as a Progressive Web App for better persistence.

### Files to Create/Modify

**1. Create `web/manifest.json`**

```json
{
  "name": "ClawReach",
  "short_name": "ClawReach",
  "description": "Connect your devices to OpenClaw Gateway",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#1a1a1a",
  "theme_color": "#00bcd4",
  "orientation": "any",
  "icons": [
    {
      "src": "/icons/Icon-192.png",
      "sizes": "192x192",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icons/Icon-512.png",
      "sizes": "512x512",
      "type": "image/png",
      "purpose": "any maskable"
    }
  ]
}
```

**2. Update `web/index.html`**

Add PWA meta tags:
```html
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="theme-color" content="#00bcd4">
  <link rel="manifest" href="manifest.json">
</head>
```

Add service worker registration:
```html
<body>
  <script>
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('flutter_service_worker.js')
          .then(reg => console.log('✅ Service Worker registered'))
          .catch(err => console.warn('⚠️ Service Worker failed:', err));
      });
    }
  </script>
  <script src="flutter_bootstrap.js" async></script>
</body>
```

### Benefits

- ✅ Installable as desktop/mobile app
- ✅ Keys persist in localStorage
- ✅ Auto-reconnect on app open
- ✅ Offline-capable (with service worker)

---

## Complete Setup Checklist

### Prerequisites

- [ ] OpenClaw Gateway running on LAN
- [ ] Flutter SDK installed (`flutter doctor`)
- [ ] ClawReach project cloned

### Flutter Code Changes

- [ ] Add `kIsWeb` checks to all platform-dependent code
- [ ] Wrap file I/O in `!kIsWeb` conditions
- [ ] Add SharedPreferences fallbacks for web
- [ ] Create PWA manifest and update index.html

### Gateway Configuration

- [ ] Get Flutter dev server port from browser
- [ ] Add `http://localhost:PORT` to `gateway.controlUi.allowedOrigins`
- [ ] Restart gateway: `openclaw gateway restart`

### Device Pairing

- [ ] Run `flutter run -d chrome`
- [ ] Wait for "pairing required" error
- [ ] Approve: `~/clawd/scripts/approve-device-pairing.sh --auto`
- [ ] Restart gateway again
- [ ] Connection should succeed ✅

### Verify Connection

Look for these logs in ClawReach console:

```
🔌 WebSocket connected to ws://192.168.1.171:18789/ws/node
✅ Connected via local URL
🔐 Got challenge nonce: ...
🔐 Sent connect request
📨 Received: res
✅ Paired and authenticated  // <-- Success!
```

---

## Troubleshooting

### Error: "origin not allowed"

**Symptom:**
```
❌ Connect error: origin not allowed
```

**Fix:**
1. Check Chrome address bar for actual port
2. Add that exact port to `allowedOrigins`
3. Restart gateway

**Note:** The `*` wildcard doesn't work for localhost. You need explicit ports.

---

### Error: "pairing required" (persists after approval)

**Symptom:**
```
❌ Connect error: pairing required
```

**Fix:**
1. Verify approval: `~/clawd/scripts/approve-device-pairing.sh --list`
2. **Restart gateway** (this is critical - approvals don't apply without restart)
3. Try connecting again

---

### Error: "MissingPluginException"

**Symptom:**
```
MissingPluginException(No implementation found for method 
getApplicationCacheDirectory on channel plugins.flutter.io/path_provider)
```

**Fix:**
Add `kIsWeb` check before calling the method:

```dart
if (kIsWeb) {
  // Use web alternative
} else {
  // Use platform API
}
```

---

### Keys Lost After Browser Refresh

**Symptom:** Keys persist within a session but lost on page reload.

**Fix:**
1. Verify `SharedPreferences` is being used correctly
2. Check browser storage: DevTools → Application → Local Storage
3. Look for `ed25519_seed` key in localStorage

**Expected behavior:** Keys should persist across page reloads but NOT across:
- Browser cache clear
- Incognito/private mode
- Different ports (each port = separate origin = separate localStorage)

---

## Development Workflow

### Daily Development

1. **Start Flutter dev server**
   ```bash
   cd ~/Development/clawreach
   flutter run -d chrome
   ```

2. **Note the port** (e.g., `http://localhost:40071/`)

3. **If origin error appears:**
   ```bash
   # Add port to gateway config
   openclaw gateway config.patch << EOF
   {
     "gateway": {
       "controlUi": {
         "allowedOrigins": ["http://localhost:40071"]
       }
     }
   }
   EOF
   
   openclaw gateway restart
   ```

4. **If pairing error appears:**
   ```bash
   # Auto-approve and restart
   ~/clawd/scripts/approve-device-pairing.sh --auto
   openclaw gateway restart
   ```

5. **Connection should succeed!**

### Hot Reload

Once connected, Flutter hot reload works normally:
- Press `r` to hot reload
- Press `R` to hot restart
- WebSocket stays connected through reloads ✅

---

## Production Considerations

### Persistent Storage

Web storage is **ephemeral** by default. For production:

1. **Request persistent storage** (prevents browser eviction)
   ```dart
   if (kIsWeb) {
     await navigator.storage.persist();
   }
   ```

2. **Use IndexedDB for large data** (see `WEB_PERSISTENCE_TODO.md`)

3. **Sync to gateway** - store tracks on server, pull on other devices

### Origin Allowlist

In production, replace localhost origins with your actual domain:

```json
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": [
        "https://clawreach.yourdomain.com"
      ]
    }
  }
}
```

Remove development localhost entries.

### Security

- **HTTPS required** for production (WebSockets over TLS)
- **Token-based auth** already working (gateway.auth.token)
- **Device pairing** ensures only approved devices connect
- **Origin validation** prevents unauthorized web apps

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                      Flutter Web App                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  localhost:PORT (random port each run)               │  │
│  │  - Ed25519 keys in localStorage                      │  │
│  │  - Gateway config in SharedPreferences               │  │
│  │  - Auto-reconnect on page load                       │  │
│  └────────────────┬─────────────────────────────────────┘  │
└───────────────────┼─────────────────────────────────────────┘
                    │
                    │ WebSocket (ws://192.168.1.171:18789/ws/node)
                    │ 1. Connect
                    │ 2. Challenge (nonce)
                    │ 3. Sign with Ed25519
                    │ 4. Check pairing
                    ▼
┌─────────────────────────────────────────────────────────────┐
│              OpenClaw Gateway (Local Mode)                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Port: 18789                                          │  │
│  │  - Origin validation (allowedOrigins)                │  │
│  │  - Device pairing (paired devices list)              │  │
│  │  - Auto-approve via heartbeat script                 │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## Files Changed Summary

```
ClawReach Flutter Project:
├── lib/
│   ├── models/
│   │   └── hike_track.dart              [MODIFIED] Added copyWith()
│   ├── services/
│   │   ├── cached_tile_provider.dart    [MODIFIED] Web compatibility
│   │   ├── hike_service.dart            [MODIFIED] Web storage + kIsWeb
│   │   └── crypto_service.dart          [OK] Already uses SharedPreferences
│   └── screens/
│       └── home_screen.dart             [OK] Auto-loads config
├── web/
│   ├── manifest.json                    [CREATED] PWA manifest
│   └── index.html                       [MODIFIED] PWA meta tags + SW
└── WEB_CONNECTION_GUIDE.md              [CREATED] This file

OpenClaw Gateway Config:
└── ~/.openclaw/openclaw.json
    └── gateway.controlUi.allowedOrigins [MODIFIED] Added localhost ports

OpenClaw Scripts:
└── ~/clawd/scripts/
    └── approve-device-pairing.sh        [EXISTING] Used with --auto flag
```

---

## Success Metrics

After following this guide, you should have:

- ✅ **0 Flutter analysis errors** (or only minor warnings)
- ✅ **Web app loads without crashes**
- ✅ **WebSocket connects successfully**
- ✅ **Device pairing completes**
- ✅ **Keys persist across page reloads**
- ✅ **Auto-reconnect works**
- ✅ **Chat messages send/receive**
- ✅ **GPS tracking functional** (browser geolocation)
- ✅ **Map displays** (network tiles)

---

## Next Steps

See `WEB_PERSISTENCE_TODO.md` for:
- IndexedDB implementation for hike history
- Browser downloads for GPX export
- Offline map tile caching

---

## Credits

**Date:** February 6, 2026  
**Author:** Fred 🦊 (AI Assistant)  
**Project:** ClawReach Flutter App  
**Gateway:** OpenClaw v2026.2.3  

---

## Quick Start Command Summary

```bash
# 1. Run Flutter web
cd ~/Development/clawreach
flutter run -d chrome

# 2. Note the port from browser address bar (e.g., 40071)

# 3. Add origin to gateway
openclaw gateway config.patch << EOF
{
  "gateway": {
    "controlUi": {
      "allowedOrigins": ["http://localhost:40071"]
    }
  }
}
EOF

# 4. Restart gateway
openclaw gateway restart

# 5. Wait for pairing error, then approve
~/clawd/scripts/approve-device-pairing.sh --auto

# 6. Restart gateway again
openclaw gateway restart

# 7. Connected! ✅
```

---

**End of Guide**
