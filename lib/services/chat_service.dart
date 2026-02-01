import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import 'gateway_service.dart';

/// Manages chat state and message flow through the gateway.
class ChatService extends ChangeNotifier {
  final GatewayService _gateway;
  static const _uuid = Uuid();

  final List<ChatMessage> _messages = [];
  String? _activeRunId;

  ChatService(this._gateway) {
    _gateway.addListener(_onGatewayChanged);
  }

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isReady => _gateway.isConnected && _gateway.mainSessionKey != null;
  bool get isStreaming => _activeRunId != null;
  String? get sessionKey => _gateway.mainSessionKey;

  /// Wait until connected and session is ready, with timeout.
  Future<bool> waitForReady({Duration timeout = const Duration(seconds: 15)}) async {
    if (isReady) return true;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (isReady) return true;
    }
    return false;
  }

  void _onGatewayChanged() {
    notifyListeners();
  }

  /// Handle an incoming gateway event or response.
  void handleGatewayMessage(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';

    if (type == 'event') {
      final event = json['event'] as String? ?? '';
      if (event == 'chat') {
        _handleChatEvent(json['payload'] as Map<String, dynamic>? ?? {});
      }
    }
  }

  void _handleChatEvent(Map<String, dynamic> payload) {
    final state = payload['state'] as String? ?? '';
    final runId = payload['runId'] as String? ?? '';
    final messageData = payload['message'] as Map<String, dynamic>?;

    if (messageData == null && state != 'error') return;

    final content = messageData?['content'] as List<dynamic>?;
    final text = content
            ?.whereType<Map<String, dynamic>>()
            .where((c) => c['type'] == 'text')
            .map((c) => c['text'] as String? ?? '')
            .join() ??
        '';

    switch (state) {
      case 'delta':
        _activeRunId = runId;
        final idx = _messages.indexWhere((m) => m.id == runId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            text: text,
            state: ChatMessageState.streaming,
          );
        } else {
          _messages.add(ChatMessage(
            id: runId,
            role: 'assistant',
            text: text,
            timestamp: DateTime.now(),
            state: ChatMessageState.streaming,
          ));
        }
        notifyListeners();
        break;

      case 'final':
        _activeRunId = null;
        // Suppress NO_REPLY / HEARTBEAT_OK — these aren't real responses
        final trimmed = text.trim();
        if (trimmed == 'NO_REPLY' || trimmed == 'HEARTBEAT_OK') {
          // Remove any streaming placeholder for this runId
          _messages.removeWhere((m) => m.id == runId);
          notifyListeners();
          break;
        }
        final idx = _messages.indexWhere((m) => m.id == runId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            text: text.isNotEmpty ? text : _messages[idx].text,
            state: ChatMessageState.complete,
          );
        } else if (text.isNotEmpty) {
          _messages.add(ChatMessage(
            id: runId,
            role: 'assistant',
            text: text,
            timestamp: DateTime.now(),
            state: ChatMessageState.complete,
          ));
        }
        notifyListeners();
        break;

      case 'error':
        _activeRunId = null;
        final errorMsg = payload['errorMessage'] as String? ?? 'Unknown error';
        final idx = _messages.indexWhere((m) => m.id == runId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            text: '⚠️ $errorMsg',
            state: ChatMessageState.error,
          );
        }
        notifyListeners();
        break;
    }
  }

  /// Send a text-only chat message.
  void sendMessage(String text) {
    sendMessageWithAttachments(text: text);
  }

  /// Send a chat message with optional attachments.
  void sendMessageWithAttachments({
    String text = '',
    List<ChatAttachment> localAttachments = const [],
    List<Map<String, dynamic>> gatewayAttachments = const [],
  }) {
    if (!isReady) {
      debugPrint('⚠️ Cannot send: not ready (connected=${_gateway.isConnected}, session=$sessionKey)');
      return;
    }
    if (text.trim().isEmpty && gatewayAttachments.isEmpty) return;

    final idempotencyKey = _uuid.v4();

    // Build display text
    String displayText = text.trim();
    if (displayText.isEmpty && localAttachments.isNotEmpty) {
      final type = localAttachments.first.type;
      displayText = type == 'audio' ? '🎤 Voice note' : '📷 Photo';
    }

    _messages.add(ChatMessage(
      id: 'user-$idempotencyKey',
      role: 'user',
      text: displayText,
      timestamp: DateTime.now(),
      state: ChatMessageState.complete,
      attachments: localAttachments,
    ));
    notifyListeners();

    final params = <String, dynamic>{
      'sessionKey': sessionKey!,
      'message': text.trim().isEmpty
          ? (localAttachments.isNotEmpty
              ? (localAttachments.first.type == 'audio'
                  ? '[voice note]'
                  : '[photo]')
              : '')
          : text.trim(),
      'idempotencyKey': idempotencyKey,
    };

    if (gatewayAttachments.isNotEmpty) {
      params['attachments'] = gatewayAttachments;
    }

    _gateway.sendRequest(
      method: 'chat.send',
      id: _uuid.v4(),
      params: params,
    );

    debugPrint('💬 Sent: ${displayText.substring(0, displayText.length.clamp(0, 40))}'
        '${gatewayAttachments.isNotEmpty ? " + ${gatewayAttachments.length} attachment(s)" : ""}');
  }

  /// Send a file (image or audio) as a chat message.
  Future<void> sendFile({
    required File file,
    required String type, // 'image' or 'audio'
    required String mimeType,
    String caption = '',
    Duration? duration,
  }) async {
    final bytes = await file.readAsBytes();
    final b64 = base64Encode(bytes);
    final fileName = file.path.split('/').last;

    final sizeKb = bytes.length / 1024;
    debugPrint('📎 Sending $type: $fileName (${sizeKb.toStringAsFixed(0)} KB)');

    if (bytes.length > 5 * 1024 * 1024) {
      // Too big for gateway (5MB limit)
      _messages.add(ChatMessage(
        id: 'error-${_uuid.v4()}',
        role: 'user',
        text: '⚠️ File too large (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB, max 5 MB)',
        timestamp: DateTime.now(),
        state: ChatMessageState.error,
      ));
      notifyListeners();
      return;
    }

    sendMessageWithAttachments(
      text: caption,
      localAttachments: [
        ChatAttachment(
          type: type,
          mimeType: mimeType,
          fileName: fileName,
          filePath: file.path,
          bytes: bytes,
          duration: duration,
        ),
      ],
      gatewayAttachments: [
        {
          'type': type,
          'mimeType': mimeType,
          'fileName': fileName,
          'content': b64,
        },
      ],
    );
  }

  @override
  void dispose() {
    _gateway.removeListener(_onGatewayChanged);
    super.dispose();
  }
}
