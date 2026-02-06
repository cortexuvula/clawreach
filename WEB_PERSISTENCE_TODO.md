# Web Persistence Roadmap

## Current Status (2026-02-06)

✅ **Working:**
- Ed25519 keys persisted in localStorage (SharedPreferences)
- Gateway config auto-loads on app start
- Auto-reconnect to gateway
- Active track saved to SharedPreferences (session-only)

❌ **Not Persistent on Web:**
- Historical hike tracks (lost on page reload)
- GPX exports (file system not available)

---

## Phase 1: IndexedDB for Hike History

### Goal
Store completed hike tracks in browser's IndexedDB so they persist across sessions and can be reviewed later.

### Implementation Plan

1. **Add `idb_shim` package**
   ```yaml
   # pubspec.yaml
   dependencies:
     idb_shim: ^2.4.1+1
   ```

2. **Create `WebHikeStorage` class**
   ```dart
   // lib/services/web_hike_storage.dart
   import 'package:idb_shim/idb_browser.dart';
   
   class WebHikeStorage {
     static const _dbName = 'clawreach_hikes';
     static const _storeName = 'tracks';
     Database? _db;
     
     Future<void> init() async {
       final factory = getIdbFactory()!;
       _db = await factory.open(_dbName, version: 1,
         onUpgradeNeeded: (event) {
           final db = event.database;
           db.createObjectStore(_storeName, keyPath: 'id');
         },
       );
     }
     
     Future<void> saveTrack(HikeTrack track) async {
       final txn = _db!.transaction(_storeName, idbModeReadWrite);
       final store = txn.objectStore(_storeName);
       await store.put(jsonDecode(track.toJsonString()));
       await txn.completed;
     }
     
     Future<List<HikeTrack>> listTracks() async {
       final txn = _db!.transaction(_storeName, idbModeReadOnly);
       final store = txn.objectStore(_storeName);
       final records = await store.getAll();
       return records.map((r) => 
         HikeTrack.fromJsonString(jsonEncode(r))
       ).toList();
     }
   }
   ```

3. **Integrate into `HikeService`**
   - Modify `listTracks()` to use `WebHikeStorage` on web
   - Modify `_saveTrack()` to persist to IndexedDB on web
   - Keep file-based storage for mobile/desktop

### Storage Limits
- IndexedDB has generous limits (~50MB minimum, often GBs)
- Each track with 1000 points ≈ 50-100KB
- Can store 500-1000 tracks easily

---

## Phase 2: Browser GPX Downloads

### Goal
Allow users to export GPX files on web via browser download API.

### Implementation Plan

1. **Add `universal_html` package** (works on web and mobile)
   ```yaml
   dependencies:
     universal_html: ^2.2.4
   ```

2. **Create `WebFileDownload` helper**
   ```dart
   // lib/utils/web_file_download.dart
   import 'dart:convert';
   import 'package:universal_html/html.dart' as html;
   
   class WebFileDownload {
     static void downloadGpx(String filename, String gpxContent) {
       final bytes = utf8.encode(gpxContent);
       final blob = html.Blob([bytes], 'application/gpx+xml');
       final url = html.Url.createObjectUrlFromBlob(blob);
       
       final anchor = html.AnchorElement(href: url)
         ..setAttribute('download', filename)
         ..click();
       
       html.Url.revokeObjectUrl(url);
     }
   }
   ```

3. **Update `HikeService.exportGpx()`**
   ```dart
   Future<String?> exportGpx(HikeTrack track) async {
     if (kIsWeb) {
       try {
         final gpxContent = track.toGpx();
         final filename = '${track.name.replaceAll(' ', '_')}.gpx';
         WebFileDownload.downloadGpx(filename, gpxContent);
         return filename; // Success indicator
       } catch (e) {
         debugPrint('❌ Web GPX download failed: $e');
         return null;
       }
     }
     
     // Mobile/desktop: existing file-based logic
     // ...
   }
   ```

### User Experience
- User taps "Export GPX"
- Browser shows download prompt
- File saved to Downloads folder
- Works on desktop and mobile browsers

---

## Phase 3: Advanced Features (Optional)

### 3.1 Offline Map Tiles (Heavy)
- Cache map tiles in IndexedDB for offline use
- Requires ~100MB+ storage
- Consider user opt-in

### 3.2 Share API Integration
```dart
// For mobile web browsers
if (navigator.share && kIsWeb) {
  final gpxFile = File([gpxBytes], filename, { type: 'application/gpx+xml' });
  await navigator.share({ files: [gpxFile] });
}
```

### 3.3 Cloud Backup Option
- Sync hikes to gateway via node.event
- Gateway stores in database
- Pull on other devices

---

## Implementation Priority

1. **Phase 1** (IndexedDB) — High priority
   - Solves the biggest pain point (losing history)
   - ~2-3 hours of work
   
2. **Phase 2** (GPX downloads) — Medium priority
   - Nice-to-have for data export
   - ~1 hour of work
   
3. **Phase 3** (Advanced) — Low priority
   - Can wait until core features stabilize

---

## Testing Checklist

### IndexedDB
- [ ] Save track and reload page → track still visible
- [ ] Save 10+ tracks → all load correctly
- [ ] Clear browser data → tracks gone (expected)
- [ ] Works in Chrome, Firefox, Safari

### GPX Downloads
- [ ] Export GPX on web → file downloads
- [ ] Open downloaded GPX in Google Earth → displays correctly
- [ ] Try on mobile browser → download works

---

## Notes

- **Storage quotas**: Web apps can request persistent storage to avoid eviction
- **Privacy**: IndexedDB data is origin-scoped (secure)
- **Fallback**: If IndexedDB fails, gracefully fall back to session-only storage

---

**Target completion:** TBD (when ready for production web deployment)
