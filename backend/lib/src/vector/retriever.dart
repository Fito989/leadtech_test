import 'dart:math';

import '../models/cv_chunk.dart';

/// Cosine similarity between two vectors — the retrieval "engine".
///
/// Measures how closely two vectors point in the same direction: `1.0` means
/// the same meaning, `~0` means unrelated. No package or native lib required.
double cosine(List<double> a, List<double> b) {
  final n = a.length < b.length ? a.length : b.length;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < n; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na == 0 || nb == 0) return 0;
  return dot / (sqrt(na) * sqrt(nb));
}

/// A chunk paired with its similarity score for a given query.
class ScoredChunk {
  ScoredChunk(this.chunk, this.score);
  final CvChunk chunk;
  final double score;
}

/// Selects CV chunks from the in-memory index. Each method backs one of the
/// router's strategies (tech-prd §4 / §5.6).
class Retriever {
  Retriever(this._chunks);
  final List<CvChunk> _chunks;

  /// SEMANTIC strategy: rank every chunk by cosine against [queryVec] and
  /// return the top [k]. This is exactly what a vector DB does internally —
  /// minus the ANN index we don't need at this scale.
  List<ScoredChunk> search(List<double> queryVec, int k) {
    final scored = _chunks
        .map((c) => ScoredChunk(c, cosine(queryVec, c.embedding)))
        .toList()
      ..sort((x, y) => y.score.compareTo(x.score));
    return scored.take(k).toList();
  }

  /// NAME-FILTERED strategy: exact (case-insensitive) match on candidate name,
  /// never similarity — so candidate-specific queries can't return a look-alike.
  List<CvChunk> byCandidate(List<String> names) {
    final wanted = names.map((n) => n.toLowerCase().trim()).toSet();
    return _chunks
        .where((c) => wanted.contains(c.candidateName.toLowerCase().trim()))
        .toList();
  }

  /// FULL-CORPUS strategy: every chunk (listing / aggregation, full recall).
  List<CvChunk> all() => List.unmodifiable(_chunks);
}
