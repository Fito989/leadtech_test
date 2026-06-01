import 'package:dio/dio.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/source.dart';
import '../../domain/repositories/chat_repository.dart';

/// Friendly, user-facing failure from the chat backend.
class ChatException implements Exception {
  ChatException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(this._dio);
  final Dio _dio;

  @override
  Future<AssistantReply> send(String message, List<ChatMessage> history) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat',
        data: {
          'message': message,
          'history': history
              .map((m) => {
                    'role': m.isUser ? 'user' : 'assistant',
                    'content': m.text,
                  })
              .toList(),
        },
      );
      final data = response.data ?? const {};
      return AssistantReply(
        answer: data['answer'] as String? ?? '',
        intent: data['intent'] as String? ?? '',
        matched: data['matched'] as bool? ?? false,
        sources: (data['sources'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(Source.fromJson)
            .toList(),
      );
    } on DioException catch (e) {
      throw ChatException(_friendly(e));
    }
  }

  String _friendly(DioException e) {
    final body = e.response?.data;
    if (body is Map && body['error'] is Map && body['error']['message'] != null) {
      return body['error']['message'].toString();
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return 'Could not reach the backend. Is it running on the configured URL?';
    }
    return 'Something went wrong talking to the backend (${e.response?.statusCode ?? e.type.name}).';
  }
}
