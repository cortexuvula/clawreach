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

  /// Send a chat message.
  void sendMessage(String text) {
    if (!isReady || text.trim().isEmpty) return;

    final idempotencyKey = _uuid.v4();

    _messages.add(ChatMessage(
      id: 'user-$idempotencyKey',
      role: 'user',
      text: text.trim(),
      timestamp: DateTime.now(),
      state: ChatMessageState.complete,
    ));
    notifyListeners();

    _gateway.sendRequest(
      method: 'chat.send',
      id: _uuid.v4(),
      params: {
        'sessionKey': sessionKey!,
        'message': text.trim(),
        'idempotencyKey': idempotencyKey,
      },
    );

    debugPrint('💬 Sent: ${text.trim().substring(0, text.trim().length.clamp(0, 40))}');
  }

  @override
  void dispose() {
    _gateway.removeListener(_onGatewayChanged);
    super.dispose();
  }
}
