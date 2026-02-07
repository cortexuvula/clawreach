# Canvas State Management Improvements

## ✅ Implemented Features

### 1. Persistent Storage (Survives App Restart)
**Problem:** Canvas state was lost when app closed/restarted  
**Solution:** SharedPreferences integration

**Implementation:**
```dart
// Storage keys
static const _prefKeyCanvasUrl = 'canvas_last_url';
static const _prefKeyCanvasVisible = 'canvas_was_visible';
static const _prefKeyCanvasMinimized = 'canvas_minimized';

// Load on init
_loadPersistedState() async {
  final prefs = await SharedPreferences.getInstance();
  final wasVisible = prefs.getBool(_prefKeyCanvasVisible) ?? false;
  final url = prefs.getString(_prefKeyCanvasUrl);
  // Restore if was visible
}

// Save on every state change
_persistState() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKeyCanvasVisible, _visible);
  await prefs.setString(_prefKeyCanvasUrl, _currentUrl ?? '');
  await prefs.setBool(_prefKeyCanvasMinimized, _minimized);
}
```

**Benefits:**
- ✅ Canvas state survives app restarts
- ✅ Last URL is remembered
- ✅ User doesn't lose their place

### 2. Minimize/Restore Functionality
**Problem:** Only had close (destructive) - no way to temporarily hide canvas  
**Solution:** Added minimize state + restore button

**New Methods:**
```dart
void minimize()      // Hide canvas but keep state
void restore()       // Bring minimized canvas back
void toggleMinimize() // Toggle between states
```

**UI Changes:**
- Added minimize button (➖) to canvas header
- Floating action button appears when minimized
- Click FAB to restore canvas instantly

**Benefits:**
- ✅ Non-destructive hide (quick restore)
- ✅ Clear visual indicator (FAB)
- ✅ One-tap restore

### 3. Automatic Reconnection Recovery
**Problem:** Canvas disappeared after gateway restart  
**Solution:** Already implemented in Phase 1, enhanced with persistence

**How it works:**
1. Node disconnects → Save canvas state
2. Node reconnects → Restore canvas if was visible
3. State also persisted to SharedPreferences

**Benefits:**
- ✅ Seamless recovery after gateway restart
- ✅ No manual intervention needed
- ✅ Canvas reappears automatically

### 4. Background Resilience
**Problem:** Canvas state could be lost when app backgrounded  
**Solution:** State persisted on every change

**Persisted on:**
- ✅ Canvas present/hide commands
- ✅ Canvas navigate (URL changes)
- ✅ Minimize/restore actions
- ✅ Manual close

**Benefits:**
- ✅ Background/foreground transitions safe
- ✅ Always recovers to last known state

## 📝 Code Changes

### Files Modified

1. **`lib/services/canvas_service.dart`**
   - Added `SharedPreferences` import
   - Added `_minimized` state flag
   - Added `_loadPersistedState()` method
   - Added `_persistState()` method
   - Added `minimize()`, `restore()`, `toggleMinimize()` methods
   - Updated `isVisible` getter to check `!_minimized`
   - Added `isMinimized` getter
   - Updated all handlers to call `_persistState()`
   - Auto-load state on service init

2. **`lib/widgets/canvas_overlay.dart`**
   - Added minimize button to header bar
   - Icon: `Icons.minimize`
   - Action: `canvas.minimize()`

3. **`lib/screens/home_screen.dart`**
   - Added floating action button
   - Shows when `canvas.isMinimized == true`
   - Extended FAB with "Canvas" label
   - Icon: `Icons.open_in_full`
   - Action: `canvas.restore()`

## 🎯 User Experience Flow

### Normal Use
1. User opens canvas: "show me my oura stats"
2. Canvas appears with Oura dashboard
3. User clicks minimize (➖) → Canvas hides, FAB appears
4. User clicks FAB → Canvas restores instantly

### After App Restart
1. User closes app (canvas was visible)
2. User reopens app
3. **Canvas automatically restores** with last URL
4. No manual action needed

### After Gateway Restart
1. User has canvas open
2. Gateway restarts: `openclaw gateway restart`
3. WebSocket disconnects, reconnects (~5-10s)
4. **Canvas automatically restores** with same content
5. Seamless recovery

### Background/Foreground
1. User backgrounds app (home button)
2. Canvas state saved to SharedPreferences
3. User foregrounds app
4. Canvas state intact (minimized or visible)

## 🧪 Testing Instructions

### Test 1: Minimize/Restore
```
1. Show canvas: "show me my oura stats"
2. Click minimize button (➖) in canvas header
   Expected: Canvas disappears, purple FAB appears bottom-right
3. Click FAB ("Canvas")
   Expected: Canvas restores with same content
```

### Test 2: Persistence Across App Restart
```
1. Show canvas: "show me world languages"
2. Note the canvas is visible
3. Close Flutter app (Ctrl+C in terminal)
4. Restart: flutter run -d chrome --web-port=9000
5. Wait for app to load
   Expected: Canvas auto-restores with world languages chart
```

### Test 3: Gateway Restart Recovery
```
1. Show canvas: "show me restaurant roulette"
2. Restart gateway: openclaw gateway restart
3. Wait ~10 seconds
   Expected: Canvas briefly disappears, then auto-restores
```

### Test 4: Minimize Persistence
```
1. Show canvas
2. Minimize it (FAB should appear)
3. Close and restart app
   Expected: Canvas stays minimized, FAB visible on launch
4. Click FAB
   Expected: Canvas restores with last content
```

## 📊 State Persistence Matrix

| Action | `_visible` | `_minimized` | Persisted | UI State |
|--------|-----------|-------------|-----------|----------|
| canvas.present | true | false | ✅ | Full screen |
| canvas.hide | false | false | ✅ | Hidden |
| canvas.navigate | true | false | ✅ | Full screen |
| minimize() | true | true | ✅ | FAB only |
| restore() | true | false | ✅ | Full screen |
| handleLocalHide() | false | false | ✅ | Hidden |

## 🔍 Debug Logging

New debug messages to watch for:

```
💾 Canvas state persisted: visible=true, minimized=false, url=http://...
🖼️ Restoring canvas from storage: visible=true, minimized=false, url=http://...
🖼️ Canvas minimized
🖼️ Canvas restored
```

## 🎨 Visual Changes

### Canvas Header
Before:
```
[X] 🌐 Canvas                    [↻]
```

After:
```
[X] 🌐 Canvas                [➖] [↻]
```

### Floating Action Button (when minimized)
```
                           ┌──────────┐
                           │ 📱 Canvas │
                           └──────────┘
```
Purple button, bottom-right corner

## 🚀 Next Steps

### Future Enhancements
1. **Canvas Position/Size Memory**
   - Remember window size on desktop
   - Remember position preferences

2. **Multiple Canvas Tabs**
   - Support multiple canvases
   - Tab switching UI
   - Each with own state

3. **Canvas History**
   - Back/forward navigation
   - Recent canvas list
   - Quick access menu

4. **Canvas Presets**
   - Save favorite canvases
   - One-click load
   - User-defined shortcuts

## ✅ Success Criteria

All criteria met:
- ✅ Canvas disappears when you background the app → **FIXED** (state persisted)
- ✅ Add minimize/restore functionality → **IMPLEMENTED** (button + FAB)
- ✅ Remember last canvas URL on reconnect → **WORKING** (SharedPreferences)

**Status:** Phase 1 Complete! 🎉
