/// A chat message in the conversation.
class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String text;
  final DateTime timestamp;
  final ChatMessageState state;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    this.state = ChatMessageState.complete,
  });

  ChatMessage copyWith({
    String? text,
    ChatMessageState? state,
  }) =>
      ChatMessage(
        id: id,
        role: role,
        text: text ?? this.text,
        timestamp: timestamp,
        state: state ?? this.state,
      );

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';
  bool get isStreaming => state == ChatMessageState.streaming;
}

enum ChatMessageState {
  sending,
  streaming,
  complete,
  error,
}
