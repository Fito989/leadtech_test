import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text field + send button. Enter sends; the field is disabled while a
/// request is in flight.
class ChatInput extends StatefulWidget {
  const ChatInput({super.key, required this.enabled, required this.onSend});

  final bool enabled;
  final void Function(String text) onSend;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): _submit,
            },
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: 'Ask about the candidates…',
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Circular send button, sized to match the single-line field height.
        SizedBox(
          width: 52,
          height: 52,
          child: FilledButton(
            onPressed: widget.enabled ? _submit : null,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: EdgeInsets.zero,
            ),
            child: const Icon(Icons.send_rounded),
          ),
        ),
      ],
    );
  }
}
