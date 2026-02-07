# Push Notification Improvements

## Overview

Enhanced push notifications in ClawReach to provide timely alerts when the app is backgrounded, including canvas updates, new messages, and web platform support via service workers.

## Features Implemented

### 1. Canvas Update Notifications

**Problem:** Canvas updates (canvas.present, canvas.a2ui.push) arrive silently when app is backgrounded

**Solution:** Automatic notifications when canvas commands arrive while app is in background

**Implementation:**
- `CanvasService` now has `_notificationService` reference
- `_handlePresent()` notifies: "Canvas Ready - Fred opened a canvas for you"
- `_handleA2uiPushJsonl()` notifies: "Canvas Update - Fred updated the canvas"
- Only triggers when `_isBackgrounded == true`

**User Experience:**
```
1. User backgrounds ClawReach app
2. Gateway sends canvas.present with Oura dashboard
3. User receives notification: "Canvas Ready"
4. User taps notification → app opens to canvas
```

### 2. Message Notifications When Backgrounded

**Problem:** New messages arrive silently when app is not visible

**Solution:** Push notification for completed messages when backgrounded

**Implementation:**
- `ChatService` now has `_notificationService` reference
- `_handleChatEvent()` case 'final' notifies when message completes
- Preview truncated to 150 characters
- Suppresses NO_REPLY/HEARTBEAT_OK (not real messages)

**User Experience:**
```
1. User backgrounds app
2. Fred sends: "Your Oura sleep score is 85/100 today..."
3. User receives notification: "Fred 🦊 - Your Oura sleep score is 85/100 today..."
4. User taps notification → app opens to chat
```

### 3. Web Platform Service Worker

**Problem:** Web platform had no push notification support

**Solution:** Custom service worker with notification handling

**Implementation:**
- `web/sw.js` - Full-featured service worker
- `web/index.html` - Service worker registration with permission request
- Caching strategy: cache-first with network fallback
- Push notification support (ready for VAPID keys)

**Features:**
- ✅ Offline caching of app shell
- ✅ Push notification handling
- ✅ Notification click opens/focuses app
- ✅ Background sync placeholder (future)
- ✅ Periodic sync placeholder (future)

**User Experience (Web):**
```
1. User opens ClawReach in browser
2. Permission prompt: "ClawReach wants to show notifications"
3. User grants permission
4. Service worker registers and subscribes to push
5. Messages/canvas updates trigger browser notifications
```

## Code Changes

### Files Modified

1. **`lib/services/notification_service.dart`**
   - Added `_isBackgrounded` flag
   - Added `setBackgrounded(bool)` method
   - Added `notifyMessage(senderName, preview)` method
   - Added `notifyCanvas Update(title, description)` method
   - New channels: `clawreach_messages` and `clawreach_canvas`

2. **`lib/services/canvas_service.dart`**
   - Added `_notificationService` reference
   - Added `setNotificationService()` method
   - Added `_notifyCanvasUpdate()` helper
   - Updated `_handlePresent()` to notify on canvas.present
   - Updated `_handleA2uiPushJsonl()` to notify on A2UI updates

3. **`lib/services/chat_service.dart`**
   - Added `_notificationService` reference
   - Added `setNotificationService()` method
   - Added `_notifyMessage()` helper
   - Updated `_handleChatEvent()` case 'final' to notify

4. **`lib/main.dart`**
   - Wired notification service to chat and canvas services
   - `chat.setNotificationService(notifications)`
   - `canvasService.setNotificationService(notifications)`

5. **`lib/screens/home_screen.dart`**
   - Added `NotificationService` import
   - Updated `didChangeAppLifecycleState()`
   - Calls `notifications.setBackgrounded(true/false)` on lifecycle changes

6. **`web/sw.js`** ✨ NEW
   - Service worker with offline caching
   - Push notification handling
   - Notification click handling
   - Background/periodic sync placeholders

7. **`web/index.html`**
   - Updated service worker registration
   - Requests notification permission
   - Subscribes to push (when available)

## Notification Channels

### Android Channels

| Channel ID | Name | Importance | Use Case |
|------------|------|------------|----------|
| `clawreach_notifications` | ClawReach | High | Gateway system.notify commands |
| `clawreach_messages` | Messages | High | New chat messages from Fred |
| `clawreach_canvas` | Canvas Updates | High | Canvas presents and A2UI pushes |

### Notification Priorities

- **Time Sensitive:** Max importance, max priority, sound + vibration
- **Active:** High importance, high priority, sound + vibration (default)
- **Passive:** Low importance, low priority, no sound/vibration

## Testing

### Test Message Notifications

1. **Build and run ClawReach:**
   ```bash
   cd ~/clawd/clawreach
   flutter run -d <device>
   ```

2. **Background the app:**
   - Press home button or switch to another app

3. **Send message from gateway:**
   ```
   (From another client or automated message)
   Fred sends: "Test notification message"
   ```

