import 'dart:typed_data';

enum MessageRole { user, assistant }

enum MessageState { sent, loading, done }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String text;
  final Uint8List? imageBytes; // user-attached image (display only)
  final MessageState state;
  final Map<String, dynamic>? foodInfo; // from API food_info field

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.imageBytes,
    this.state = MessageState.done,
    this.foodInfo,
  });

  ChatMessage copyWith({
    String? text,
    MessageState? state,
    Map<String, dynamic>? foodInfo,
  }) {
    return ChatMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      imageBytes: imageBytes,
      state: state ?? this.state,
      foodInfo: foodInfo ?? this.foodInfo,
    );
  }

  bool get needsRecordPrompt =>
      role == MessageRole.assistant && text.contains('需要帮您记录吗');
}
