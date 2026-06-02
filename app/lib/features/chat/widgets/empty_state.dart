import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/chat_cubit.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.examples});
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
