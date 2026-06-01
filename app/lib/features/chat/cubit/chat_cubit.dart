import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/repositories/chat_repository.dart';

part 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._repository) : super(const ChatState());

  final ChatRepository _repository;

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    final history = state.messages; // prior turns, before this question
    final userMessage = ChatMessage(sender: Sender.user, text: trimmed);
    emit(state.copyWith(
      messages: [...state.messages, userMessage],
      status: ChatStatus.sending,
      clearError: true,
    ));

    try {
      final reply = await _repository.send(trimmed, history);
      final assistant = ChatMessage(
        sender: Sender.assistant,
        text: reply.answer,
        sources: reply.sources,
        intent: reply.intent,
        matched: reply.matched,
      );
      emit(state.copyWith(
        messages: [...state.messages, assistant],
        status: ChatStatus.idle,
      ));
    } catch (e) {
      emit(state.copyWith(status: ChatStatus.error, error: e.toString()));
    }
  }

  void clear() => emit(const ChatState());
}
