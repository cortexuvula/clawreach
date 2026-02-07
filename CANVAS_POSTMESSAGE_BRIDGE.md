# Canvas postMessage Bridge Implementation

## Overview

The Canvas postMessage Bridge enables bidirectional communication between ClawReach (Flutter web) and canvas HTML pages displayed in iframes, solving cross-origin security restrictions.

## Problem Solved

**Before (Cross-Origin Limitations):**
- ❌ `canvas.eval` - Can't execute JS in iframe
- ❌ `canvas.snapshot` - Can't read iframe DOM
- ❌ No user interaction feedback
- ❌ No event notifications from canvas

**After (postMessage Bridge):**
- ✅ `canvas.eval` - Execute JS via postMessage
- ✅ `canvas.snapshot` - Capture canvas via postMessage
- ✅ User actions flow to gateway
- ✅ Canvas events notify app
- ✅ App can send data/commands to canvas

## Architecture

```
┌─────────────────┐                      ┌──────────────────┐
│  ClawReach App  │◄────postMessage─────►│  Canvas (iframe) │
│  (Flutter Web)  │                      │   (HTML/JS)      │
└─────────────────┘                      └──────────────────┘
        │                                         │
        │                                         │
        ▼                                         ▼
  CanvasService                           openclawCanvas API
  CanvasWebBridge                         (JavaScript Helper)
```

## Message Protocol

### App → Canvas Messages

```javascript
{
  "source": "openclaw-app",
  "type": "eval" | "snapshot" | "data" | "control",
  "requestId": "req_123...",  // For commands expecting response
  "params": { ... }
}
```

### Canvas → App Messages

```javascript
{
  "source": "openclaw-canvas",
  "type": "ready" | "response" | "action" | "event" | "navigation",
  "requestId": "req_123...",  // Echo from command
  "result": ...,              // Response data
  "error": "...",             // Error message if failed
  "data": { ... }
}
```

## Implementation Files

### Flutter/Dart Side

1. **`lib/widgets/canvas_web_view.dart`**
   - Creates iframe with postMessage listener
   - Forwards messages to `CanvasService`
   - Sends messages to iframe

2. **`lib/services/canvas_service_web.dart`**
   - `CanvasWebBridge` class for web-specific operations
   - Request/response tracking with timeouts
   - `eval()` and `snapshot()` implementations

3. **`lib/services/canvas_service.dart`**
   - Handles incoming canvas messages
   - Routes user actions to gateway
   - Manages web view state registration

4. **`lib/widgets/canvas_overlay.dart`**
   - Registers web view with `CanvasService`
   - Passes `onMessage` callback to `CanvasWebView`

### JavaScript Side

1. **`web/openclaw-canvas-bridge.js`**
   - Canvas helper library
   - Handles postMessage protocol
   - Provides clean API for canvas developers

2. **`web/example-canvas.html`**
   - Example interactive canvas
   - Demonstrates all features
   - Template for new canvases

## Usage

### In Canvas HTML Files

Include the bridge script:

```html
<!DOCTYPE html>
<html>
<head>
  <title>My Canvas</title>
</head>
<body>
  <h1>Interactive Canvas</h1>
  <button onclick="handleClick()">Click Me</button>
  <canvas id="openclaw-canvas" width="400" height="300"></canvas>

  <script src="openclaw-canvas-bridge.js"></script>
  <script>
    function handleClick() {
      // Send action to app → gateway
      openclawCanvas.sendAction('button-clicked', {
        timestamp: Date.now()
      });
    }

    // Listen for data from app
    openclawCanvas.onCommand('data', (data) => {
      console.log('Received:', data.key, data.value);
    });

    // Canvas auto-sends ready on load
  </script>
</body>
</html>
```

### Canvas API Methods

#### Send Messages

```javascript
// Notify app that canvas is ready (auto-called on load)
openclawCanvas.ready();

// Send user action (button click, form submit, etc.)
openclawCanvas.sendAction('action-name', { data });

// Send event (completion, error, progress)
openclawCanvas.sendEvent('event-name', { data });

// Request navigation
openclawCanvas.navigate('https://example.com');

// Send response to app command
openclawCanvas.sendResponse(requestId, result, error);
```

#### Receive Messages

```javascript
// Handle custom commands
openclawCanvas.onCommand('my-command', (params, requestId) => {
  // Do something
  openclawCanvas.sendResponse(requestId, { success: true });
});

// Listen for data updates
openclawCanvas.onCommand('data', ({ key, value }) => {
  updateUI(key, value);
});

// Listen for control commands
openclawCanvas.onCommand('control', ({ action, params }) => {
  if (action === 'play') startPlayback();
  if (action === 'pause') pausePlayback();
});

// Alternative: DOM events
document.addEventListener('openclaw-data', (e) => {
  console.log(e.detail.key, e.detail.value);
});

document.addEventListener('openclaw-control', (e) => {
  console.log(e.detail.action, e.detail.params);
});
```

### From Flutter/Gateway

#### Execute JavaScript

```dart
// Gateway sends canvas.eval command
final result = await canvasService.eval("2 + 2");
print(result); // "4"
```

#### Take Snapshot

```dart
// Gateway sends canvas.snapshot command
final snapshot = await canvasService.snapshot(format: 'png', quality: 0.9);
final base64 = snapshot['base64'];
```

#### Send Data to Canvas

