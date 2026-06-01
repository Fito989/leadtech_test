import '../entities/chat_message.dart';
import '../entities/source.dart';

/// The assistant's reply to one question.
class AssistantReply {
  const AssistantReply({
    required this.answer,
    required this.sources,
    required this.intent,
    required this.matched,
  });

  final String answer;
  final List<Source> sources;
  final String intent;
  final bool matched;
}

/// Sends a question (plus prior turns for follow-ups) to the backend.
abstract class ChatRepository {
  Future<AssistantReply> send(String message, List<ChatMessage> history);
}
