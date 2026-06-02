import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/chat_cubit.dart';
import 'empty_state.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';

class MessageList extends StatefulWidget {
  const MessageList({super.key, required this.examples});
  final List<String> examples;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _scroll = ScrollController();

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (_, __) => _toBottom(),
      builder: (context, state) {
        if (state.messages.isEmpty) {
          return EmptyState(examples: widget.examples);
        }
        final itemCount = state.messages.length + (state.isSending ? 1 : 0);
        return ListView.builder(
          controller: _scroll,
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index >= state.messages.length) return const TypingIndicator();
            return MessageBubble(message: state.messages[index]);
          },
        );
      },
    );
  }
}
