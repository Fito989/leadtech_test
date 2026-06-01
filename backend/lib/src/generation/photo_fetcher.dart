import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Fetches AI-generated profile photos from `thispersondoesnotexist.com`
/// (StyleGAN faces). Returns null on failure so the generator can fall back to
/// a drawn initials avatar — a missing photo never aborts a CV.
class PhotoFetcher {
  PhotoFetcher({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static final _uri = Uri.parse('https://thispersondoesnotexist.com/');

  void close() => _http.close();

  Future<Uint8List?> fetch({int maxAttempts = 3}) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final resp = await _http.get(
          _uri,
          headers: {'User-Agent': 'Mozilla/5.0 (cv-screener-generator)'},
        ).timeout(const Duration(seconds: 30));
        if (resp.statusCode == 200 &&
            (resp.headers['content-type']?.contains('image') ?? false) &&
            resp.bodyBytes.lengthInBytes > 1000) {
          return resp.bodyBytes;
        }
      } catch (_) {
        // fall through to retry/backoff
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
    return null;
  }
}
