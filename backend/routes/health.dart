import 'package:backend/src/bootstrap.dart';
import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  final backend = context.read<Backend>();
  return Response.json(
    statusCode: backend.ready ? 200 : 503,
    body: {
      'status': backend.ready ? 'ok' : 'not_initialized',
      'indexReady': backend.ready,
      'chunks': backend.index?.length ?? 0,
      'candidates': backend.index?.roster.length ?? 0,
      if (backend.indexError != null) 'error': backend.indexError,
    },
  );
}
