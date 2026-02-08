import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import '../services/canvas_service.dart';
import '../services/capability_service.dart';
import '../services/chat_service.dart';
import '../services/connection_coordinator.dart';
import '../services/gateway_service.dart';
import '../services/hike_service.dart';
import '../services/deep_link_service.dart';
import '../services/node_connection_service.dart';
import '../services/notification_service.dart';
import '../widgets/canvas_overlay.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/offline_banner.dart';
import 'hike_screen.dart';
import 'settings_screen.dart';

/// Main home screen with chat interface.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  GatewayConfig? _config;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  int _prevMessageCount = 0;

  // Deep link service
  final DeepLinkService _deepLinkService = DeepLinkService();

  // Media state
  final AudioRecorder _recorder = AudioRecorder();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isRecording = false;
  DateTime? _recordingStart;
  Timer? _recordingTimer;
  bool _hasText = false;

  // Typing indicator debounce
  Timer? _typingDebounce;
  bool _sentTypingIndicator = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfigAndAutoConnect();
    _initDeepLinks();
    _focusNode.addListener(_onFocusChange);
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deepLinkService.dispose();
    _recordingTimer?.cancel();
    _typingDebounce?.cancel();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final gateway = context.read<GatewayService>();
    final nodeConn = context.read<NodeConnectionService>();
    final notifications = context.read<NotificationService>();

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        debugPrint('🔄 App lifecycle: BACKGROUNDED (${state.name})');
        // Notify notification service app is backgrounded
        notifications.setBackgrounded(true);
        
        // Pause connections when backgrounded (FCM handles offline notifications)
        debugPrint('💤 App backgrounded — pausing connections');
        gateway.setBackgrounded(true);
        nodeConn.setBackgrounded(true);
        break;
      case AppLifecycleState.resumed:
        debugPrint('🔄 App lifecycle: FOREGROUNDED (${state.name})');
        debugPrint('☀️ App foregrounded — resuming connections');
        
        // Notify notification service app is foregrounded
        notifications.setBackgrounded(false);
        
        gateway.setBackgrounded(false);
        nodeConn.setBackgrounded(false);
        
        // Force reconnect if disconnected (app may have been killed)
        if (!gateway.isConnected) {
          final config = gateway.activeConfig;
          if (config != null) {
            debugPrint('🔄 Gateway disconnected, reconnecting...');
            gateway.connect(config);
          }
        }
        
        if (!nodeConn.isConnected) {
          final config = nodeConn.activeConfig;
          if (config != null) {
            debugPrint('🔄 Node disconnected, reconnecting...');
            nodeConn.connect(config);
          }
        }
        
        // If neither is connected and we have config, do sequential reconnect
        if (!gateway.isConnected && !nodeConn.isConnected && _config != null) {
          _connectSequential(_config!);
        }
        break;
      default:
        break;
    }
  }

  void _onTextChanged() {
    final hasText = _textController.text.trim().isNotEmpty;
    
    // Send typing indicator on first keystroke (leading edge)
    if (hasText && !_sentTypingIndicator) {
      _sendTypingIndicator(true);
      _sentTypingIndicator = true;
    }
    
    // Debounce the "stopped typing" signal
    _typingDebounce?.cancel();
    if (hasText) {
      _typingDebounce = Timer(const Duration(milliseconds: 500), () {
        if (_sentTypingIndicator) {
          _sendTypingIndicator(false);
          _sentTypingIndicator = false;
        }
      });
    } else {
      // Clear immediately when text is deleted
      if (_sentTypingIndicator) {
        _sendTypingIndicator(false);
        _sentTypingIndicator = false;
      }
    }
    
    // UI state update
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  void _sendTypingIndicator(bool isTyping) {
    try {
      final gateway = context.read<GatewayService>();
      if (gateway.isConnected) {
        gateway.sendEvent({
          'type': 'typing',
          'isTyping': isTyping,
        });
        debugPrint('⌨️ Typing indicator: $isTyping');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to send typing indicator: $e');
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

  Future<void> _initDeepLinks() async {
    _deepLinkService.onConfigReceived = _onDeepLinkConfig;
    await _deepLinkService.init();
  }

  Future<void> _onDeepLinkConfig(GatewayConfig config) async {
    // Save config to SharedPreferences and auto-connect
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gateway_config', jsonEncode(config.toJson()));
    setState(() => _config = config);
    _connectSequential(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connected via link: ${config.url}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _loadConfigAndAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('gateway_config');
    debugPrint('🔧 Loading config from SharedPreferences...');
    debugPrint('🔧 Config found: ${configStr != null ? "YES (${configStr.length} chars)" : "NO"}');
    if (configStr != null) {
      final config = GatewayConfig.fromJson(
        jsonDecode(configStr) as Map<String, dynamic>,
      );
      debugPrint('🔧 Parsed config: ${config.url}');
      setState(() => _config = config);
      _connectSequential(config);
    } else {
      debugPrint('🔧 No saved config — user needs to enter settings');
    }
  }

  /// Connect operator first, then node — avoids double pairing requests.
  Future<void> _connectSequential(GatewayConfig config) async {
    final coordinator = context.read<ConnectionCoordinator>();
    
    // Use coordinator for proper sequencing
    await coordinator.connectAll(config);
    
    // Probe capabilities after operator connects
    if (mounted) {
      context.read<CapabilityService>().probe(config.url);
    }
    
  }

  void _onConfigSaved(GatewayConfig config) {
    setState(() => _config = config);
    _connectSequential(config);
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
      if (!kIsWeb) {
        await Permission.microphone.request();
      }
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission required')),
          );
        }
        return;
      }
    }

    // On web, record package handles storage internally (blob URLs)
    // On native, we need to provide a file path
    final String path;
    final AudioEncoder encoder;
    final String extension;
    
    if (kIsWeb) {
      // Web: Use opus (compressed) or wav (fallback). AAC-LC not supported.
      encoder = AudioEncoder.opus;
      extension = 'webm';
      path = 'voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    } else {
      // Native: Use AAC-LC for best mobile compatibility
      encoder = AudioEncoder.aacLc;
      extension = 'm4a';
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.$extension';
    }

    await _recorder.start(
      RecordConfig(
        encoder: encoder,
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

    if (path == null || !mounted) return;

    final caps = context.read<CapabilityService>();
    String? transcript;

    debugPrint('🎤 hasTranscriptionServer: ${caps.hasTranscriptionServer}');

    // On web: path is blob URL, fetch blob data for transcription
    // On native: path is file path, check existence
    if (kIsWeb) {
      // Web: Try server-side transcription with blob data
      debugPrint('🎤 Web mode, path: $path');
      if (caps.hasTranscriptionServer) {
        debugPrint('🎤 Attempting web transcription...');
        transcript = await _transcribeAudioWeb(path, 'audio/webm');
      } else {
        debugPrint('🎤 No transcription server detected');
      }
    } else {
      // Native: Check file exists
      final file = File(path);
      if (!await file.exists()) return;

      // Try server-side transcription
      if (caps.hasTranscriptionServer) {
        transcript = await _transcribeAudio(file);
      }

      // Fallback: on-device speech-to-text
      if ((transcript == null || transcript.isEmpty) && !caps.hasTranscriptionServer) {
        debugPrint('🎤 No transcription server, trying on-device STT...');
        transcript = await _transcribeOnDevice(file);
      }
    }

    // Send audio message with transcript (if available) and audio attachment
    await _sendAudioMessage(
      path: path,
      transcript: transcript,
      duration: duration,
      mimeType: kIsWeb ? 'audio/webm' : 'audio/mp4',
    );
    
    _scrollToBottom();
  }
  
  /// Send image file (works on both web and native platforms).
  Future<void> _sendImageFile(XFile xfile, ChatService chat) async {
    try {
      Uint8List imageBytes;
      String fileName;
      
      if (kIsWeb) {
        // Web: Read bytes directly from XFile
        debugPrint('📷 Reading image bytes from web picker...');
        imageBytes = await xfile.readAsBytes();
        fileName = xfile.name;
        debugPrint('📷 Web image: ${imageBytes.length} bytes, name: $fileName');
      } else {
        // Native: Read from file path
        final file = File(xfile.path);
        if (!await file.exists()) {
          throw Exception('Image file not found: ${xfile.path}');
        }
        imageBytes = await file.readAsBytes();
        fileName = file.path.split('/').last;
        debugPrint('📷 Native image: ${imageBytes.length} bytes');
      }
      
      final mimeType = xfile.mimeType ?? 'image/jpeg';
      final sizeKb = imageBytes.length / 1024;
      debugPrint('📎 Sending image: $fileName (${sizeKb.toStringAsFixed(0)} KB, $mimeType)');

      if (imageBytes.length > 5 * 1024 * 1024) {
        throw Exception('File too large (${(imageBytes.length / 1024 / 1024).toStringAsFixed(1)} MB, max 5 MB)');
      }

      final b64 = base64Encode(imageBytes);
      
      chat.sendMessageWithAttachments(
        text: '',
        localAttachments: [
          ChatAttachment(
            type: 'image',
            mimeType: mimeType,
            fileName: fileName,
            filePath: kIsWeb ? null : xfile.path,
            bytes: imageBytes,
            fileSize: imageBytes.length,
          ),
        ],
        gatewayAttachments: [
          {
            'type': 'image',
            'mimeType': mimeType,
            'fileName': fileName,
            'data': b64,
          },
        ],
      );
      
      debugPrint('📷 Image sent: ${imageBytes.length ~/ 1024}KB');
    } catch (e, stack) {
      debugPrint('❌ Error sending image: $e');
      debugPrint('Stack: $stack');
      rethrow; // Let caller handle error
    }
  }
  
  /// Send audio message with transcript and audio attachment.
  Future<void> _sendAudioMessage({
    required String path,
    String? transcript,
    Duration? duration,
    required String mimeType,
  }) async {
    final chat = context.read<ChatService>();
    
    try {
      Uint8List? audioBytes;
      String? fileName;
      
      if (kIsWeb) {
        // Web: Fetch blob data
        debugPrint('🎤 Fetching blob for attachment: $path');
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) {
          audioBytes = response.bodyBytes; // Already Uint8List
          fileName = 'voice-${DateTime.now().millisecondsSinceEpoch}.webm';
          debugPrint('🎤 Blob fetched: ${audioBytes.length} bytes');
        } else {
          debugPrint('⚠️ Failed to fetch blob: ${response.statusCode}');
        }
      } else {
        // Native: Read file
        final file = File(path);
        if (await file.exists()) {
          audioBytes = await file.readAsBytes(); // Returns Uint8List
          fileName = file.path.split('/').last;
          debugPrint('🎤 File read: ${audioBytes.length} bytes');
        } else {
          debugPrint('⚠️ Audio file not found: $path');
        }
      }
      
      if (audioBytes != null && audioBytes.isNotEmpty && fileName != null) {
        // Send message with both transcript and audio attachment
        final displayText = transcript != null && transcript.isNotEmpty
            ? '🎤 $transcript'
            : '🎤 Voice note';
        
        chat.sendMessageWithAttachments(
          text: displayText,
          localAttachments: [
            ChatAttachment(
              type: 'audio',
              mimeType: mimeType,
              fileName: fileName,
              filePath: path,
              bytes: audioBytes,
              duration: duration,
            ),
          ],
          gatewayAttachments: [
            {
              'type': 'audio',
              'mimeType': mimeType,
              'fileName': fileName,
              'data': base64Encode(audioBytes),
              if (duration != null) 'durationMs': duration.inMilliseconds,
            },
          ],
        );
        
        debugPrint('🎤 Sent audio message: ${audioBytes.length ~/ 1024}KB, transcript: ${transcript?.substring(0, transcript.length.clamp(0, 40))}');
      } else {
        // Fallback: send transcript only if we have it
        if (transcript != null && transcript.isNotEmpty) {
          debugPrint('⚠️ Audio bytes unavailable, sending transcript only');
          chat.sendMessage('🎤 $transcript');
        } else {
          debugPrint('❌ No audio bytes and no transcript');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🎤 Failed to send audio'),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Error sending audio message: $e');
      debugPrint('Stack: $stack');
      
      // Fallback: send transcript only if available
      if (transcript != null && transcript.isNotEmpty) {
        chat.sendMessage('🎤 $transcript');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎤 Error: ${e.toString()}'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Transcribe audio on-device using Android's speech recognition.
  /// This is the fallback when no server-side transcription is available.
  Future<String?> _transcribeOnDevice(File file) async {
    // Note: Android SpeechToText works with live mic input, not audio files.
    // For file-based on-device transcription we'd need a different approach.
    // For now, return null to fall through to audio attachment.
    // TODO: Integrate a local whisper model or use MediaPlayer + SpeechRecognizer
    debugPrint('🎤 On-device STT not yet implemented for file input');
    return null;
  }

  /// Transcribe audio file via the local transcription server (native).
  Future<String?> _transcribeAudio(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return await _sendTranscriptionRequest(bytes, 'audio/mp4');
    } catch (e) {
      debugPrint('🎤 Transcription failed: $e');
      return null;
    }
  }

  /// Transcribe audio from blob URL via the local transcription server (web).
  Future<String?> _transcribeAudioWeb(String blobUrl, String mimeType) async {
    try {
      debugPrint('🎤 Fetching blob from: $blobUrl');
      // Fetch blob data from the URL
      final response = await http.get(Uri.parse(blobUrl));
      debugPrint('🎤 Blob fetch: ${response.statusCode}, ${response.bodyBytes.length} bytes');
      if (response.statusCode != 200) {
        debugPrint('🎤 Failed to fetch blob: ${response.statusCode}');
        return null;
      }
      return await _sendTranscriptionRequest(response.bodyBytes, mimeType);
    } catch (e, stack) {
      debugPrint('🎤 Web transcription failed: $e');
      debugPrint('🎤 Stack: $stack');
      return null;
    }
  }

  /// Send transcription request to the server (shared logic).
  Future<String?> _sendTranscriptionRequest(List<int> bytes, String mimeType) async {
    try {
      final b64 = base64Encode(bytes);

      // Try gateway's local IP first, then fallback
      final config = _config;
      final gatewayHost = config != null
          ? Uri.parse(config.url).host
          : 'localhost';
      final url = 'http://$gatewayHost:8014/transcribe';

      debugPrint('🎤 Transcribing via $url (${(bytes.length / 1024).toStringAsFixed(0)} KB, $mimeType)...');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'audio': b64,
          'mimeType': mimeType,
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
      debugPrint('🎤 Transcription request failed: $e');
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

      if (!mounted) return;
      final caps = context.read<CapabilityService>();
      final maxDim = caps.maxImageDimension.toDouble();
      final quality = caps.imageQuality;
      debugPrint('📷 Picking image from ${source.name} (max ${maxDim.toInt()}px, $quality% quality)...');
      final xfile = await _imagePicker.pickImage(
        source: source,
        maxWidth: maxDim,
        maxHeight: maxDim,
        imageQuality: quality,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (xfile == null) {
        debugPrint('📷 Image picker cancelled');
        return;
      }

      debugPrint('📷 Got image: ${xfile.path} (mime: ${xfile.mimeType})');
      if (!mounted) return;
      final chat = context.read<ChatService>();
      await _sendImageFile(xfile, chat);
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
      final caps = context.read<CapabilityService>();
      final maxDim = caps.maxImageDimension.toDouble();
      final quality = caps.imageQuality;
      debugPrint('📷 Opening multi-image picker (max ${maxDim.toInt()}px, $quality% quality)...');
      final xfiles = await _imagePicker.pickMultiImage(
        maxWidth: maxDim,
        maxHeight: maxDim,
        imageQuality: quality,
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
      if (!mounted) return;
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
        try {
          await _sendImageFile(xfile, chat);
          sent++;
        } catch (e) {
          debugPrint('❌ Failed to send image ${i + 1}: $e');
          failed++;
        }

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
    // Show node pairing state if operator connected but node is waiting
    final isNodePairing = gateway.state == msg.GatewayConnectionState.connected && 
                          nodeConn.isPairingPending;
    
    // Show reconnection attempts
    final reconnecting = gateway.reconnectAttempts > 0;
    final reconnectLabel = reconnecting ? ' (${gateway.reconnectAttempts})' : '';
    
    final (color, label) = isNodePairing
        ? (Colors.orange, 'Device Pairing...')
        : switch (gateway.state) {
            msg.GatewayConnectionState.disconnected => (
              Colors.grey, 
              reconnecting ? 'Reconnecting$reconnectLabel...' : 'Offline'
            ),
            msg.GatewayConnectionState.connecting => (
              Colors.orange, 
              reconnecting ? 'Reconnecting$reconnectLabel...' : 'Connecting...'
            ),
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
          // Manual reconnect button (show when disconnected/error)
          Builder(builder: (ctx) {
            final gateway = ctx.watch<GatewayService>();
            final coordinator = ctx.watch<ConnectionCoordinator>();
            final showReconnect = gateway.state == msg.GatewayConnectionState.disconnected ||
                                   gateway.state == msg.GatewayConnectionState.error;
            
            if (!showReconnect) return const SizedBox.shrink();
            
            return IconButton(
              icon: coordinator.isReconnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: coordinator.isReconnecting
                  ? null
                  : () async {
                      final config = gateway.activeConfig;
                      if (config != null) {
                        await coordinator.reconnect();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('No config available. Please enter settings.'),
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    },
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

          // Offline banner (shows when disconnected or has queued messages)
          const OfflineBanner(),

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
                      // Performance optimizations for long message lists
                      cacheExtent: 500, // Only cache ~2-3 screens worth of messages
                      addAutomaticKeepAlives: false, // Don't keep invisible items alive
                      addRepaintBoundaries: true, // Isolate repaints per message
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
      floatingActionButton: Consumer<CanvasService>(
        builder: (context, canvas, _) {
          // Show restore button when canvas is minimized
          if (canvas.isMinimized) {
            return FloatingActionButton.extended(
              onPressed: () => canvas.restore(),
              icon: const Icon(Icons.open_in_full),
              label: const Text('Canvas'),
              backgroundColor: Colors.deepPurple,
              tooltip: 'Restore canvas',
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
