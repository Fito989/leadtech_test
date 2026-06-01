import 'dart:io';

import 'package:backend/src/config/app_config.dart';
import 'package:backend/src/gemini/gemini_client.dart';
import 'package:backend/src/ingestion/ingestion_pipeline.dart';
import 'package:backend/src/vector/vector_index.dart';

/// Builds the vector index: extract → chunk → embed every CV under CVS_DIR,
/// then write data/index/embeddings.json. Prints per-file status (ING-07).
Future<void> main(List<String> args) async {
  final cfg = AppConfig.fromEnv();
  final gemini = GeminiClient(
    apiKey: cfg.geminiApiKey,
    chatModel: cfg.chatModel,
    embedModel: cfg.embedModel,
    embedDim: cfg.embedDim,
  );

  // Reuse embeddings from a previous run so we only call the API for new
  // chunks (resumable; keeps us under the embedding rate limit).
  final cache = <String, List<double>>{};
  if (File(cfg.indexPath).existsSync()) {
    for (final c in VectorIndex.load(cfg.indexPath).chunks) {
      if (c.embedding.isNotEmpty) cache[c.chunkId] = c.embedding;
    }
    stdout.writeln('Reusing ${cache.length} embeddings from existing index.');
  }

  stdout.writeln('Ingesting CVs from ${cfg.cvsDir} ...');
  final pipeline = IngestionPipeline(gemini);
  final result = await pipeline.run(cfg.cvsDir, cache: cache);

  var ok = 0;
  var failed = 0;
  for (final s in result.statuses) {
    if (s.error != null) {
      failed++;
      stdout.writeln('  ✗ ${s.file}: ${s.error}');
    } else {
      ok++;
      final tag = s.usedFallback ? ' (sidecar fallback)' : '';
      stdout.writeln('  ✓ ${s.file}: ${s.chunks} chunks$tag');
    }
  }

  VectorIndex.save(cfg.indexPath, result.chunks);
  gemini.close();

  stdout.writeln('---');
  stdout.writeln('Ingested $ok file(s), $failed failed. '
      '${result.chunks.length} chunks written to ${cfg.indexPath}.');
}
