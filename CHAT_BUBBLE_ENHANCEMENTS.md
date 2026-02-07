# Chat Bubble Enhancements

## What's New

### 1. **Audio Playback** 🎵
- Full-featured audio player with:
  - ▶️ Play/Pause button
  - 📊 Animated waveform visualization (shows progress)
  - ⏱️ Real-time position tracking (e.g., "0:12 / 2:45")
  - 🎚️ Seekable slider for scrubbing through audio
  - 🔄 Auto-restart when replay from end
  - ⚡ Loading indicator during playback start

### 2. **File Attachments** 📎
- Display non-audio/image files with:
  - 📄 File type icons (PDF, ZIP, TXT, VIDEO, etc.)
  - 📏 File size display (auto-formatted: B, KB, MB)
  - 📂 Tap to open with system default app
  - 📥 Download icon indicator
  - 🎨 Clean card design with border

### 3. **Context Menu Updates**
- Long-press bubble shows options for:
  - Text: Copy, Select, Share
  - Images: Save, Share
  - Audio/Files: Share media

## Technical Details

### Dependencies Added
```yaml
audioplayers: ^6.1.0  # Cross-platform audio playback
url_launcher: ^6.3.1   # Open files with system apps
```

### Updated Files
1. **pubspec.yaml** - Added new dependencies
2. **lib/widgets/chat_bubble.dart** - Complete rewrite with:
   - `AudioPlayerWidget` - Stateful audio player
   - `FileAttachmentWidget` - File display/download
   - Enhanced context menu
3. **lib/models/chat_message.dart** - Added:
   - `fileSize` property to `ChatAttachment`
   - `isFile` getter

### Platform Support
- ✅ **Android/iOS**: Full support (file I/O, audio playback)
- ✅ **Web**: Audio from bytes, file download via browser
- ⚠️ **Linux/Desktop**: Requires system media codecs

## Usage Example

```dart
// Audio message
ChatMessage(
  id: '1',
  role: 'assistant',
  text: '🎤 Voice note',
  timestamp: DateTime.now(),
  attachments: [
    ChatAttachment(
      type: 'audio',
      mimeType: 'audio/mpeg',
      fileName: 'voice_note.mp3',
      filePath: '/path/to/audio.mp3',
      duration: Duration(minutes: 2, seconds: 45),
    ),
  ],
)

// File message
ChatMessage(
  id: '2',
  role: 'user',
  text: 'Here's the document',
  timestamp: DateTime.now(),
  attachments: [
    ChatAttachment(
      type: 'file',
      mimeType: 'application/pdf',
      fileName: 'report.pdf',
      filePath: '/path/to/report.pdf',
      fileSize: 1024 * 256, // 256 KB
    ),
  ],
)
```

## Testing

### Audio Playback
1. Send voice note attachment
2. Tap play button → audio should start
3. Waveform should animate showing progress
4. Drag slider → should seek to position
5. Tap pause → should pause playback
6. Play to end → should reset to beginning

### File Attachments
1. Send PDF/ZIP/document attachment
2. Should show file icon, name, and size
3. Tap file → should open with system default app
4. Long-press → context menu with "Share media"

## Known Limitations
- **Web**: File paths must use bytes source (no direct file I/O)
- **Waveform**: Static visualization (not true audio waveform analysis)
- **Simultaneous playback**: Multiple audio players can play at once (no auto-pause)

## Future Enhancements
- [ ] True waveform visualization from audio analysis
- [ ] Speed controls (0.5x, 1x, 1.5x, 2x)
- [ ] Auto-pause other players when starting new playback
- [ ] Audio caching for faster replay
- [ ] Download progress indicator for remote files
- [ ] File preview/thumbnail generation
