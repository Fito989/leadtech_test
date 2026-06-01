import 'package:bloc_test/bloc_test.dart';
import 'package:cv_screener_app/domain/entities/chat_message.dart';
import 'package:cv_screener_app/domain/entities/source.dart';
import 'package:cv_screener_app/domain/repositories/chat_repository.dart';
import 'package:cv_screener_app/features/chat/cubit/chat_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRepo implements ChatRepository {
  _FakeRepo(this.reply, {this.fail = false});
  final AssistantReply reply;
  final bool fail;

  @override
  Future<AssistantReply> send(String message, List<ChatMessage> history) async {
    if (fail) throw Exception('boom');
    return reply;
  }
}

void main() {
  const reply = AssistantReply(
    answer: 'Jane Doe knows Python.',
    sources: [Source(candidate: 'Jane Doe', file: 'cv01_jane_doe.pdf', score: 0.9)],
    intent: 'listing',
    matched: true,
  );

  blocTest<ChatCubit, ChatState>(
    'emits sending then idle with user + assistant messages on success',
    build: () => ChatCubit(_FakeRepo(reply)),
    act: (cubit) => cubit.send('Who knows Python?'),
    expect: () => [
      isA<ChatState>()
          .having((s) => s.status, 'status', ChatStatus.sending)
          .having((s) => s.messages.length, 'messages', 1),
      isA<ChatState>()
          .having((s) => s.status, 'status', ChatStatus.idle)
          .having((s) => s.messages.length, 'messages', 2)
          .having((s) => s.messages.last.sender, 'last sender', Sender.assistant),
    ],
  );

  blocTest<ChatCubit, ChatState>(
    'emits error status when the repository throws',
    build: () => ChatCubit(_FakeRepo(reply, fail: true)),
    act: (cubit) => cubit.send('hi'),
    expect: () => [
      isA<ChatState>().having((s) => s.status, 'status', ChatStatus.sending),
      isA<ChatState>().having((s) => s.status, 'status', ChatStatus.error),
    ],
  );

  blocTest<ChatCubit, ChatState>(
    'ignores empty input',
    build: () => ChatCubit(_FakeRepo(reply)),
    act: (cubit) => cubit.send('   '),
    expect: () => const <ChatState>[],
  );
}
