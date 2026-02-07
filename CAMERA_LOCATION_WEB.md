# Camera & Location Support (Web Platform)

This document describes camera and location support for ClawReach on the web platform using browser APIs.

## Overview

ClawReach now supports camera and location on web browsers using:
- **Camera**: `getUserMedia` API (MediaStream)
- **Location**: Geolocation API

Both features require HTTPS (or localhost) and user permission.

## Features

### Camera (getUserMedia)

**Capabilities:**
- ✅ Take photos from front/back camera
- ✅ Auto-detect available cameras
- ✅ Permission handling with helpful error messages
- ✅ Configurable quality and resolution
- ✅ Optional capture delay (for focus/exposure)
- ✅ JPEG and PNG output formats
- ✅ Base64 encoding for gateway transmission

**Browser Support:**
- Chrome/Edge: Full support
- Firefox: Full support
- Safari: iOS 14.3+, macOS 11+
- Mobile browsers: Requires HTTPS

**Limitations:**
- No flash control (not available in browser API)
- No manual focus control
- Camera selection limited to front/back on mobile

### Location (Geolocation API)

**Capabilities:**
- ✅ Get current GPS coordinates
- ✅ Accuracy control (coarse/balanced/precise)
- ✅ Cached location support (maxAge)
- ✅ Timeout configuration
- ✅ Altitude, speed, heading data
- ✅ Timestamp for location fix

**Browser Support:**
- All modern browsers (Chrome, Firefox, Safari, Edge)
- Requires HTTPS (or localhost)
- Mobile: GPS + WiFi positioning
- Desktop: WiFi/IP-based positioning

**Limitations:**
- Accuracy varies by device (mobile GPS > desktop WiFi)
- Desktop browsers typically only offer IP-based location (~km accuracy)
- No background location tracking (session-based only)

## Implementation

### Camera Service (Web)

**File:** `lib/services/camera_service_web.dart`

```dart
// Request camera and capture photo
final result = await cameraService.handleSnap(
  requestId: 'req_123',
  command: 'camera.snap',
  params: {
    'facing': 'back',      // 'front' or 'back'
    'maxWidth': 1920,      // Max width in pixels
    'quality': 85,         // JPEG quality 0-100
    'delayMs': 500,        // Optional delay before capture
    'format': 'jpg',       // 'jpg' or 'png'
  },
);

// Returns:
// {
//   'format': 'jpg',
//   'base64': '...',  // Base64 encoded image data
//   'width': 1920,
//   'height': 1080,
// }
```

**getUserMedia Constraints:**
```javascript
{
  video: {
    facingMode: 'environment',  // or 'user' for front
    width: { ideal: 1920 }
  }
}
```

**Error Handling:**
- `NotAllowedError` → "Camera permission denied"
- `NotFoundError` → "No camera found on this device"
- `NotReadableError` → "Camera already in use"

### Location Service (Web)

**File:** `lib/services/location_service_web.dart`

```dart
// Request location
final result = await locationService.handleLocationGet(
  requestId: 'req_123',
  command: 'location.get',
  params: {
    'desiredAccuracy': 'balanced',  // 'coarse', 'balanced', 'precise'
    'maxAgeMs': 30000,              // Accept cached location up to 30s old
    'timeoutMs': 10000,             // Timeout after 10s
  },
);

// Returns:
// {
//   'lat': 49.8844,
//   'lon': -119.4960,
//   'accuracyMeters': 15.0,
//   'altitudeMeters': 344.0,
//   'speedMps': 0.0,
//   'headingDegrees': 0.0,
//   'timestamp': '2026-02-07T07:45:30.000Z',
// }
```

**Geolocation Options:**
```javascript
{
  enableHighAccuracy: true,    // GPS vs WiFi (mobile)
  timeout: 10000,              // Max wait time
  maximumAge: 30000            // Cache duration
}
```

**Error Handling:**
- `PERMISSION_DENIED` → "Location permission denied"
- `POSITION_UNAVAILABLE` → "Location unavailable"
- `TIMEOUT` → "Location request timed out"

## Permission Handling

### Browser Permission Flow

**Camera:**
1. User triggers camera action (via gateway command)
2. Browser shows permission prompt: "Allow ClawReach to use your camera?"
3. User accepts → Photo captured
4. User denies → Error message shown

