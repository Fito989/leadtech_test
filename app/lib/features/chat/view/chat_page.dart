import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/chat_cubit.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';

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
                  Expanded(child: _MessageList(examples: _examples)),
                  const _ErrorBanner(),
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

class _MessageList extends StatefulWidget {
  const _MessageList({required this.examples});
  final List<String> examples;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
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
          return _EmptyState(examples: widget.examples);
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.examples});
  final List<String> examples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_alt_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text('Ask anything about the candidate CVs',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ex in examples)
                  ActionChip(
                    label: Text(ex),
                    onPressed: () => context.read<ChatCubit>().send(ex),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (a, b) => a.status != b.status || a.error != b.error,
      builder: (context, state) {
        if (state.status != ChatStatus.error || state.error == null) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).shadowColor,
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.error!,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
