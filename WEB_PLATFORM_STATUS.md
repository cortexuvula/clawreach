# ClawReach Web Platform Status

## ✅ Working on Web

### Core Functionality
- ✅ **WebSocket connection** to OpenClaw gateway
- ✅ **Text chat** send/receive
- ✅ **Canvas display** and rendering
- ✅ **Connection status** indicators
- ✅ **Settings** persistence (SharedPreferences)

### Media Capture
- ✅ **Audio recording** (4.5s test successful)
  - Uses `AudioEncoder.opus` → `.webm` format
  - Records to blob URLs (not file paths)
  - Sample rate: 48kHz (auto-adjusted from 44.1kHz)
- ✅ **Audio transcription** (faster-whisper via blob upload)
  - Fetches blob data, uploads to transcription server
  - Server supports `audio/webm` format
  - CORS-enabled for cross-origin requests

### UI/UX
- ✅ **Chat bubbles** with text messages
- ✅ **Audio player widget** (plays from bytes/blob)
- ✅ **File attachment widget** (display only)
- ✅ **Connection badges** and status

## ⚠️ Limited on Web

### Audio Processing
- ✅ **Transcription**: ~~Not yet implemented~~ **IMPLEMENTED** (2026-02-06)
  - ~~Server-side transcription requires file upload (blob → multipart)~~
  - ✅ Now uploads blob data to faster-whisper server
  - ✅ Supports `audio/webm` format
  - ⚠️ On-device STT not available on web (server-only)

### File Operations
- ⚠️ **Audio attachment sending**: Disabled
  - `ChatService.sendFile()` expects `File` objects
  - Need to add blob/bytes upload support
- ⚠️ **File downloads**: Display only
  - Can't save to device filesystem from web
  - Browser handles downloads via blob URLs

### Storage
- ⚠️ **Hike tracking persistence**: Disabled
  - Can't save GPX/JSON files to persistent storage
  - Tracks lost on page refresh
  - **Workaround**: Runtime-only tracking in memory

## ❌ Not Supported on Web

### Platform-Specific
- ❌ **Camera capture**: No implementation
  - Would need `<input type="file" accept="image/*" capture="camera">`
- ❌ **Background services**: Not supported
  - No foreground task service
  - No persistent connections when tab inactive
- ❌ **System permissions**: Different model
  - Microphone: browser prompts automatically
  - Location: browser geolocation API (different from mobile)
- ❌ **Tile caching**: Disabled
  - No local filesystem for map tiles
  - Downloads tiles every time (slower, more bandwidth)

### Deep Linking
- ❌ **App links**: Not applicable
  - Web uses URL routing instead
- ❌ **QR scanner**: No implementation
  - Would need `html5-qrcode` or similar library

## 🔧 To-Do for Full Web Support

### High Priority
1. ~~**Audio transcription**~~ ✅ **DONE** (2026-02-06)
   - ~~Add blob → multipart/form-data upload to transcription server~~
   - ~~Or use Web Speech API (browser built-in STT)~~
   - ✅ Implemented blob fetch + base64 upload

2. **Audio attachment sending**:
   - Convert blob URLs to `Uint8List` for `ChatService.sendFile()`
   - Or add new `sendFileFromBlob()` method

3. **Image capture**:
   - Add `<input type="file">` fallback for photo picker
   - Handle blob → bytes conversion

### Medium Priority
4. **File downloads**:
   - Use `url_launcher` to trigger browser downloads
   - Or create blob URLs for user-initiated downloads

5. **Persistent storage**:
   - Use IndexedDB for hike tracks (via `idb_shim` package)
   - Store audio recordings in IndexedDB

### Low Priority
6. **QR code scanning**:
   - Integrate `html5-qrcode` package
   - Use device camera via `getUserMedia()`

7. **Offline support**:
   - Service worker for PWA functionality
   - Cache static assets
   - Queue messages when offline

## Architecture Notes

### File I/O Pattern
**Native**:
```dart
final dir = await getTemporaryDirectory();
final file = File('${dir.path}/recording.m4a');
await recorder.start(path: file.path);
final bytes = await file.readAsBytes();
```

**Web** (current workaround):
```dart
if (kIsWeb) {
  // Skip file operations
  debugPrint('Feature not available on web');
  return;
}
```

**Web** (better approach):
```dart
if (kIsWeb) {
  final bytes = await recorder.stop(); // Returns Uint8List
  await uploadBlob(bytes);
} else {
  final path = await recorder.stop(); // Returns file path
  final file = File(path);
  await uploadFile(file);
}
```

### Platform Detection
Always use `kIsWeb` from `package:flutter/foundation.dart`:
```dart
import 'package:flutter/foundation.dart' show kIsWeb;

if (kIsWeb) {
  // Web-specific code
} else {
  // Native-specific code
}
```

### Conditional Imports
For platform-specific implementations:
```dart
import 'service_stub.dart'
    if (dart.library.io) 'service_mobile.dart'
    if (dart.library.html) 'service_web.dart';
```

## Testing Checklist

### Web Testing
- [ ] Text chat send/receive
- [ ] Audio recording (check console for blob URL)
- [ ] Audio playback from assistant messages
- [ ] Image display in chat bubbles
- [ ] File attachment display (no download)
- [ ] Settings save/load
- [ ] Connection status updates
- [ ] Canvas rendering

### Cross-Platform Testing
- [ ] Feature parity between web and mobile
- [ ] Graceful degradation when features unavailable
- [ ] Clear user feedback for unsupported features
- [ ] No crashes from platform-specific code

## Known Issues

1. **Audio recording on web**:
   - ✅ Records successfully
   - ❌ Transcription not implemented
   - ❌ Can't send as attachment
   - **Workaround**: Shows snackbar notification

2. **Map tiles on web**:
   - ✅ Displays correctly
   - ❌ No caching (re-downloads every time)
   - **Impact**: Slower load times, more bandwidth

3. **Hike tracking on web**:
   - ✅ Tracks in memory during session
   - ❌ Not persisted between sessions
   - **Impact**: Lose track history on page refresh

## Performance Notes

### Web-Specific Optimizations
- Opus codec provides good compression (~64kbps)
- Blob URLs avoid filesystem overhead
- SharedPreferences faster than file I/O for small data

### Web-Specific Limitations
- No background execution when tab inactive
- Network requests more restricted (CORS)
- Memory constraints in browser sandbox
- No direct filesystem access

---

**Last Updated**: 2026-02-06
**Platform**: Web (Chrome/Flutter Web)
**Flutter Version**: 3.10.7
**Record Package**: 5.2.1 (with record_web 1.3.0)
