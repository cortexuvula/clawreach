# Connection Recovery - Rock-Solid Reliability

## Current State Analysis

### ✅ What Works
- **Exponential backoff**: 5s → 10s → 20s → 40s → 60s (capped)
- **Zombie channel detection**: Prevents old handlers from interfering
- **Dual reconnection**: Both GatewayService and NodeConnectionService have independent reconnect logic
- **Background awareness**: Pauses reconnects when app is backgrounded (unless foreground service active)
- **Auto-reconnect flag**: Respects `autoReconnect` config setting

### ⚠️ Current Issues
1. **Canvas state lost on reconnect** - No mechanism to restore canvas URL/visibility
2. **No reconnection coordination** - Operator and node reconnect independently (could cause double pairing requests)
3. **No connection health monitoring** - Can't detect slow/degraded connections
4. **Limited visual feedback** - User doesn't see reconnection attempts clearly
5. **Pairing state unclear** - After gateway restart, pairing might be lost

## Test Scenarios

### Scenario 1: Gateway Restart (Clean)
**Steps:**
1. Connect ClawReach (operator + node)
2. Open canvas with content
3. Restart gateway: `openclaw gateway restart`
4. Wait for auto-reconnect

**Expected:**
- ✅ Both WebSockets reconnect within 5-10s
- ✅ Canvas state preserved (URL + visibility)
- ✅ Pairing still valid (no re-approval needed)
- ✅ UI shows "Reconnecting..." then "Connected"

**Current Reality:**
- ⚠️ Reconnects work but canvas disappears
- ❓ Pairing persistence unknown

### Scenario 2: Network Interruption
**Steps:**
1. Connect ClawReach
2. Disable WiFi for 10 seconds
3. Re-enable WiFi

**Expected:**
- ✅ Immediate reconnection attempt after network restored
- ✅ Exponential backoff if gateway unreachable
- ✅ UI shows network status

### Scenario 3: Gateway Crash (Unclean)
**Steps:**
1. Connect ClawReach
2. Kill gateway process: `kill -9 $(pidof openclaw)`
3. Restart gateway

**Expected:**
- ✅ WebSocket detects disconnect
- ✅ Reconnects when gateway comes back
- ✅ Pairing survives (paired.json still on disk)

### Scenario 4: Long-Running Connection
**Steps:**
1. Connect ClawReach
2. Leave connected for 24+ hours
3. Use periodically

**Expected:**
- ✅ No memory leaks
- ✅ No zombie connections
- ✅ Heartbeat/ping keeps connection alive

## Proposed Improvements

### 1. Canvas State Persistence (HIGH)
**Problem:** Canvas disappears on reconnect

**Solution:**
```dart
class CanvasService {
  String? _lastUrl;
  bool _wasVisible = false;
  
  void _onNodeReconnected() {
    if (_wasVisible && _lastUrl != null) {
      debugPrint('🖼️ Restoring canvas: $_lastUrl');
      _currentUrl = _lastUrl;
      _visible = true;
      notifyListeners();
    }
  }
}
```

**Implementation:**
- Save canvas URL + visibility when shown
- Listen to NodeConnectionService state changes
- Auto-restore on reconnection

### 2. Reconnection Coordination (MEDIUM)
**Problem:** Operator and node reconnect independently

**Solution:**
```dart
class ConnectionCoordinator {
  Future<void> reconnectAll(GatewayConfig config) async {
    // Connect operator first
    await gatewayService.connect(config);
    
    // Wait for operator to be fully connected
    await gatewayService.waitForState(GatewayConnectionState.connected, timeout: 10s);
    
    // Then connect node (avoids double pairing)
    await nodeConnectionService.connect(config);
  }
}
```

**Benefits:**
- Sequential connection avoids race conditions
- Clearer state transitions
- Single point of control

### 3. Connection Health Monitoring (MEDIUM)
**Problem:** Can't detect degraded connections

**Solution:**
```dart
class ConnectionHealthMonitor {
  Timer? _healthCheckTimer;
  DateTime? _lastMessageReceived;
  
  void startMonitoring() {
    _healthCheckTimer = Timer.periodic(Duration(seconds: 30), (_) {
      final timeSinceLastMessage = DateTime.now().difference(_lastMessageReceived);
      
      if (timeSinceLastMessage > Duration(minutes: 2)) {
        debugPrint('⚠️ Connection appears stale, forcing reconnect');
        _forceReconnect();
      }
    });
  }
}
```

**Features:**
- Periodic health checks (30s interval)
- Detect stale connections (no messages for 2+ min)
- Force reconnect if needed
- Log connection quality metrics

### 4. Visual Feedback (HIGH)
**Problem:** User doesn't see reconnection status

**Solution:**
```dart
// Add to ConnectionBadge widget
Widget build(BuildContext context) {
  return Consumer<GatewayService>(
    builder: (context, gateway, _) {
      if (gateway.state == GatewayConnectionState.connecting) {
        return AnimatedBadge(
          icon: Icons.sync,
          color: Colors.orange,
          label: 'Reconnecting... (${gateway.reconnectAttempt}/5)',
          animated: true, // Spinning icon
        );
      }
      // ... other states
    },
  );
}
```

**Features:**
- Show reconnection attempts count
- Animated icon during reconnect
- Distinct colors for each state
- Tap to see connection details

### 5. Pairing State Verification (LOW)
**Problem:** Unclear if pairing survives gateway restart

**Solution:**
```dart
// After successful reconnect, verify pairing
Future<void> _verifyPairing() async {
  try {
    // Send a test node command
    final result = await nodeConnection.ping(timeout: Duration(seconds: 5));
    
    if (!result.ok) {
      debugPrint('⚠️ Node pairing appears invalid');
      // Show pairing dialog
      _showPairingRequiredDialog();
    }
  } catch (e) {
    debugPrint('⚠️ Pairing verification failed: $e');
  }
}
```

## Implementation Plan

### Phase 1: Quick Wins (1-2 hours)
- [x] Review existing reconnection logic
- [ ] Add canvas state persistence
- [ ] Improve connection badge visual feedback
- [ ] Add reconnection attempt counter to UI

### Phase 2: Testing (1 hour)
- [ ] Test Scenario 1: Gateway restart
- [ ] Test Scenario 2: Network interruption
- [ ] Test Scenario 3: Gateway crash
- [ ] Document results

### Phase 3: Coordination (2-3 hours)
- [ ] Implement ConnectionCoordinator
- [ ] Sequential reconnection logic
- [ ] Add connection health monitoring
- [ ] Test all scenarios again

### Phase 4: Polish (1 hour)
- [ ] Better error messages
- [ ] Connection diagnostics screen
- [ ] Add manual reconnect button
- [ ] Documentation

## Success Metrics

✅ **Gateway restart**: Full recovery within 10 seconds  
✅ **Canvas persistence**: 100% state restoration  
✅ **No user intervention**: Fully automatic recovery  
✅ **Visual feedback**: Clear status at all times  
✅ **No double pairing**: Sequential connection prevents races  

## Testing Checklist

- [ ] Gateway restart while idle
- [ ] Gateway restart during canvas display
- [ ] Gateway restart during active conversation
- [ ] Network interruption (WiFi off/on)
- [ ] Gateway crash (kill -9)
- [ ] Long-running connection (24h+)
- [ ] Rapid gateway restarts (< 5s apart)
- [ ] Background/foreground transitions during reconnect
