import 'dart:io';

import 'package:dotenv/dotenv.dart';

/// Runtime configuration loaded from the environment / `.env` file.
///
/// The server and the CLI tools both run from the `backend/` directory, so
/// `.env` is expected to live there. We still walk one directory up as a
/// fallback so the config keeps working if someone runs from the repo root.
class AppConfig {
  AppConfig({
    required this.geminiApiKey,
    required this.chatModel,
    required this.embedModel,
    required this.embedDim,
    required this.topK,
    required this.indexPath,
    required this.cvsDir,
  });

  final String geminiApiKey;
  final String chatModel;
  final String embedModel;
  final int embedDim;
  final int topK;
  final String indexPath;
  final String cvsDir;

  factory AppConfig.fromEnv() {
    final env = DotEnv(includePlatformEnvironment: true);
    for (final candidate in ['.env', '../.env']) {
      if (File(candidate).existsSync()) {
        env.load([candidate]);
        break;
      }
    }

    final key = env['GEMINI_API_KEY'] ?? '';
    if (key.isEmpty) {
      // Fail fast with an actionable message rather than emitting cryptic
      // 401s on the first API call (ERR-02).
      throw StateError(
        'GEMINI_API_KEY is not set. Copy backend/.env.example to backend/.env '
        'and add your key (https://aistudio.google.com/apikey).',
      );
    }

    return AppConfig(
      geminiApiKey: key,
      chatModel: env['GEMINI_CHAT_MODEL'] ?? 'gemini-2.5-flash-lite',
      embedModel: env['GEMINI_EMBED_MODEL'] ?? 'gemini-embedding-2',
      embedDim: int.tryParse(env['EMBED_DIM'] ?? '') ?? 768,
      topK: int.tryParse(env['TOP_K'] ?? '') ?? 6,
      indexPath: env['INDEX_PATH'] ?? 'data/index/embeddings.json',
      cvsDir: env['CVS_DIR'] ?? 'data/cvs',
    );
  }
}
