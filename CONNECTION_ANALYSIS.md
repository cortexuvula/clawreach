# ClawReach Connection Analysis & Improvements

## Current Architecture

### Two Independent WebSocket Connections

1. **GatewayService** (`lib/services/gateway_service.dart`)
   - Connects to `/ws/operator` (webchat mode)
   - Role: `operator`
   - Used for: Chat messages, commands
   - **Status**: ✅ Working

2. **NodeConnectionService** (`lib/services/node_connection_service.dart`)
   - Connects to `/ws/node` (node mode)
   - Role: `node`
   - Used for: Canvas, camera, location, notifications
   - **Status**: ❌ Stuck in pairing loop

### Current Connection Flow

```
1. User enters settings → Save
2. home_screen.dart: _connectSequential(config)
3. ├─> GatewayService.connect()  [operator role]
4. │   └─> Succeeds → connected ✅
5. └─> NodeConnectionService.connect()  [node role]
    └─> Fails "pairing required" ❌
    └─> Enters pairing pending state
    └─> Retries every 5s (60 attempts = 5 min)
    └─> Gives up after 5 min
```

---

## Issues Identified

### 1. **Dual-Role Approval Gap** 🔴
- **Problem**: Device gets approved as `operator` first, then tries to connect as `node`
- **Gateway behavior**: Creates NEW pairing request for node role
- **ClawReach behavior**: Waits for approval, retries connect every 5s
- **Issue**: User must manually approve TWICE (once for operator, once for node)

### 2. **No Visual Feedback** 🟡
- **Problem**: User doesn't know node connection is waiting for approval
- **Current**: Connection badge shows "connected" (operator works)
- **Reality**: Canvas won't work until node connection approved

### 3. **Reconnect Complexity** 🟡
- **Problem**: Two independent reconnect timers with different backoff strategies
- **Race conditions**: Operator and node can both try to reconnect simultaneously
- **Resource waste**: Double the WebSocket connections

### 4. **Pairing Request Spam** 🟡
- **Problem**: Every connect attempt creates a new pairing request
- **Gateway behavior**: Pending requests accumulate in `devices/pending.json`
- **Result**: Multiple identical pending requests for same device

### 5. **No Auto-Recovery After Approval** 🟡
- **Problem**: After manual approval, gateway must restart to pick up changes
- **ClawReach behavior**: Keeps retrying old connection (not aware of approval)
- **Workflow**: Approve → Restart gateway → Wait for ClawReach retry

### 6. **Hard-Coded Pairing Timeout** 🟡
- **Current**: 60 retries × 5s = 5 minutes max
- **Issue**: If approval happens at minute 4:59, next retry is at 5:00 → gives up
- **Better**: Never give up if operator connection is healthy

---

## Proposed Solutions

### Solution A: Unified Connection Manager (Recommended)

**Create a `ConnectionManager` that coordinates both connections:**

```dart
class ConnectionManager extends ChangeNotifier {
  final GatewayService _gateway;
  final NodeConnectionService _node;
  
  ConnectionState _state = ConnectionState.disconnected;
  
  Future<void> connect(GatewayConfig config) async {
    // 1. Connect operator first
    await _gateway.connect(config);
    
    // 2. Wait for operator to be fully connected
    await _waitForOperatorConnected();
    
    // 3. Connect node (may trigger pairing)
    await _node.connect(config);
    
    // 4. Monitor both connections
    _startHealthMonitoring();
  }
  
  void _startHealthMonitoring() {
    // Periodic ping to detect dead connections
    Timer.periodic(Duration(seconds: 30), (_) {
      if (_gateway.isConnected) _gateway.ping();
      if (_node.isConnected) _node.ping();
    });
  }
}
```

**Benefits:**
- ✅ Sequential connection (operator before node)
- ✅ Coordinated reconnects
- ✅ Single source of truth for connection state
- ✅ Health monitoring built-in

---

### Solution B: Smart Pairing Auto-Retry

**Improve node connection pairing logic:**

```dart
void _enterPairingPendingState() {
  _pairingPending = true;
  _pairingRetryCount = 0;
  notifyListeners();
  
  // Retry connect every 10s instead of 5s (less spam)
  _pairingRetryTimer = Timer.periodic(Duration(seconds: 10), (_) {
    // NO MAX RETRIES - keep trying as long as operator is connected
    if (_gateway.isConnected && !_connected) {
      debugPrint('🔄 [Node] Retrying pairing...');
      connect(_config!);
    } else if (!_gateway.isConnected) {
      // Operator disconnected - pause node retries
      _pairingRetryTimer?.cancel();
    }
  });
}
```

**Benefits:**
- ✅ Never gives up while operator connected
- ✅ Automatically succeeds after gateway restart
- ✅ Pauses retries if operator disconnects
- ✅ Less aggressive (10s vs 5s)

---

### Solution C: Visual Pairing State

**Add UI feedback for pairing pending:**

```dart
// In connection_badge.dart
Widget build(BuildContext context) {
  final gateway = context.watch<GatewayService>();
  final node = context.watch<NodeConnectionService>();
  
  if (gateway.isConnected && node.isPairingPending) {
    return Badge(
      icon: Icons.pending,
      color: Colors.orange,
      tooltip: 'Waiting for device approval (node)',
    );
  }
  // ... rest of logic
}
```

**Benefits:**
- ✅ User knows pairing is pending
- ✅ Can take action (check gateway UI, approve manually)
- ✅ Clear visual distinction

---

### Solution D: Auto-Approve via LAN Policy

**Add auto-approval for trusted LAN connections:**