4. **Expected:**
   - Notification appears: "Fred 🦊 - Test notification message"
   - Tap notification → app opens to chat

### Test Canvas Notifications

1. **Background the app**

2. **Send canvas command:**
   ```
   canvas.present url="http://example.com/oura-dashboard"
   ```

3. **Expected:**
   - Notification: "Canvas Ready - Fred opened a canvas for you"
   - Tap notification → app opens with canvas visible

### Test Web Notifications

1. **Build for web:**
   ```bash
   flutter build web
   flutter run -d chrome --web-port=9000
   ```

2. **Grant permission when prompted**

3. **Check service worker:**
   ```javascript
   // In browser console:
   navigator.serviceWorker.ready.then(reg => {
     console.log('Service Worker:', reg);
     console.log('Notification permission:', Notification.permission);
   });
   ```

4. **Test notification:**
   ```javascript
   // In browser console:
   new Notification('Test', { body: 'Hello from ClawReach!' });
   ```

## Lifecycle Flow

### Backgrounding

```
1. User backgrounds app
   ↓
2. didChangeAppLifecycleState(AppLifecycleState.paused)
   ↓
3. notifications.setBackgrounded(true)
   ↓
4. _isBackgrounded = true
   ↓
5. New messages/canvas → notifications appear
```

### Foregrounding

```
1. User opens app (or taps notification)
   ↓
2. didChangeAppLifecycleState(AppLifecycleState.resumed)
   ↓
3. notifications.setBackgrounded(false)
   ↓
4. _isBackgrounded = false
   ↓
5. New messages/canvas → no notifications (user sees them in-app)
```

## Future Enhancements

### 1. Rich Notifications

```dart
// Show inline actions
androidDetails = AndroidNotificationDetails(
  ...,
  actions: [
    AndroidNotificationAction('reply', 'Reply'),
    AndroidNotificationAction('dismiss', 'Dismiss'),
  ],
);
```

### 2. Notification Grouping

```dart
// Group related notifications
androidDetails = AndroidNotificationDetails(
  ...,
  groupKey: 'messages',
  setAsGroupSummary: true,
);
```

### 3. VAPID Keys for Web Push

```javascript
// In production, use VAPID keys
const subscription = await reg.pushManager.subscribe({
  userVisibleOnly: true,
  applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
});
```

### 4. Custom Notification Sounds

```dart
androidDetails = AndroidNotificationDetails(
  ...,
  sound: RawResourceAndroidNotificationSound('notification_sound'),
);
```

### 5. Notification Images

```dart
// Show image in notification
androidDetails = AndroidNotificationDetails(
  ...,
  styleInformation: BigPictureStyleInformation(
    FilePathAndroidBitmap(imagePath),
  ),
);
```

## Troubleshooting

### Notifications Not Appearing

**Symptom:** No notifications when app is backgrounded

**Checks:**
1. Verify permission granted: `Permission.notification.isGranted`
2. Check app state: `_isBackgrounded == true`
3. Look for errors in logs: `flutter logs`
4. Verify channel importance: High or Max

**Fix:**
```dart
// Request permission explicitly
final status = await Permission.notification.request();
if (!status.isGranted) {
  print('Permission denied');
}
```

### Web Notifications Not Working

**Symptom:** Service worker registers but no notifications

**Checks:**
1. HTTPS required (or localhost)
2. Permission granted: `Notification.permission === 'granted'`
3. Service worker active: `navigator.serviceWorker.controller`
4. Check browser console for errors

**Fix:**
```javascript
// Debug in console
Notification.requestPermission().then(perm => {
  console.log('Permission:', perm);
  if (perm === 'granted') {
    new Notification('Test', {body: 'Working!'});
  }
});
```

### Service Worker Not Updating

**Symptom:** Old service worker code still running

**Fix:**
```javascript
// Force update
navigator.serviceWorker.getRegistrations().then(regs => {
  regs.forEach(reg => reg.unregister());
  location.reload();
});
```

## Security & Privacy

### Permissions

- Android: Notification permission requested on first launch
- Web: Permission requested after service worker registration
- Both: User can revoke permission at any time

### Data Handling

- Notifications only show preview text (no sensitive data in notification itself)
- Full message content only visible after unlocking and opening app
- Notification history cleared when app is cleared from recents

### Best Practices

1. **Don't spam:** Only notify for important, user-relevant events
2. **Respect quiet hours:** Consider time-of-day filtering
3. **Clear old notifications:** Remove notifications when content viewed
4. **Provide controls:** Let users customize notification preferences

## Conclusion

Push notifications now provide:
- ✅ Timely alerts for canvas updates
- ✅ Message notifications when backgrounded
- ✅ Web platform support via service workers
- ✅ Clean separation of concerns
- ✅ Extensible architecture for future features

Users stay informed even when ClawReach is not in the foreground, improving the overall experience and engagement with Fred.
