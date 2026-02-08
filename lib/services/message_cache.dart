import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

/// Caches recent messages to SharedPreferences for offline access.
class MessageCache {
  static const _keyPrefix = 'cached_messages_';
  static const _keyLastSync = 'message_cache_last_sync';
  static const _maxCachedMessages = 100; // Keep last 100 messages

  /// Save messages to cache
  static Future<void> saveMessages(List<ChatMessage> messages, String sessionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Take last N messages to avoid excessive storage
      final toCache = messages.length > _maxCachedMessages
          ? messages.sublist(messages.length - _maxCachedMessages)
          : messages;

      // Serialize messages to JSON
      final jsonList = toCache.map((msg) => {
        'id': msg.id,
        'role': msg.role,
        'text': msg.text,
        'timestamp': msg.timestamp.toIso8601String(),
        'state': msg.state.name,
        'attachments': msg.attachments.map((a) => {
          'type': a.type,
          'mimeType': a.mimeType,
          'fileName': a.fileName,
          'filePath': a.filePath,
          'duration': a.duration,
        }).toList(),
      }).toList();

      final json = jsonEncode(jsonList);
      await prefs.setString('$_keyPrefix$sessionKey', json);
      await prefs.setInt(_keyLastSync, DateTime.now().millisecondsSinceEpoch);
      
      debugPrint('💾 Cached ${toCache.length} messages for session $sessionKey');
    } catch (e) {
      debugPrint('⚠️ Failed to cache messages: $e');
    }
  }

  /// Load cached messages
  static Future<List<ChatMessage>> loadMessages(String sessionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_keyPrefix$sessionKey');
      
      if (json == null) {
        debugPrint('📭 No cached messages for session $sessionKey');
        return [];
      }

      final jsonList = jsonDecode(json) as List<dynamic>;
      final messages = jsonList.map((item) {
        final map = item as Map<String, dynamic>;
        return ChatMessage(
          id: map['id'] as String,
          role: map['role'] as String,
          text: map['text'] as String,
          timestamp: DateTime.parse(map['timestamp'] as String),
          state: ChatMessageState.values.firstWhere(
            (s) => s.name == map['state'],
            orElse: () => ChatMessageState.complete,
          ),
          attachments: (map['attachments'] as List<dynamic>?)?.map((a) {
            final aMap = a as Map<String, dynamic>;
            final durationMs = aMap['duration'] as int?;
            return ChatAttachment(
              type: aMap['type'] as String,
              mimeType: aMap['mimeType'] as String,
              fileName: aMap['fileName'] as String,
              filePath: aMap['filePath'] as String?,
              bytes: null, // Not cached (too large)
              duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
            );
          }).toList() ?? [],
        );
      }).toList();

      debugPrint('📦 Loaded ${messages.length} cached messages for session $sessionKey');
      return messages;
    } catch (e) {
      debugPrint('⚠️ Failed to load cached messages: $e');
      return [];
    }
  }

  /// Get last sync timestamp
  static Future<DateTime?> getLastSync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(_keyLastSync);
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (e) {
      return null;
    }
  }

  /// Clear cache for a session
  static Future<void> clearCache(String sessionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_keyPrefix$sessionKey');
      debugPrint('🗑️ Cleared message cache for session $sessionKey');
    } catch (e) {
      debugPrint('⚠️ Failed to clear cache: $e');
    }
  }

  /// Clear all caches
  static Future<void> clearAllCaches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final cacheKeys = keys.where((k) => k.startsWith(_keyPrefix));
      
      for (final key in cacheKeys) {
        await prefs.remove(key);
      }
      
      await prefs.remove(_keyLastSync);
      debugPrint('🗑️ Cleared all message caches (${cacheKeys.length} sessions)');
    } catch (e) {
      debugPrint('⚠️ Failed to clear all caches: $e');
    }
  }
}
