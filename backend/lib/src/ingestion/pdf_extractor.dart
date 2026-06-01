import 'dart:io';

/// Extracts text from a CV PDF using poppler's `pdftotext` (tech-prd §6.2).
/// Returns an empty string on any failure so the pipeline can fall back to the
/// sidecar JSON — a single unreadable PDF never aborts ingestion (NFR-04).
class PdfExtractor {
  static Future<String> extractText(String pdfPath) async {
    try {
      final result = await Process.run('pdftotext', ['-layout', pdfPath, '-']);
      if (result.exitCode == 0 && result.stdout is String) {
        return result.stdout as String;
      }
    } catch (_) {
      // pdftotext not installed or failed — caller falls back to sidecar.
    }
    return '';
  }
}
