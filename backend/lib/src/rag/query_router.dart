import '../gemini/gemini_client.dart';
import '../models/chat.dart';
import '../models/query_intent.dart';

/// Classifies a query into an [Intent] and extracts candidate names, validated
/// against the known roster. This is the hero feature (tech-prd §4): it lets us
/// route to full-corpus / name-filtered / vector retrieval per query type.
class QueryRouter {
  QueryRouter(this._gemini, this._roster);

  final GeminiClient _gemini;
  final List<String> _roster;

  static final Map<String, dynamic> _schema = {
    'type': 'OBJECT',
    'properties': {
      'intent': {
        'type': 'STRING',
        'enum': ['candidateSpecific', 'listing', 'aggregation', 'comparison', 'semantic', 'outOfScope'],
      },
      'candidateNames': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
    },
    'required': ['intent'],
  };

  static const _system = '''
You classify a recruiter's question about a FIXED set of candidate CVs into exactly one intent, and extract any candidate names it mentions.

Intents:
- candidateSpecific: about ONE specific named candidate ("summarise Jane Doe", "where did John work?").
- comparison: comparing TWO OR MORE named candidates ("compare Jane and John").
- listing: asks which/who candidates match a criterion ("who knows Python?", "which graduated from UPC?").
- aggregation: counting, ranking, or "top N" ("how many know React?", "top 3 backend candidates").
- semantic: open-ended search by experience/skill that isn't a single clean attribute ("who has led large migrations?").
- outOfScope: not about these candidates at all (weather, math, general chit-chat).

Only extract candidateNames that plausibly refer to entries in the provided roster. Return JSON matching the schema.''';

  Future<QueryIntent> classify(String message, List<ChatTurn> history) async {
    try {
      final json = await _gemini.generateJson(
        systemPrompt: _system,
        userMessage: _userMessage(message, history),
        schema: _schema,
      );
      final raw = QueryIntent.fromJson(json);
      final validated = _validateNames(raw.candidateNames);
      return QueryIntent(intent: raw.intent, candidateNames: validated);
    } catch (_) {
      // Classifier unavailable (e.g. 503) — degrade gracefully to heuristics.
      return _heuristic(message);
    }
  }

  String _userMessage(String message, List<ChatTurn> history) {
    final recent = history.length > 4 ? history.sublist(history.length - 4) : history;
    final convo = recent.map((t) => '${t.role}: ${t.content}').join('\n');
    return [
      'Roster: ${_roster.join(', ')}',
      if (convo.isNotEmpty) 'Conversation so far:\n$convo',
      'Question: $message',
    ].join('\n\n');
  }

  /// Keep only names that map to a roster entry; return canonical roster names.
  List<String> _validateNames(List<String> mentioned) {
    final out = <String>{};
    for (final m in mentioned) {
      for (final r in _matchRoster(m)) {
        out.add(r);
      }
    }
    return out.toList();
  }

  /// Roster entries matching a mentioned string: exact, containment either way,
  /// or a shared name token (enables the ambiguous-first-name case, UC-24).
  List<String> _matchRoster(String mentioned) {
    final m = mentioned.toLowerCase().trim();
    if (m.isEmpty) return const [];
    final matches = <String>[];
    for (final r in _roster) {
      final rl = r.toLowerCase();
      if (rl == m || rl.contains(m) || m.contains(rl)) {
        matches.add(r);
        continue;
      }
      final mTokens = m.split(RegExp(r'\s+')).where((t) => t.length >= 3).toSet();
      final rTokens = rl.split(RegExp(r'\s+')).where((t) => t.length >= 3).toSet();
      if (mTokens.intersection(rTokens).isNotEmpty) matches.add(r);
    }
    return matches;
  }

  QueryIntent _heuristic(String message) {
    final m = message.toLowerCase();
    final names = _rosterNamesIn(m);
    if (RegExp(r'\bhow many\b|\bcount\b|\btop \d|\brank').hasMatch(m)) {
      return QueryIntent(intent: Intent.aggregation, candidateNames: names);
    }
    if (m.contains('compare') || names.length >= 2) {
      return QueryIntent(intent: Intent.comparison, candidateNames: names);
    }
    if (names.isNotEmpty) {
      return QueryIntent(intent: Intent.candidateSpecific, candidateNames: names);
    }
    if (RegExp(r'^\s*(who|which|list|whose)\b').hasMatch(m)) {
      return QueryIntent(intent: Intent.listing);
    }
    return QueryIntent(intent: Intent.semantic);
  }

  List<String> _rosterNamesIn(String lowerMessage) {
    final found = <String>[];
    for (final r in _roster) {
      final tokens = r.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length >= 3);
      if (tokens.any((t) => RegExp('\\b$t\\b').hasMatch(lowerMessage))) found.add(r);
    }
    return found;
  }
}
