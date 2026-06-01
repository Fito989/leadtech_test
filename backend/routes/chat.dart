import 'package:backend/src/bootstrap.dart';
import 'package:backend/src/gemini/gemini_client.dart';
import 'package:backend/src/models/chat.dart';
import 'package:dart_frog/dart_frog.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(
      statusCode: 405,
      body: {'error': {'code': 'METHOD_NOT_ALLOWED', 'message': 'Use POST'}},
    );
  }

  final backend = context.read<Backend>();
  if (!backend.ready) {
    return Response.json(
      statusCode: 503,
      body: {
        'error': {
          'code': 'NOT_INITIALIZED',
          'message': backend.indexError ?? 'Vector index not built. Run tools/ingest.dart.',
        }
      },
    );
  }

  Map<String, dynamic> json;
  try {
    json = (await context.request.json()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(
      statusCode: 400,
      body: {'error': {'code': 'BAD_JSON', 'message': 'Request body must be JSON.'}},
    );
  }

  final request = ChatRequest.fromJson(json);
  if (request.message.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': {'code': 'EMPTY_MESSAGE', 'message': '"message" is required.'}},
    );
  }
  if (request.message.length > 2000) {
    return Response.json(
      statusCode: 400,
      body: {'error': {'code': 'TOO_LONG', 'message': 'Message is too long (max 2000 chars).'}},
    );
  }

  try {
    final response = await backend.rag!.answer(request);
    return Response.json(body: response.toJson());
  } on GeminiException catch (e) {
    final rateLimited = e.status == 429;
    return Response.json(
      statusCode: rateLimited ? 429 : 502,
      body: {
        'error': {
          'code': rateLimited ? 'RATE_LIMITED' : 'UPSTREAM_ERROR',
          'message': e.message,
        }
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': {'code': 'INTERNAL', 'message': e.toString()}},
    );
  }
}
