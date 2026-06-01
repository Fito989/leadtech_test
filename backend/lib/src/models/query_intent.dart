/// The query-type router's classification of a user message.
///
/// Each intent maps to a context-assembly strategy in [RagService]:
/// - [listing] / [aggregation] -> full-corpus (completeness/recall)
/// - [candidateSpecific] / [comparison] -> name-filtered chunks
/// - [semantic] -> vector top-k retrieval (classic RAG)
/// - [outOfScope] -> guardrail refusal
enum Intent {
  candidateSpecific,
  listing,
  aggregation,
  comparison,
  semantic,
  outOfScope;

  static Intent fromString(String? value) {
    switch (value?.trim()) {
      case 'candidateSpecific':
        return Intent.candidateSpecific;
      case 'listing':
        return Intent.listing;
      case 'aggregation':
        return Intent.aggregation;
      case 'comparison':
        return Intent.comparison;
      case 'outOfScope':
        return Intent.outOfScope;
      case 'semantic':
      default:
        // Default to semantic: a real but conservative RAG lookup is the
        // safest fallback when the classifier is unsure.
        return Intent.semantic;
    }
  }
}

class QueryIntent {
  QueryIntent({required this.intent, this.candidateNames = const []});

  final Intent intent;

  /// Candidate names mentioned in the query, validated against the roster.
  final List<String> candidateNames;

  factory QueryIntent.fromJson(Map<String, dynamic> json) => QueryIntent(
        intent: Intent.fromString(json['intent'] as String?),
        candidateNames: (json['candidateNames'] as List? ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
}
