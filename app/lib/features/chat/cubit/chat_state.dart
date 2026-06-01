part of 'chat_cubit.dart';

enum ChatStatus { idle, sending, error }

class ChatState extends Equatable {
  const ChatState({
    this.messages = const [],
    this.status = ChatStatus.idle,
    this.error,
  });

  final List<ChatMessage> messages;
  final ChatStatus status;
  final String? error;

  bool get isSending => status == ChatStatus.sending;

  ChatState copyWith({
    List<ChatMessage>? messages,
    ChatStatus? status,
    String? error,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [messages, status, error];
}