**Location:**
1. User triggers location action (via gateway command)
2. Browser shows permission prompt: "Allow ClawReach to access your location?"
3. User accepts → Location retrieved
4. User denies → Error message shown

**Permission Persistence:**
- Granted permissions are remembered per origin (domain)
- Users can revoke permissions in browser settings
- Localhost permissions are separate from deployed domain

### HTTPS Requirement

**Why HTTPS?**
- Modern browsers require HTTPS for sensitive APIs (camera, location)
- Exception: `localhost` and `127.0.0.1` work on HTTP
- Exception: LAN IPs (192.168.x.x) may work on HTTP in some browsers

**Development:**
- ✅ `localhost:9000` → HTTP works
- ✅ `127.0.0.1:9000` → HTTP works
- ⚠️ `192.168.1.171:9000` → HTTPS required (varies by browser)
- ❌ `example.com:9000` → HTTPS required

**Production:**
- Deploy with valid SSL certificate (Let's Encrypt, Cloudflare, etc.)
- Use Cloudflare Tunnel for secure remote access
- Self-signed certificates trigger browser warnings

## Testing

### Test Camera (Web)

1. **Start development server:**
   ```bash
   cd ~/clawd/clawreach
   flutter run -d chrome --web-port=9000
   ```

2. **Test camera via gateway:**
   ```bash
   # In OpenClaw gateway
   nodes invoke --node=<web-device-id> \
     --invoke-command=camera.snap \
     --invoke-params='{"facing":"back","quality":85}'
   ```

3. **Verify:**
   - Browser shows camera permission prompt
   - Grant permission
   - Photo captured and sent to gateway
   - Check browser console for logs

4. **Test error handling:**
   - Deny camera permission → Check error message
   - Cover camera → Check capture quality
   - Close camera tab during capture → Check cleanup

### Test Location (Web)

1. **Start development server:**
   ```bash
   cd ~/clawd/clawreach
   flutter run -d chrome --web-port=9000
   ```

2. **Test location via gateway:**
   ```bash
   # In OpenClaw gateway
   nodes invoke --node=<web-device-id> \
     --invoke-command=location.get \
     --invoke-params='{"desiredAccuracy":"balanced","timeoutMs":10000}'
   ```

3. **Verify:**
   - Browser shows location permission prompt
   - Grant permission
   - Location retrieved (lat/lon/accuracy)
   - Check browser console for coordinates

4. **Test error handling:**
   - Deny location permission → Check error message
   - Set low timeout (500ms) → Check timeout handling
   - Test on desktop vs mobile → Compare accuracy

### Test Image Picker (Web)

Image picker already works on web via file input!

```dart
final image = await ImagePicker().pickImage(source: ImageSource.gallery);
// On web: Opens file picker dialog
// User selects image → File uploaded to app
```

**No special implementation needed** - the `image_picker` package handles web automatically.

## Browser Compatibility

### Camera Support

| Browser | Desktop | Mobile | Notes |
|---------|---------|--------|-------|
| Chrome | ✅ | ✅ | Full support |
| Firefox | ✅ | ✅ | Full support |
| Safari | ✅ (macOS 11+) | ✅ (iOS 14.3+) | Requires user gesture |
| Edge | ✅ | ✅ | Full support |

### Location Support

| Browser | Desktop | Mobile | Accuracy |
|---------|---------|--------|----------|
| Chrome | ✅ | ✅ | WiFi/GPS |
| Firefox | ✅ | ✅ | WiFi/GPS |
| Safari | ✅ | ✅ | WiFi/GPS |
| Edge | ✅ | ✅ | WiFi/GPS |

**Desktop Accuracy:**
- WiFi/IP-based: 50m - 5km radius
- No GPS hardware → Lower precision

**Mobile Accuracy:**
- GPS enabled: 5-50m radius
- WiFi only: 50-500m radius
- `enableHighAccuracy: true` uses GPS (higher battery drain)

## Security & Privacy

### Permission Prompts

**Browser shows:**
- "Allow ClawReach to use your camera?"
- "Allow ClawReach to access your location?"

**User can:**
- Grant permission (remembered for session or forever)
- Deny permission (app receives error)
- Revoke later in browser settings

### Data Handling

**Camera:**
- Photos captured in-memory only
- Base64 encoded and sent to gateway
- No photos saved to disk (unless gateway saves them)
- Video element cleaned up after capture

**Location:**
- Coordinates retrieved on-demand
- No background tracking
- No location history stored
- Only shared with gateway when requested

### Best Practices

1. **Request permissions only when needed**
   - Don't request camera/location on app startup
   - Request when user takes action (via gateway command)

2. **Provide context to users**
   - Error messages explain why permission needed
   - Clear feedback when permission denied

3. **Handle permission denial gracefully**
   - Show helpful error messages
   - Don't retry automatically (annoying)
   - Let user re-trigger action if they change mind

4. **Use HTTPS in production**
   - Required for camera/location APIs
   - Protects user privacy
   - Prevents man-in-the-middle attacks

## Troubleshooting

### Camera Issues

**"Camera permission denied"**
- User denied browser permission
- Check browser settings → Site permissions → Camera
- Remove site, try again (triggers fresh prompt)

**"No camera found"**
- Device has no camera (desktop)
- Camera blocked by OS settings (Windows/macOS privacy)
- Check system settings → Privacy → Camera

**"Camera already in use"**
- Another app/tab using camera
- Close other camera apps
- Restart browser if stuck

**Camera not working on LAN IP**
- HTTPS required for non-localhost
- Use localhost:9000 for development
- Use Cloudflare Tunnel for production

### Location Issues

**"Location permission denied"**
- User denied browser permission
- Check browser settings → Site permissions → Location
- Remove site, try again

**"Location unavailable"**
- GPS disabled (mobile)
- Poor GPS signal (indoors)
- WiFi disabled (desktop)
- Check system location settings

**Low accuracy on desktop**
- Desktop browsers use WiFi/IP location
- Accuracy typically 50m-5km
- This is normal for desktop
- Mobile with GPS gives 5-50m accuracy

**Timeout errors**
- Increase `timeoutMs` parameter
- Location fix taking too long (poor signal)
- Try `maxAgeMs` to accept cached location

### General Web Issues

**HTTPS errors**
- Camera/location require HTTPS (except localhost)
- Use `localhost` for development
- Deploy with SSL for production
- Self-signed certs trigger warnings

**Permission prompts not showing**
- User previously denied permission
- Check browser settings → Site permissions
- Remove site to reset permissions
- Try incognito mode for fresh start

**Browser console errors**
- Check DevTools console (F12) for details
- Look for `getUserMedia` or `geolocation` errors
- Check network tab for failed requests

## Future Enhancements

### Camera
- [ ] Video recording support (MediaRecorder API)
- [ ] Multiple photo capture (burst mode)
- [ ] Camera preview in UI before capture
- [ ] Flash control (if API becomes available)
- [ ] QR code scanning from camera stream

### Location
- [ ] Watch position (continuous tracking)
- [ ] Background location (requires service worker)
- [ ] Location history/trail
- [ ] Geofencing (proximity alerts)
- [ ] Distance/speed calculations

### Permissions
- [ ] Pre-request permissions with explanation UI
- [ ] Settings screen to manage permissions
- [ ] Permission status indicators
- [ ] Graceful degradation when denied

## Related Documentation

- [PERFORMANCE_OPTIMIZATIONS.md](PERFORMANCE_OPTIMIZATIONS.md) - Virtual scrolling, lazy loading
- [OFFLINE_SUPPORT.md](OFFLINE_SUPPORT.md) - Message caching and queueing
- [CANVAS_POSTMESSAGE_BRIDGE.md](CANVAS_POSTMESSAGE_BRIDGE.md) - Canvas integration
- [NOTIFICATION_IMPROVEMENTS.md](NOTIFICATION_IMPROVEMENTS.md) - Push notifications

## References

- [MDN: getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
- [MDN: Geolocation API](https://developer.mozilla.org/en-US/docs/Web/API/Geolocation_API)
- [Flutter image_picker](https://pub.dev/packages/image_picker)
- [Can I Use: getUserMedia](https://caniuse.com/stream)
- [Can I Use: Geolocation](https://caniuse.com/geolocation)
