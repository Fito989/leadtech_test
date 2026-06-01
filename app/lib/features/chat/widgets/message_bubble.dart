import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../domain/entities/chat_message.dart';
import 'source_chip.dart';

/// A single chat bubble. User messages are right-aligned and coloured;
/// assistant messages are left-aligned with optional source chips.
class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final bubbleColor = isUser ? scheme.primary : scheme.surfaceContainerHighest;
    final textColor = isUser ? scheme.onPrimary : scheme.onSurface;
    // Responsive: cap bubble width to a fraction of the screen on phones,
    // and to a comfortable reading width on tablets/desktop.
    final maxBubbleWidth = math.min(560.0, MediaQuery.sizeOf(context).width * 0.82);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxBubbleWidth),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor,
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User text is plain; assistant answers render as Markdown.
            if (isUser)
              SelectableText(
                message.text,
                style: TextStyle(color: textColor, height: 1.35),
              )
            else
              GptMarkdown(
                message.text,
                style: TextStyle(color: textColor, height: 1.4),
              ),
            if (!isUser && message.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final s in message.sources) SourceChip(source: s),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
