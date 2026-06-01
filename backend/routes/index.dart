import 'package:backend/src/bootstrap.dart';
import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  final backend = context.read<Backend>();
  return Response.json(
    body: {
      'name': 'CV Screener API',
      'chatModel': backend.config.chatModel,
      'embedModel': backend.config.embedModel,
      'indexReady': backend.ready,
      'chunks': backend.index?.length ?? 0,
      'candidates': backend.index?.roster.length ?? 0,
      'endpoints': ['GET /health', 'POST /chat'],
    },
  );
}
