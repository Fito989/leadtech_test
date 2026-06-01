/// Request/response models for the `POST /chat` endpoint.

/// A single prior turn in the conversation, used for follow-up resolution.
class ChatTurn {
  ChatTurn({required this.role, required this.content});

  /// `user` or `assistant`.
  final String role;
  final String content;

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatTurn.fromJson(Map<String, dynamic> json) => ChatTurn(
        role: json['role'] as String? ?? 'user',
        content: json['content'] as String? ?? '',
      );
}

class ChatRequest {
  ChatRequest({required this.message, this.history = const []});

  final String message;
  final List<ChatTurn> history;

  factory ChatRequest.fromJson(Map<String, dynamic> json) => ChatRequest(
        message: (json['message'] as String? ?? '').trim(),
        history: (json['history'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatTurn.fromJson)
            .toList(),
      );
}

/// A CV that contributed to an answer, surfaced to the user for attribution.
class Source {
  Source({required this.candidate, required this.file, this.score});

  final String candidate;
  final String file;

  /// Cosine similarity for the semantic branch; null for full-corpus/name
  /// strategies where ranking doesn't apply.
  final double? score;

  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        'file': file,
        if (score != null) 'score': double.parse(score!.toStringAsFixed(3)),
      };
}

class ChatResponse {
  ChatResponse({
    required this.answer,
    required this.intent,
    required this.sources,
    required this.matched,
  });

  final String answer;
  final String intent;
  final List<Source> sources;

  /// false when nothing relevant was found or the question was out of scope.
  final bool matched;

  Map<String, dynamic> toJson() => {
        'answer': answer,
        'intent': intent,
        'sources': sources.map((s) => s.toJson()).toList(),
        'matched': matched,
      };
}
