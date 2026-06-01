import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/chat.dart';

/// Thrown for non-recoverable Gemini API failures. Carries the HTTP status so
/// callers/middleware can map it to a sensible response code.
class GeminiException implements Exception {
  GeminiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => 'GeminiException(${status ?? '-'}): $message';
}

/// Task types for `gemini-embedding-2`. Embedding the query and the documents
/// with the matching task type meaningfully improves retrieval quality.
class EmbedTask {
  static const document = 'RETRIEVAL_DOCUMENT';
  static const query = 'RETRIEVAL_QUERY';
}

/// Thin REST client over the Gemini API (`generativelanguage.googleapis.com`).
///
/// Handles three operations the app needs: free-text [chat], structured
/// [generateJson] (used by the query router), and [embed]. All requests share
/// a retry-with-backoff policy for transient failures and fail fast on auth
/// errors so a bad key surfaces immediately.
class GeminiClient {
  GeminiClient({
    required this.apiKey,
    required this.chatModel,
    required this.embedModel,
    this.embedDim = 768,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
    this.maxAttempts = 4,
  }) : _http = client ?? http.Client();

  final String apiKey;
  final String chatModel;
  final String embedModel;
  final int embedDim;
  final Duration timeout;
  final int maxAttempts;
  final http.Client _http;

  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  void close() => _http.close();

  // --- Public API ---------------------------------------------------------

  /// Generate a free-text answer. [history] is the prior conversation; Gemini
  /// uses the role `model` for assistant turns.
  Future<String> chat({
    required String systemPrompt,
    required String userMessage,
    List<ChatTurn> history = const [],
    double temperature = 0.2,
  }) async {
    final contents = <Map<String, dynamic>>[
      for (final turn in history)
        {
          'role': turn.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': turn.content}
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      },
    ];

    final body = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': contents,
      'generationConfig': {'temperature': temperature},
    };

    final json = await _post('$chatModel:generateContent', body);
    return _extractText(json);
  }

  /// Generate a structured JSON object constrained by [schema]. Used by the
  /// query router to classify intent reliably (JSON mode).
  Future<Map<String, dynamic>> generateJson({
    required String systemPrompt,
    required String userMessage,
    required Map<String, dynamic> schema,
  }) async {
    final body = {
      'system_instruction': {
        'parts': [
          {'text': systemPrompt}
        ]
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userMessage}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0,
        'responseMimeType': 'application/json',
        'responseSchema': schema,
      },
    };

    final json = await _post('$chatModel:generateContent', body);
    final text = _extractText(json);
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      throw GeminiException('Model did not return valid JSON: $text');
    }
  }

  /// Embed a single text with the given [taskType].
  Future<List<double>> embedOne(String text, {required String taskType}) async {
    final body = {
      'model': 'models/$embedModel',
      'content': {
        'parts': [
          {'text': text}
        ]
      },
      'taskType': taskType,
      'outputDimensionality': embedDim,
    };
    final json = await _post('$embedModel:embedContent', body);
    final values = (json['embedding']?['values'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList(growable: false);
    if (values == null || values.isEmpty) {
      throw GeminiException('Empty embedding response');
    }
    return values;
  }

  /// Embed many texts with bounded concurrency. `gemini-embedding-2` exposes
  /// only single-item `embedContent`, so we parallelize in small waves to stay
  /// fast without tripping free-tier rate limits.
  Future<List<List<double>>> embed(
    List<String> texts, {
    required String taskType,
    int concurrency = 4,
  }) async {
    final results = List<List<double>?>.filled(texts.length, null);
    for (var start = 0; start < texts.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, texts.length);
      await Future.wait([
        for (var i = start; i < end; i++)
          embedOne(texts[i], taskType: taskType).then((v) => results[i] = v),
      ]);
    }
    return results.map((e) => e!).toList(growable: false);
  }

  // --- Internals ----------------------------------------------------------

  String _extractText(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      // Could be a safety block; surface the reason if present.
      final feedback = json['promptFeedback'];
      throw GeminiException('No content returned${feedback != null ? ' ($feedback)' : ''}');
    }
    final parts = candidates.first['content']?['parts'] as List?;
    final text = parts
        ?.map((p) => p['text'] as String? ?? '')
        .where((s) => s.isNotEmpty)
        .join();
    if (text == null || text.isEmpty) {
      throw GeminiException('Empty text in model response');
    }
    return text;
  }

  /// POST with retry/backoff. Retries transient failures (429/5xx, network);
  /// throws immediately on auth/client errors so misconfiguration fails fast.
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$_base/models/$path');
    var attempt = 0;
    while (true) {
      attempt++;
      try {
        final resp = await _http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': apiKey,
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);

        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }

        final retriable = resp.statusCode == 429 || resp.statusCode >= 500;
        if (!retriable || attempt >= maxAttempts) {
          throw GeminiException(
            _errorMessage(resp.statusCode, resp.body),
            status: resp.statusCode,
          );
        }
      } on GeminiException {
        rethrow;
      } on TimeoutException {
        if (attempt >= maxAttempts) {
          throw GeminiException('Request timed out after $maxAttempts attempts');
        }
      } catch (e) {
        // Network-level error; retry unless we're out of attempts.
        if (attempt >= maxAttempts) {
          throw GeminiException('Network error: $e');
        }
      }
      // Exponential backoff: 0.5s, 1s, 2s, ...
      await Future<void>.delayed(Duration(milliseconds: 500 * (1 << (attempt - 1))));
    }
  }

  String _errorMessage(int status, String body) {
    if (status == 401 || status == 403) {
      return 'Authentication failed ($status). Check GEMINI_API_KEY.';
    }
    if (status == 429) {
      return 'Gemini rate limit / daily quota exceeded. Wait a moment and retry, '
          'or set GEMINI_CHAT_MODEL to another model.';
    }
    if (status >= 500) {
      return 'Gemini is temporarily unavailable ($status). Please try again.';
    }
    if (status == 400) {
      return 'Bad request (400).';
    }
    return 'Gemini API error ($status).';
  }
}
