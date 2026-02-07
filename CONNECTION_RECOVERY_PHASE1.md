# Connection Recovery - Phase 1 Implementation

## ✅ Completed (Phase 1: Quick Wins)

### 1. Canvas State Persistence
**File:** `lib/services/canvas_service.dart`

**Changes:**
- Added `_wasVisibleBeforeDisconnect` and `_lastUrlBeforeDisconnect` fields
- Listen to NodeConnectionService state changes via `_onNodeConnectionChanged()`
- Save canvas state when node disconnects
- Automatically restore canvas URL + visibility when node reconnects

**Code:**
```dart
void _onNodeConnectionChanged() {
  final isConnected = _nodeConnection.isConnected;
  
  if (!isConnected) {
    // Save state when disconnecting
    _wasVisibleBeforeDisconnect = _visible;
    _lastUrlBeforeDisconnect = _currentUrl;
    debugPrint('🖼️ Canvas state saved: visible=$_wasVisibleBeforeDisconnect, url=$_lastUrlBeforeDisconnect');
  } else if (_wasVisibleBeforeDisconnect && _lastUrlBeforeDisconnect != null) {
    // Restore canvas after reconnection
    debugPrint('🖼️ Restoring canvas: $_lastUrlBeforeDisconnect');
    _currentUrl = _lastUrlBeforeDisconnect;
    _visible = true;
    _a2uiReady = false;
    notifyListeners();
  }
}
```

**Result:**
- Canvas will automatically reappear after gateway restart
- Same URL will be loaded
- User sees seamless recovery

### 2. Reconnection Visual Feedback
**Files:**
- `lib/services/gateway_service.dart` - Exposed `reconnectAttempts` getter
- `lib/widgets/connection_badge.dart` - Added `reconnectAttempts` parameter
- `lib/screens/home_screen.dart` - Updated status display

**Changes:**
- Connection badge now shows "Reconnecting (1)...", "Reconnecting (2)...", etc.
- Status bar in app header shows attempt count
- User knows system is actively trying to reconnect

**Code:**
```dart
final reconnecting = gateway.reconnectAttempts > 0;
final reconnectLabel = reconnecting ? ' (${gateway.reconnectAttempts})' : '';

final (color, label) = switch (gateway.state) {
  msg.GatewayConnectionState.disconnected => (
    Colors.grey, 
    reconnecting ? 'Reconnecting$reconnectLabel...' : 'Offline'
  ),
  // ...
}
```

**Result:**
- Clear visual feedback during reconnection
- User knows how many attempts have been made
- Reduces uncertainty during gateway restarts

## 📝 Testing Instructions

### Test 1: Canvas Persistence
1. Open ClawReach web at http://localhost:9000
2. Connect to gateway
3. Show canvas: "show me my oura stats"
4. Restart gateway: `openclaw gateway restart`
5. **Expected:** Canvas disappears briefly, then auto-restores with same content

**Debug logs to watch for:**
```
🖼️ Canvas state saved: visible=true, url=http://127.0.0.1:8888/oura-sleep-dashboard.html
🔌 WebSocket closed
🔄 Reconnecting in 5000ms (attempt 1)...
✅ Connected to gateway via ws://192.168.1.171:18789!
✅ [Node] Connected as node
🖼️ Restoring canvas: http://127.0.0.1:8888/oura-sleep-dashboard.html
```

### Test 2: Reconnection Feedback
1. Open ClawReach
2. Connect to gateway
3. Restart gateway: `openclaw gateway restart`
4. **Expected:** Status shows "Reconnecting (1)...", then "Reconnecting (2)..." if needed
5. **Expected:** After ~5-10s, shows "Connected" again

**Watch the header:**
- Should see: 🟠 "Reconnecting (1)..."
- Then: 🟢 "Connected • 📶 Local"

### Test 3: Long Reconnection
1. Open ClawReach
2. Connect to gateway
3. Stop gateway: `openclaw gateway stop`
4. **Expected:** Attempts count up: (1), (2), (3), (4), (5)
5. Restart gateway: `openclaw gateway start`
6. **Expected:** Reconnects on next attempt, counter resets

## 🔍 What to Watch For

### Success Indicators
✅ Canvas reappears after gateway restart  
✅ Reconnection counter visible in UI  
✅ Connection recovers within 10 seconds  
✅ No manual intervention needed  
✅ Debug logs show state save/restore  

### Potential Issues
⚠️ Canvas doesn't restore → Check `_onNodeConnectionChanged` is firing  
⚠️ Counter doesn't show → Check `reconnectAttempts` getter exposed  
⚠️ Slow reconnection → Check exponential backoff timing  
⚠️ Double canvas → Check state is cleared after restore  

## 📊 Next Steps (Phase 2)

Once Phase 1 is tested and validated:

1. **Test all scenarios** from CONNECTION_RECOVERY_PLAN.md
2. **Connection Health Monitoring** - Detect stale connections
3. **Reconnection Coordination** - Sequential operator → node reconnect
4. **Manual Reconnect Button** - Allow user to force reconnect
5. **Connection Diagnostics** - Show detailed connection info

## 🎯 Success Metrics

**Current Implementation Achieves:**
- ✅ Canvas persistence across gateway restart
- ✅ Visual feedback during reconnection
- ✅ Automatic recovery (no user action needed)

**Remaining Goals:**
- ⏳ Connection health monitoring (Phase 2)
- ⏳ Reconnection coordination (Phase 2)
- ⏳ Manual reconnect UI (Phase 2)
