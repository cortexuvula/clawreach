import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import '../services/canvas_service.dart';
import '../services/chat_service.dart';
import '../services/gateway_service.dart';
import '../services/hike_service.dart';
import '../services/node_connection_service.dart';
import '../widgets/canvas_overlay.dart';
import '../widgets/chat_bubble.dart';
import 'hike_screen.dart';
import 'settings_screen.dart';

/// Main home screen with chat interface.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GatewayConfig? _config;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  int _prevMessageCount = 0;

  // Media state
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isRecording = false;
  DateTime? _recordingStart;
  Timer? _recordingTimer;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _loadConfigAndAutoConnect();
    _focusNode.addListener(_onFocusChange);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _scrollToBottom(delay: 300);
    }
  }

  void _scrollToBottom({int delay = 100}) {
    Future.delayed(Duration(milliseconds: delay), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadConfigAndAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('gateway_config');
    if (configStr != null) {
      final config = GatewayConfig.fromJson(
        jsonDecode(configStr) as Map<String, dynamic>,
      );
      setState(() => _config = config);

      final gateway = context.read<GatewayService>();
      final nodeConn = context.read<NodeConnectionService>();
      if (!gateway.isConnected) {
        gateway.connect(config);
      }
      if (!nodeConn.isConnected) {
        nodeConn.connect(config);
      }
    }
  }

  void _onConfigSaved(GatewayConfig config) {
    setState(() => _config = config);
    final gateway = context.read<GatewayService>();
    final nodeConn = context.read<NodeConnectionService>();
    gateway.connect(config);
    nodeConn.connect(config);
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final chat = context.read<ChatService>();
    chat.sendMessage(text);
    _textController.clear();
    _scrollToBottom();
  }

  // ── Voice recording ──

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopAndSendRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    // Check permission
    if (!await _recorder.hasPermission()) {
      await Permission.microphone.request();
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required')),
          );
        }
        return;
      }
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
      _recordingStart = DateTime.now();
    });

    // Tick the UI every second to update the timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isRecording) {
        setState(() {}); // Trigger rebuild to update elapsed time
      }
    });
  }

  Future<void> _stopAndSendRecording() async {
    final path = await _recorder.stop();
    final duration = _recordingStart != null
        ? DateTime.now().difference(_recordingStart!)
        : Duration.zero;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    setState(() {
      _isRecording = false;
      _recordingStart = null;
    });

    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    final chat = context.read<ChatService>();

    // Try to transcribe via the server
    final transcript = await _transcribeAudio(file);

    if (transcript != null && transcript.isNotEmpty) {
      // Send as text with a voice note prefix
      debugPrint('🎤 Transcript: $transcript');
      chat.sendMessage('🎤 $transcript');
    } else {
      // Fallback: send as audio attachment
      debugPrint('🎤 Transcription failed, sending as audio file');
      await chat.sendFile(
        file: file,
        type: 'audio',
        mimeType: 'audio/mp4',
        duration: duration,
      );
    }
    _scrollToBottom();
  }

  /// Transcribe audio file via the local transcription server.
  Future<String?> _transcribeAudio(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      // Try gateway's local IP first, then fallback
      final config = _config;
      final gatewayHost = config != null
          ? Uri.parse(config.url).host
          : '192.168.1.171';
      final url = 'http://$gatewayHost:8014/transcribe';

      debugPrint('🎤 Transcribing via $url (${(bytes.length / 1024).toStringAsFixed(0)} KB)...');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'audio': b64,
          'mimeType': 'audio/mp4',
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = (data['text'] as String?)?.trim() ?? '';
        final elapsed = data['elapsed'] ?? 0;
        debugPrint('🎤 Transcribed in ${elapsed}s: ${text.substring(0, text.length.clamp(0, 60))}');
        return text;
      } else {
        debugPrint('🎤 Transcription server error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('🎤 Transcription failed: $e');
      return null;
    }
  }

  // ── Image picking ──

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Select one or more photos'),
              onTap: () {
                Navigator.pop(ctx);
                _pickMultipleImages();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Pick a single image from camera.
  Future<void> _pickImage(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Camera permission required')),
            );
          }
          return;
        }
      }

      debugPrint('📷 Picking image from ${source.name}...');
      final xfile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (xfile == null) {
        debugPrint('📷 Image picker cancelled');
        return;
      }

      debugPrint('📷 Got image: ${xfile.path} (mime: ${xfile.mimeType})');
      final file = File(xfile.path);
      final chat = context.read<ChatService>();
      await chat.sendFile(
        file: file,
        type: 'image',
        mimeType: xfile.mimeType ?? 'image/jpeg',
      );
      _scrollToBottom();
    } catch (e, stack) {
      debugPrint('❌ Image picker error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  static const int _maxMultiPhotos = 10;

  /// Pick multiple images from gallery and send them sequentially.
  Future<void> _pickMultipleImages() async {
    try {
      debugPrint('📷 Opening multi-image picker...');
      final xfiles = await _imagePicker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
        limit: _maxMultiPhotos,
      );
      if (xfiles.isEmpty) {
        debugPrint('📷 Multi-image picker cancelled');
        return;
      }

      // Enforce limit (some Android versions ignore the limit param)
      final selected = xfiles.length > _maxMultiPhotos
          ? xfiles.sublist(0, _maxMultiPhotos)
          : xfiles;

      if (xfiles.length > _maxMultiPhotos && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Max $_maxMultiPhotos photos — first $_maxMultiPhotos selected')),
        );
      }

      debugPrint('📷 Selected ${selected.length} image(s)');
      final chat = context.read<ChatService>();

      // Wait for gateway connection before starting
      if (!chat.isReady) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Waiting for connection...')),
          );
        }
        final ready = await chat.waitForReady(timeout: const Duration(seconds: 10));
        if (!ready) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Not connected — photos not sent')),
            );
          }
          return;
        }
      }

      int sent = 0;
      int failed = 0;

      // Send each image silently (no per-photo caption)
      for (int i = 0; i < selected.length; i++) {
        if (!chat.isReady) {
          debugPrint('📷 Lost connection at image ${i + 1}, waiting...');
          final reconnected = await chat.waitForReady(timeout: const Duration(seconds: 10));
          if (!reconnected) {
            debugPrint('📷 Could not reconnect, skipping remaining ${selected.length - i} images');
            failed += selected.length - i;
            break;
          }
        }

        final xfile = selected[i];
        debugPrint('📷 Sending image ${i + 1}/${selected.length}: ${xfile.path}');
        final file = File(xfile.path);
        await chat.sendFile(
          file: file,
          type: 'image',
          mimeType: xfile.mimeType ?? 'image/jpeg',
        );
        sent++;

        // Pace sends to avoid flooding gateway
        if (i < selected.length - 1) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }

      // Send one summary message after all photos
      if (sent > 1) {
        final summary = failed > 0
            ? '📷 $sent photos sent, $failed failed'
            : '📷 $sent photos';
        chat.sendMessage(summary);
      }
      _scrollToBottom();

      if (mounted && failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$sent sent, $failed failed')),
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Multi-image picker error: $e\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick images: $e')),
        );
      }
    }
  }

  // ── UI helpers ──

  String _routeLabel(String? url) {
    if (url == null || url.isEmpty) return 'Connected';
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Connected';
    final host = uri.host;
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.')) {
      return 'Local';
    } else if (host.contains('.ts.net') || host.startsWith('100.')) {
      return 'Tailscale';
    }
    return 'Connected';
  }

  Widget _buildAppBarStatus(
      GatewayService gateway, ChatService chat, NodeConnectionService nodeConn) {
    final (color, label) = switch (gateway.state) {
      msg.GatewayConnectionState.disconnected => (Colors.grey, 'Offline'),
      msg.GatewayConnectionState.connecting => (Colors.orange, 'Connecting...'),
      msg.GatewayConnectionState.authenticating => (Colors.amber, 'Auth...'),
      msg.GatewayConnectionState.pairingPending => (Colors.blue, 'Pairing...'),
      msg.GatewayConnectionState.connected => (
          chat.isReady ? Colors.green : Colors.lime,
          chat.isReady ? _routeLabel(gateway.activeUrl) : 'Syncing...',
        ),
      msg.GatewayConnectionState.error => (Colors.red, 'Error'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: color == Colors.green
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w500)),
        if (nodeConn.isConnected) ...[
          const SizedBox(width: 8),
          Icon(Icons.sensors,
              size: 14, color: Colors.green.withValues(alpha: 0.8)),
        ],
      ],
    );
  }

  Widget _buildRecordingBanner() {
    final elapsed = _recordingStart != null
        ? DateTime.now().difference(_recordingStart!)
        : Duration.zero;
    final secs = elapsed.inSeconds;
    final timeStr = '${(secs ~/ 60).toString().padLeft(2, '0')}:${(secs % 60).toString().padLeft(2, '0')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.red.withValues(alpha: 0.15),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.5),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Recording $timeStr',
            style: TextStyle(
              color: Colors.red[300],
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () async {
              // Cancel recording without sending
              _recordingTimer?.cancel();
              _recordingTimer = null;
              await _recorder.stop();
              setState(() {
                _isRecording = false;
                _recordingStart = null;
              });
            },
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();
    final chat = context.watch<ChatService>();
    final nodeConn = context.watch<NodeConnectionService>();
    final canvas = context.watch<CanvasService>();

    // Auto-scroll when new messages arrive or streaming updates
    if (chat.messages.length != _prevMessageCount) {
      _prevMessageCount = chat.messages.length;
      _scrollToBottom();
    } else if (chat.isStreaming) {
      _scrollToBottom(delay: 50);
    }

    // Canvas overlay takes over the whole screen when visible
    if (canvas.isVisible) {
      return const CanvasOverlay();
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🦊 ', style: TextStyle(fontSize: 24)),
            const Text('Claw Reach'),
            const SizedBox(width: 12),
            _buildAppBarStatus(gateway, chat, nodeConn),
          ],
        ),
        actions: [
          Builder(builder: (ctx) {
            final hikeService = ctx.watch<HikeService>();
            return IconButton(
              icon: hikeService.isTracking
                  ? const Icon(Icons.directions_run, color: Colors.green)
                  : const Icon(Icons.directions_run),
              tooltip: 'Fitness Tracker',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HikeScreen()),
              ),
            );
          }),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  currentConfig: _config,
                  onSave: _onConfigSaved,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Pairing banner
          if (gateway.state == msg.GatewayConnectionState.pairingPending)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.blue.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Waiting for pairing approval',
                            style: TextStyle(
                                color: Colors.blue[300],
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('Ask the gateway admin to approve this device',
                            style: TextStyle(
                                color: Colors.blue[200], fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Error banner
          if (gateway.state == msg.GatewayConnectionState.error &&
              gateway.errorMessage != null)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red[300], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(gateway.errorMessage!,
                        style:
                            TextStyle(color: Colors.red[300], fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: _config != null
                        ? () => gateway.connect(_config!)
                        : null,
                    child:
                        const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Recording banner
          if (_isRecording) _buildRecordingBanner(),

          // Configure prompt
          if (_config == null)
            Expanded(
              child: Center(
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        currentConfig: _config,
                        onSave: _onConfigSaved,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('Configure Gateway'),
                ),
              ),
            )
          else ...[
            // Chat messages
            Expanded(
              child: chat.messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            gateway.state ==
                                    msg.GatewayConnectionState.pairingPending
                                ? '🔗'
                                : gateway.state ==
                                        msg.GatewayConnectionState.error
                                    ? '⚠️'
                                    : '🦊',
                            style: const TextStyle(fontSize: 48),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            chat.isReady
                                ? 'Say something!'
                                : gateway.state ==
                                        msg.GatewayConnectionState
                                            .pairingPending
                                    ? 'This device needs to be approved'
                                    : gateway.state ==
                                            msg.GatewayConnectionState
                                                .connecting
                                        ? 'Connecting to gateway...'
                                        : gateway.isConnected
                                            ? 'Syncing session...'
                                            : gateway.state ==
                                                    msg.GatewayConnectionState
                                                        .error
                                                ? gateway.errorMessage ??
                                                    'Connection failed'
                                                : 'Configure gateway to start',
                            style: const TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: chat.messages.length,
                      itemBuilder: (context, index) {
                        return ChatBubble(message: chat.messages[index]);
                      },
                    ),
            ),

            // Input bar
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context)
                        .dividerColor
                        .withValues(alpha: 0.2),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    // Camera/gallery button
                    IconButton(
                      onPressed: chat.isReady ? _showMediaPicker : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      tooltip: 'Send photo',
                      iconSize: 22,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                    ),

                    // Text field
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        enabled: chat.isReady && !_isRecording,
                        decoration: InputDecoration(
                          hintText: _isRecording
                              ? 'Recording...'
                              : chat.isReady
                                  ? 'Message Fred...'
                                  : 'Connecting...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        maxLines: 4,
                        minLines: 1,
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Send or Mic button (toggles based on text content)
                    if (_hasText || _isRecording)
                      // Send button (when text is present)
                      IconButton.filled(
                        onPressed: chat.isReady
                            ? (_isRecording
                                ? _toggleRecording
                                : _sendMessage)
                            : null,
                        icon: _isRecording
                            ? const Icon(Icons.stop, color: Colors.red)
                            : chat.isStreaming
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                      )
                    else
                      // Mic button (when text field is empty)
                      IconButton.filled(
                        onPressed:
                            chat.isReady ? _toggleRecording : null,
                        icon: const Icon(Icons.mic),
                        style: IconButton.styleFrom(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .secondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
