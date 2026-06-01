import '../models/cv_chunk.dart';

/// Splits a CV into one chunk per section (tech-prd §6.3). Works on the text
/// extracted from the PDF by detecting the capitalised section headers the
/// generator renders; callers supply a sidecar fallback when extraction is poor.
class Chunker {
  /// Section headers as rendered in the PDF (uppercase, on their own line).
  static const headers = ['SUMMARY', 'EXPERIENCE', 'SKILLS', 'EDUCATION', 'LANGUAGES'];

  /// Parse extracted `pdftotext` output into `{section: text}`. Everything
  /// above the first header (name, role, contact line) becomes `contact`.
  static Map<String, String> sectionsFromText(String text) {
    final sections = <String, String>{};
    var current = 'contact';
    final buffer = <String, List<String>>{current: []};

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final header = headers.firstWhere(
        (h) => line.toUpperCase() == h,
        orElse: () => '',
      );
      if (header.isNotEmpty) {
        current = header.toLowerCase();
        buffer.putIfAbsent(current, () => []);
      } else {
        buffer.putIfAbsent(current, () => []).add(line);
      }
    }

    buffer.forEach((section, lines) {
      final joined = lines.join('\n').trim();
      if (joined.isNotEmpty) sections[section] = joined;
    });
    return sections;
  }

  /// Build one [CvChunk] per non-empty section (embeddings filled in later).
  static List<CvChunk> chunk({
    required String candidateName,
    required String sourceFile,
    required Map<String, String> sections,
  }) {
    final slug = sourceFile.replaceAll(RegExp(r'\.pdf$'), '');
    final chunks = <CvChunk>[];
    sections.forEach((section, text) {
      if (text.trim().isEmpty) return;
      chunks.add(CvChunk(
        chunkId: '$slug#$section',
        candidateName: candidateName,
        sourceFile: sourceFile,
        section: section,
        // Prefix the candidate name so a chunk is self-describing in the
        // prompt context (helps the LLM attribute facts correctly).
        text: '$candidateName — ${section.toUpperCase()}\n$text',
        embedding: const [],
      ));
    });
    return chunks;
  }
}
