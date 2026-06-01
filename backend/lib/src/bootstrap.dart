import 'config/app_config.dart';
import 'gemini/gemini_client.dart';
import 'rag/rag_service.dart';
import 'vector/vector_index.dart';

/// Process-wide singletons, built once and shared across requests via DI.
/// Loads the vector index at startup but tolerates its absence so `/health`
/// can report "not initialized" instead of crashing the server (ERR-07).
class Backend {
  Backend._() {
    config = AppConfig.fromEnv();
    gemini = GeminiClient(
      apiKey: config.geminiApiKey,
      chatModel: config.chatModel,
      embedModel: config.embedModel,
      embedDim: config.embedDim,
    );
    try {
      final loaded = VectorIndex.load(config.indexPath);
      index = loaded;
      rag = RagService(config: config, gemini: gemini, index: loaded);
    } catch (e) {
      indexError = e.toString();
    }
  }

  late final AppConfig config;
  late final GeminiClient gemini;
  VectorIndex? index;
  RagService? rag;
  String? indexError;

  bool get ready => rag != null;

  static Backend? _instance;
  static Backend get instance => _instance ??= Backend._();
}
