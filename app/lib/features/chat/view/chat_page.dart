import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/chat_cubit.dart';
import '../widgets/chat_input.dart';
import '../widgets/error_banner.dart';
import '../widgets/message_list.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({super.key});

  static const _examples = [
    'Who has experience with Python?',
    'Which candidate graduated from UPC?',
    'Summarize the profile of Jane Doe.',
    'How many candidates know React?',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CV Screener'),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            onPressed: () => context.read<ChatCubit>().clear(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              // Responsive: tighter padding on phones, roomier on tablets/desktop.
              padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 600 ? 12 : 20,
                vertical: 8,
              ),
              child: Column(
                children: [
                  Expanded(child: MessageList(examples: _examples)),
                  const ErrorBanner(),
                  const SizedBox(height: 8),
                  BlocBuilder<ChatCubit, ChatState>(
                    buildWhen: (a, b) => a.isSending != b.isSending,
                    builder: (context, state) => ChatInput(
                      enabled: !state.isSending,
                      onSend: (text) => context.read<ChatCubit>().send(text),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
