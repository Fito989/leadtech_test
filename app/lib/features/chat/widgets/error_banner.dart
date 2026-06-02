import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/chat_cubit.dart';

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key});

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
