import 'dart:convert';
import 'dart:io';

import '../gemini/gemini_client.dart';
import '../models/cv_chunk.dart';
import '../models/cv_data.dart';
import 'chunker.dart';
import 'pdf_extractor.dart';

/// Status of ingesting one CV file (ING-07).
class FileStatus {
  FileStatus(this.file, this.chunks, this.usedFallback, [this.error]);
  final String file;
  final int chunks;
  final bool usedFallback;
  final String? error;
}

class IngestionResult {
  IngestionResult(this.chunks, this.statuses);
  final List<CvChunk> chunks;
  final List<FileStatus> statuses;
}

/// Extract → section-chunk → embed for every PDF in a directory.
class IngestionPipeline {
  IngestionPipeline(this._gemini);
  final GeminiClient _gemini;

  /// [cache] maps already-embedded `chunkId` -> embedding, so re-runs reuse
  /// existing vectors and only call the API for new/changed chunks (ING-06).
  /// This keeps re-ingestion well under the embedding rate limit.
  Future<IngestionResult> run(String cvsDir, {Map<String, List<double>> cache = const {}}) async {
    final dir = Directory(cvsDir);
    if (!dir.existsSync()) {
      throw StateError('CVs directory not found: $cvsDir. Run generate_cvs.dart first.');
    }
    final pdfs = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    final allChunks = <CvChunk>[];
    final statuses = <FileStatus>[];

    for (final pdf in pdfs) {
      final fileName = pdf.uri.pathSegments.last;
      try {
        final sidecar = _readSidecar(pdf.path);
        final candidateName = sidecar?.name ?? _slugToName(fileName);

        // Primary: real extraction from the PDF.
        final extracted = await PdfExtractor.extractText(pdf.path);
        var sections = Chunker.sectionsFromText(extracted);
        var usedFallback = false;

        // Fallback: sidecar JSON if extraction was poor (ING-02 / ERR-06).
        if (sections.length < 2 && sidecar != null) {
          sections = sidecar.sections();
          usedFallback = true;
        }

        final chunks = Chunker.chunk(
          candidateName: candidateName,
          sourceFile: fileName,
          sections: sections,
        );

        // Reuse cached embeddings; only call the API for new chunks (ING-06).
        final embeddings = List<List<double>?>.filled(chunks.length, null);
        final toEmbed = <int>[];
        for (var i = 0; i < chunks.length; i++) {
          final cached = cache[chunks[i].chunkId];
          if (cached != null && cached.isNotEmpty) {
            embeddings[i] = cached;
          } else {
            toEmbed.add(i);
          }
        }
        if (toEmbed.isNotEmpty) {
          final vectors = await _gemini.embed(
            [for (final i in toEmbed) chunks[i].text],
            taskType: EmbedTask.document,
          );
          for (var j = 0; j < toEmbed.length; j++) {
            embeddings[toEmbed[j]] = vectors[j];
          }
        }
        for (var i = 0; i < chunks.length; i++) {
          allChunks.add(CvChunk(
            chunkId: chunks[i].chunkId,
            candidateName: chunks[i].candidateName,
            sourceFile: chunks[i].sourceFile,
            section: chunks[i].section,
            text: chunks[i].text,
            embedding: embeddings[i]!,
          ));
        }
        statuses.add(FileStatus(fileName, chunks.length, usedFallback));
      } catch (e) {
        statuses.add(FileStatus(fileName, 0, false, e.toString()));
      }
    }
    return IngestionResult(allChunks, statuses);
  }

  CvData? _readSidecar(String pdfPath) {
    final jsonPath = pdfPath.replaceAll(RegExp(r'\.pdf$'), '.json');
    final file = File(jsonPath);
    if (!file.existsSync()) return null;
    try {
      return CvData.fromJson(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String _slugToName(String fileName) {
    final slug = fileName.replaceAll(RegExp(r'\.pdf$'), '');
    return slug
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