**Gateway config change:**
```json
{
  "pairing": {
    "policy": "lan-auto",  // Auto-approve devices from LAN
    "trustedSubnets": ["192.168.1.0/24"]
  }
}
```

**Benefits:**
- ✅ Zero-touch pairing for home network
- ✅ Secure (limited to LAN)
- ✅ Works for both operator and node roles

**Note**: This would require OpenClaw gateway changes, not just ClawReach.

---

### Solution E: Single WebSocket with Role Upgrade

**Refactor to use ONE connection with multiple roles:**

Instead of two separate WebSockets:
```
ws://gateway:18789/ws/operator  [role: operator]
ws://gateway:18789/ws/node      [role: node]
```

Use one connection that requests both roles:
```
ws://gateway:18789/ws/dual      [roles: operator, node]
```

**Connect request:**
```json
{
  "type": "req",
  "method": "connect",
  "params": {
    "requestedRoles": ["operator", "node"],
    "capabilities": ["chat", "canvas", "camera"]
  }
}
```

**Benefits:**
- ✅ Half the connections
- ✅ Single pairing approval
- ✅ Simpler state management
- ✅ Coordinated reconnects

**Note**: This requires OpenClaw protocol changes.

---

## Immediate Fixes (No Protocol Changes Required)

### Fix 1: Improve Node Connection Retry

**File**: `lib/services/node_connection_service.dart`

```dart
void _enterPairingPendingState() {
  _pairingPending = true;
  _pairingRetryCount = 0;
  notifyListeners();
  
  // Cancel existing timer
  _pairingRetryTimer?.cancel();
  
  // Retry every 10s, NO max retries
  _pairingRetryTimer = Timer.periodic(Duration(seconds: 10), (timer) {
    if (!_connected && _config != null) {
      _pairingRetryCount++;
      debugPrint('🔄 [Node] Pairing retry #$_pairingRetryCount');
      connect(_config!);
    }
  });
}
```

### Fix 2: Add Connection Health Check

**File**: `lib/services/gateway_service.dart`

```dart
void startHeartbeat() {
  Timer.periodic(Duration(seconds: 30), (timer) {
    if (isConnected) {
      // Send ping to keep connection alive
      send({
        'type': 'ping',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    }
  });
}
```

### Fix 3: Better State Synchronization

**File**: `lib/screens/home_screen.dart`

```dart
Future<void> _connectSequential(GatewayConfig config) async {
  final gateway = context.read<GatewayService>();
  final nodeConn = context.read<NodeConnectionService>();

  // 1. Connect operator
  await gateway.connect(config);
  
  // 2. Wait up to 10s for operator connection
  for (int i = 0; i < 20; i++) {
    if (gateway.isConnected) break;
    await Future.delayed(Duration(milliseconds: 500));
  }
  
  // 3. Only start node if operator succeeded
  if (gateway.isConnected) {
    // Wait 2s for operator to fully settle
    await Future.delayed(Duration(seconds: 2));
    
    // Start node connection
    nodeConn.connect(config);
  } else {
    debugPrint('⚠️ Operator connection failed, skipping node connection');
  }
}
```

### Fix 4: Connection Badge Shows Both States

**File**: `lib/widgets/connection_badge.dart`

```dart
case msg.GatewayConnectionState.connected:
  final nodeConn = context.watch<NodeConnectionService>();
  if (nodeConn.isPairingPending) {
    return const Icon(Icons.pending, color: Colors.orange, size: 14);
  }
  return const Icon(Icons.check_circle, color: Colors.green, size: 14);
```

---

## Testing Plan

### Test Case 1: Fresh Install
1. Install ClawReach (no saved keys)
2. Enter gateway settings
3. Observe:
   - ✅ Operator connects successfully
   - ⏳ Node shows "pairing pending"
   - ⏳ Badge shows orange pending icon

### Test Case 2: Manual Approval
1. From Test Case 1, approve node pairing in gateway
2. Restart gateway
3. Observe:
   - ✅ Node connection succeeds within 10s
   - ✅ Badge turns green
   - ✅ Canvas commands work

### Test Case 3: Network Interruption
1. Connected state (operator + node)
2. Disable Wi-Fi for 30s
3. Re-enable Wi-Fi
4. Observe:
   - ✅ Both connections auto-reconnect
   - ✅ No duplicate pairing requests
   - ✅ Resume within 30s

### Test Case 4: Gateway Restart
1. Connected state
2. Restart gateway
3. Observe:
   - ✅ ClawReach detects disconnect
   - ✅ Auto-reconnects within 10s
   - ✅ No new pairing requests

---

## Recommended Implementation Order

1. **Fix 1** (Node retry) — Immediate, no breaking changes
2. **Fix 4** (Badge) — Quick UI improvement
3. **Fix 3** (Sequential connect) — Better coordination
4. **Fix 2** (Heartbeat) — Keep-alive for long sessions
5. **Solution B** (Smart retry) — Enhanced version of Fix 1
6. **Solution C** (Visual state) — Full UI feedback
7. **Solution A** (Connection Manager) — Major refactor, best long-term

---

## Metrics to Track

- **Connection Success Rate**: % of connect attempts that succeed
- **Time to Connect**: Median time from settings save to full connect
- **Reconnect Count**: How often connections drop
- **Pairing Approval Time**: Time from pairing request to approval
- **Connection Uptime**: % of time both connections are healthy

---

## Conclusion

The current connection architecture works but has rough edges around dual-role approval. The immediate fixes (#1-4) will make it **much more robust** without requiring protocol changes.

Long-term, consider **Solution A (Connection Manager)** or **Solution E (Single WebSocket)** for the cleanest architecture.

**Priority**: Implement Fixes 1-4 TODAY for immediate stability improvement. 🚀
