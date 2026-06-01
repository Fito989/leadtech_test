import 'package:backend/src/bootstrap.dart';
import 'package:dart_frog/dart_frog.dart';

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

Handler middleware(Handler handler) {
  return handler
      .use(requestLogger())
      .use(provider<Backend>((_) => Backend.instance))
      .use(_cors());
}

/// Adds CORS headers (Flutter web is a different origin) and answers preflight
/// OPTIONS requests.
Middleware _cors() {
  return (handler) {
    return (context) async {
      if (context.request.method == HttpMethod.options) {
        return Response(statusCode: 200, headers: _corsHeaders);
      }
      final response = await handler(context);
      return response.copyWith(headers: {...response.headers, ..._corsHeaders});
    };
  };
}
