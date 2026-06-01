import 'package:flutter/material.dart';

import '../../../domain/entities/source.dart';

/// Small chip attributing an answer to a source CV.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scoreText = source.score != null ? ' · ${(source.score! * 100).round()}%' : '';
    return Tooltip(
      message: source.file,
      child: Chip(
        avatar: Icon(Icons.description_outlined, size: 16, color: scheme.primary),
        label: Text('${source.candidate}$scoreText'),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: scheme.surfaceContainerHighest,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    );
  }
}
