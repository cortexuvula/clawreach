import 'dart:typed_data';

/// Attachment metadata for a chat message.
class ChatAttachment {
  final String type; // 'image', 'audio', 'file'
  final String mimeType;
  final String? fileName;
  final String? filePath; // Local path (for user-sent media)
  final Uint8List? bytes; // Raw bytes (for display)
  final Duration? duration; // For audio

  const ChatAttachment({
    required this.type,
    required this.mimeType,
    this.fileName,
    this.filePath,
    this.bytes,
    this.duration,
  });

  bool get isImage => type == 'image';
  bool get isAudio => type == 'audio';
}

/// A chat message in the conversation.
class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String text;
  final DateTime timestamp;
  final ChatMessageState state;
  final List<ChatAttachment> attachments;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.state = ChatMessageState.complete,
    this.attachments = const [],
  });

  ChatMessage copyWith({
    String? text,
    ChatMessageState? state,
    List<ChatAttachment>? attachments,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        state: state ?? this.state,
        attachments: attachments ?? this.attachments,
      );

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isStreaming => state == ChatMessageState.streaming;
  bool get hasAttachments => attachments.isNotEmpty;
}

enum ChatMessageState {
  sending,
  streaming,
  complete,
  error,
}
