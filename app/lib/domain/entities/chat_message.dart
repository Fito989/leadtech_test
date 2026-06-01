import 'package:equatable/equatable.dart';

import 'source.dart';

enum Sender { user, assistant }

/// A single message in the chat transcript.
class ChatMessage extends Equatable {
  const ChatMessage({
    required this.sender,
    required this.text,
    this.sources = const [],
    this.intent,
    this.matched = true,
  });

  final Sender sender;
  final String text;
  final List<Source> sources;
  final String? intent;
  final bool matched;

  bool get isUser => sender == Sender.user;

  @override
  List<Object?> get props => [sender, text, sources, intent, matched];
}
