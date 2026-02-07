import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Queued message waiting to be sent
class QueuedMessage {
  final String id;
  final String text;
  final List<Map<String, dynamic>>? attachments;
  final DateTime queuedAt;

  QueuedMessage({
    required this.id,
    required this.text,
    this.attachments,
    required this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'attachments': attachments,
    'queuedAt': queuedAt.toIso8601String(),
  };

  factory QueuedMessage.fromJson(Map<String, dynamic> json) => QueuedMessage(
    id: json['id'] as String,
    text: json['text'] as String,
    attachments: (json['attachments'] as List<dynamic>?)
        ?.map((a) => a as Map<String, dynamic>)
        .toList(),
    queuedAt: DateTime.parse(json['queuedAt'] as String),
  );
}

/// Manages outbound message queue for offline support.
/// Messages are queued when disconnected and sent when connection is restored.
class MessageQueue extends ChangeNotifier {
  static const _keyQueue = 'message_queue';
  static const _uuid = Uuid();

  final List<QueuedMessage> _queue = [];
  bool _isProcessing = false;

  List<QueuedMessage> get queue => List.unmodifiable(_queue);
  int get queueSize => _queue.length;
  bool get hasQueuedMessages => _queue.isNotEmpty;

  /// Initialize and load persisted queue
  Future<void> init() async {
    await _loadQueue();
    debugPrint('📥 Message queue initialized: ${_queue.length} pending');
  }

  /// Add message to queue
  Future<String> enqueue(String text, {List<Map<String, dynamic>>? attachments}) async {
    final message = QueuedMessage(
      id: _uuid.v4(),
      text: text,
      attachments: attachments,
      queuedAt: DateTime.now(),
    );

    _queue.add(message);
    await _persistQueue();
    notifyListeners();

    debugPrint('📤 Queued message: ${message.id} (queue size: ${_queue.length})');
    return message.id;
  }

  /// Process queue and send messages
  Future<void> processQueue(Future<void> Function(QueuedMessage) sendFunction) async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    debugPrint('⚙️ Processing message queue: ${_queue.length} messages');

    final toSend = List<QueuedMessage>.from(_queue);
    
    for (final message in toSend) {
      try {
        debugPrint('📨 Sending queued message: ${message.id}');
        await sendFunction(message);
        
        // Remove from queue on success
        _queue.removeWhere((m) => m.id == message.id);
        await _persistQueue();
        notifyListeners();
        
        debugPrint('✅ Sent queued message: ${message.id}');
      } catch (e) {
        debugPrint('❌ Failed to send queued message ${message.id}: $e');
        // Keep in queue for retry
        break; // Stop processing on first failure
      }
    }

    _isProcessing = false;
    
    if (_queue.isEmpty) {
      debugPrint('✅ Message queue cleared');
    } else {
      debugPrint('⚠️ ${_queue.length} messages still queued (send failed)');
    }
  }

  /// Remove a specific message from queue
  Future<void> remove(String messageId) async {
    _queue.removeWhere((m) => m.id == messageId);
    await _persistQueue();
    notifyListeners();
    debugPrint('🗑️ Removed message from queue: $messageId');
  }

  /// Clear entire queue
  Future<void> clear() async {
    _queue.clear();
    await _persistQueue();
    notifyListeners();
    debugPrint('🗑️ Message queue cleared');
  }

  /// Load queue from SharedPreferences
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_keyQueue);
      
      if (json == null) return;

      final jsonList = jsonDecode(json) as List<dynamic>;
      _queue.clear();
      _queue.addAll(
        jsonList.map((item) => QueuedMessage.fromJson(item as Map<String, dynamic>))
      );
    } catch (e) {
      debugPrint('⚠️ Failed to load message queue: $e');
    }
  }

  /// Persist queue to SharedPreferences
  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      if (_queue.isEmpty) {
        await prefs.remove(_keyQueue);
      } else {
        final jsonList = _queue.map((m) => m.toJson()).toList();
        final json = jsonEncode(jsonList);
        await prefs.setString(_keyQueue, json);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to persist message queue: $e');
    }
  }
}
