/// One embeddable unit of a CV — a single section of one candidate.
///
/// Chunking per section (rather than fixed-size windows) keeps each chunk a
/// semantically coherent unit and gives clean metadata (`candidateName` +
/// `section`) for the router's name/section filtering.
class CvChunk {
  CvChunk({
    required this.chunkId,
    required this.candidateName,
    required this.sourceFile,
    required this.section,
    required this.text,
    required this.embedding,
  });

  /// Stable hash id (idempotent re-ingestion).
  final String chunkId;
  final String candidateName;

  /// Original PDF filename, e.g. `jane_doe.pdf`.
  final String sourceFile;

  /// summary | experience | education | skills | languages | contact
  final String section;
  final String text;
  final List<double> embedding;

  Map<String, dynamic> toJson() => {
        'chunkId': chunkId,
        'candidateName': candidateName,
        'sourceFile': sourceFile,
        'section': section,
        'text': text,
        'embedding': embedding,
      };

  factory CvChunk.fromJson(Map<String, dynamic> json) => CvChunk(
        chunkId: json['chunkId'] as String,
        candidateName: json['candidateName'] as String,
        sourceFile: json['sourceFile'] as String,
        section: json['section'] as String,
        text: json['text'] as String,
        embedding: (json['embedding'] as List)
            .map((e) => (e as num).toDouble())
            .toList(growable: false),
      );
}
