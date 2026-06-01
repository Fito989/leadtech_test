import 'dart:convert';
import 'dart:io';

import '../models/cv_chunk.dart';

/// The in-memory store of CV chunks. `embeddings.json` is the persisted index;
/// this loads it once at startup into a plain `List<CvChunk>`. See tech-prd
/// §5.6 for why this replaces a vector database at this scale.
class VectorIndex {
  VectorIndex(this.chunks);

  final List<CvChunk> chunks;

  bool get isEmpty => chunks.isEmpty;
  int get length => chunks.length;

  /// Unique candidate names, sorted. The query router validates names it
  /// detects against this roster so it never invents a candidate.
  late final List<String> roster = (chunks.map((c) => c.candidateName).toSet().toList())
    ..sort();

  /// Load the index from a JSON file produced by `tools/ingest.dart`.
  /// Accepts either a bare array or an object with a `chunks` array.
  static VectorIndex load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      // ERR-07: surfaced by /health and at startup with an actionable message.
      throw StateError(
        'Vector index not found at "$path". '
        'Generate CVs and run `dart run tools/ingest.dart` first.',
      );
    }
    final decoded = jsonDecode(file.readAsStringSync());
    final rawList = decoded is Map<String, dynamic>
        ? (decoded['chunks'] as List? ?? const [])
        : decoded as List;
    final chunks = rawList
        .cast<Map<String, dynamic>>()
        .map(CvChunk.fromJson)
        .toList(growable: false);
    return VectorIndex(chunks);
  }

  /// Persist chunks to [path] (used by the ingestion pipeline).
  static void save(String path, List<CvChunk> chunks) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final json = {
      'count': chunks.length,
      'chunks': chunks.map((c) => c.toJson()).toList(),
    };
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }
}
