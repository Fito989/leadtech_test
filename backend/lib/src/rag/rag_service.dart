import '../config/app_config.dart';
import '../gemini/gemini_client.dart';
import '../models/chat.dart';
import '../models/cv_chunk.dart';
import '../models/query_intent.dart';
import '../vector/retriever.dart';
import '../vector/vector_index.dart';
import 'prompt_builder.dart';
import 'query_router.dart';

/// Orchestrates a chat turn: classify → assemble context by strategy →
/// grounded generation → attach sources (tech-prd §5.3).
class RagService {
  RagService({
    required this.config,
    required this.gemini,
    required this.index,
  })  : _retriever = Retriever(index.chunks),
        _router = QueryRouter(gemini, index.roster);

  final AppConfig config;
  final GeminiClient gemini;
  final VectorIndex index;
  final Retriever _retriever;
  final QueryRouter _router;

  Future<ChatResponse> answer(ChatRequest request) async {
    final intent = await _router.classify(request.message, request.history);

    if (intent.intent == Intent.outOfScope) {
      return ChatResponse(
        answer: 'I can only answer questions about the candidate CVs in this dataset.',
        intent: intent.intent.name,
        sources: const [],
        matched: false,
      );
    }

    // Assemble context per strategy.
    List<CvChunk> context;
    List<ScoredChunk>? scored;
    switch (intent.intent) {
      case Intent.candidateSpecific:
      case Intent.comparison:
        context = _retriever.byCandidate(intent.candidateNames);
        // If the named candidate didn't match the roster, fall back to a
        // semantic lookup rather than answering with nothing.
        if (context.isEmpty) {
          scored = await _semantic(request.message);
          context = scored.map((s) => s.chunk).toList();
        }
        break;
      case Intent.listing:
      case Intent.aggregation:
        context = _retriever.all();
        break;
      case Intent.semantic:
      case Intent.outOfScope:
        scored = await _semantic(request.message);
        context = scored.map((s) => s.chunk).toList();
        break;
    }

    final answer = await gemini.chat(
      systemPrompt: PromptBuilder.systemPrompt,
      userMessage: PromptBuilder.userMessage(
        request.message,
        PromptBuilder.contextBlock(context),
      ),
      history: request.history,
    );

    return ChatResponse(
      answer: answer,
      intent: intent.intent.name,
      sources: _sources(intent.intent, context, scored),
      matched: context.isNotEmpty,
    );
  }

  Future<List<ScoredChunk>> _semantic(String message) async {
    final queryVec = await gemini.embedOne(message, taskType: EmbedTask.query);
    return _retriever.search(queryVec, config.topK);
  }

  /// For full-corpus strategies the answer itself enumerates candidates, so we
  /// don't list 28 "sources". For targeted/semantic strategies we surface the
  /// specific CVs used (deduped by file, best score kept).
  List<Source> _sources(Intent intent, List<CvChunk> context, List<ScoredChunk>? scored) {
    if (intent == Intent.listing || intent == Intent.aggregation) return const [];
    final byFile = <String, Source>{};
    if (scored != null) {
      for (final s in scored) {
        final existing = byFile[s.chunk.sourceFile];
        if (existing == null || (existing.score ?? 0) < s.score) {
          byFile[s.chunk.sourceFile] =
              Source(candidate: s.chunk.candidateName, file: s.chunk.sourceFile, score: s.score);
        }
      }
    } else {
      for (final c in context) {
        byFile[c.sourceFile] ??= Source(candidate: c.candidateName, file: c.sourceFile);
      }
    }
    return byFile.values.toList();
  }
}