```dart
// Send data update to canvas
CanvasWebBridge.sendData('temperature', 72.5);

// Canvas receives via data handler
```

#### Send Control Commands

```dart
// Send control command
CanvasWebBridge.sendControl('play', {'speed': 1.5});

// Canvas receives via control handler
```

## Message Flow Examples

### Example 1: Button Click → Gateway

```
1. User clicks button in canvas HTML
2. Canvas JS: openclawCanvas.sendAction('play')
3. iframe → postMessage → ClawReach app
4. CanvasService.handleCanvasMessage()
5. NodeConnection.sendNodeEvent('canvas.action', {action: 'play'})
6. Gateway receives action, can respond
```

### Example 2: Gateway Eval → Canvas

```
1. Gateway sends canvas.eval command
2. CanvasService._handleEval()
3. CanvasWebBridge.eval(js)
4. App → postMessage → iframe
5. Canvas JS: openclawCanvas._handleEval()
6. eval(js) executes
7. Canvas → postMessage → app (response)
8. CanvasWebBridge.handleResponse()
9. Gateway receives result
```

### Example 3: Canvas Snapshot

```
1. Gateway sends canvas.snapshot
2. CanvasService._handleSnapshot()
3. CanvasWebBridge.snapshot()
4. App → postMessage → iframe
5. Canvas JS: openclawCanvas._handleSnapshot()
6. canvas.toDataURL() captures image
7. Canvas → postMessage → app (base64)
8. Gateway receives image data
```

## Testing

### Test Canvas Bridge

1. **Build ClawReach for web:**
   ```bash
   cd ~/clawd/clawreach
   flutter run -d chrome --web-port=9000
   ```

2. **Show example canvas:**
   ```
   In ClawReach chat:
   "show example canvas at http://localhost:9000/example-canvas.html"
   ```

3. **Test interactions:**
   - Click buttons → should see actions in console
   - Submit form → should send action to gateway
   - Click "Draw Random Shapes" → canvas fills with shapes
   - From gateway: `canvas.snapshot` → should capture drawn shapes

4. **Test eval:**
   ```
   From gateway:
   canvas.eval "document.title"
   → Should return "Example Interactive Canvas"
   ```

5. **Test control commands:**
   ```dart
   CanvasWebBridge.sendControl('clear-canvas', {});
   → Canvas should clear
   ```

## Limitations

### Security

- postMessage uses `'*'` origin for simplicity
- Consider restricting origin in production:
  ```javascript
  window.parent.postMessage(json, 'https://your-gateway.com');
  ```

### Performance

- Each message is serialized/deserialized JSON
- Large data transfers may be slow
- Consider data URLs for binary data

### Browser Support

- Requires modern browser with postMessage
- Works in Chrome, Firefox, Safari, Edge
- No IE11 support

## Future Enhancements

1. **Typed Message Protocol**
   - TypeScript definitions
   - Message validation

2. **Streaming Data**
   - Large file transfers
   - Progressive updates

3. **Canvas Lifecycle**
   - beforeunload notifications
   - Error recovery

4. **Developer Tools**
   - Message logging UI
   - Debug mode
   - Performance metrics

## Troubleshooting

### Messages Not Received

**Symptom:** Canvas sends message but app doesn't respond

**Fix:**
1. Check browser console for errors
2. Verify `source: 'openclaw-canvas'` in messages
3. Ensure `openclawCanvas.ready()` was called

### Eval/Snapshot Timeout

**Symptom:** `TimeoutException` after 5 seconds

**Fix:**
1. Verify iframe loaded successfully
2. Check `openclaw-canvas-bridge.js` is included
3. Look for JavaScript errors in canvas

### postMessage Blocked

**Symptom:** CORS or security errors

**Fix:**
1. Ensure iframe `src` uses same protocol (http/https)
2. Check browser console for CSP violations
3. Verify iframe `allow` attributes

## Example Use Cases

### 1. Interactive Dashboard

```html
<!-- Oura health dashboard -->
<script>
  function updateStats(data) {
    document.getElementById('sleep-score').textContent = data.sleep;
    document.getElementById('readiness').textContent = data.readiness;
  }

  openclawCanvas.onCommand('data', ({ key, value }) => {
    if (key === 'oura-stats') updateStats(value);
  });
</script>
```

### 2. Audio Player

```html
<script>
  const audio = new Audio();

  openclawCanvas.onCommand('control', ({ action, params }) => {
    switch (action) {
      case 'play':
        audio.play();
        break;
      case 'pause':
        audio.pause();
        break;
    }
  });

  audio.addEventListener('ended', () => {
    openclawCanvas.sendEvent('playback-complete');
  });
</script>
```

### 3. Form with Gateway Submit

```html
<script>
  function handleFormSubmit(e) {
    e.preventDefault();
    const formData = new FormData(e.target);
    const data = Object.fromEntries(formData);

    openclawCanvas.sendAction('form-submit', data);
  }
</script>
```

## Conclusion

The postMessage bridge unlocks full interactivity for web canvases, enabling:
- ✅ User interaction feedback
- ✅ Bidirectional data flow
- ✅ canvas.eval and canvas.snapshot on web
- ✅ Event-driven architecture
- ✅ Clean separation of concerns

Canvas developers can now build rich, interactive experiences that integrate seamlessly with the OpenClaw ecosystem.
