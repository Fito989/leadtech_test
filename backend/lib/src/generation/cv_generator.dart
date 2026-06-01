import '../gemini/gemini_client.dart';
import '../models/cv_data.dart';

/// Constraints for one CV to generate. Canonical seeds (a fixed name, a
/// required school, required skills) let us guarantee the golden demo queries
/// return real results (tech-prd §6.5).
class CvBrief {
  CvBrief({
    required this.role,
    required this.seniority,
    required this.location,
    this.fixedName,
    this.mustSkills = const [],
    this.mustSchool,
    this.contentLanguage = 'English',
  });

  final String role;
  final String seniority;
  final String location;
  final String? fixedName;
  final List<String> mustSkills;
  final String? mustSchool;
  final String contentLanguage;
}

/// Turns a [CvBrief] into structured [CvData] using `gemini-3.5-flash` in
/// JSON mode.
class CvGenerator {
  CvGenerator(this._gemini);
  final GeminiClient _gemini;

  static const _systemPrompt =
      'You generate realistic but entirely FICTIONAL CV/resume data for a demo '
      'dataset. Never use real, identifiable people. Use only standard Latin '
      'characters (no emoji). Make content internally consistent: employment '
      'periods and the summary should match the stated seniority. Return JSON '
      'that matches the provided schema exactly.';

  static final Map<String, dynamic> _schema = {
    'type': 'OBJECT',
    'properties': {
      'name': {'type': 'STRING'},
      'role': {'type': 'STRING'},
      'email': {'type': 'STRING'},
      'phone': {'type': 'STRING'},
      'location': {'type': 'STRING'},
      'summary': {'type': 'STRING'},
      'experience': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'title': {'type': 'STRING'},
            'company': {'type': 'STRING'},
            'period': {'type': 'STRING'},
            'description': {'type': 'STRING'},
          },
          'required': ['title', 'company', 'period', 'description'],
        },
      },
      'education': {
        'type': 'ARRAY',
        'items': {
          'type': 'OBJECT',
          'properties': {
            'degree': {'type': 'STRING'},
            'institution': {'type': 'STRING'},
            'period': {'type': 'STRING'},
          },
          'required': ['degree', 'institution', 'period'],
        },
      },
      'skills': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
      'languages': {'type': 'ARRAY', 'items': {'type': 'STRING'}},
    },
    'required': [
      'name', 'role', 'email', 'phone', 'location', 'summary',
      'experience', 'education', 'skills', 'languages',
    ],
  };

  Future<CvData> generate(CvBrief brief) async {
    final json = await _gemini.generateJson(
      systemPrompt: _systemPrompt,
      userMessage: _prompt(brief),
      schema: _schema,
    );
    var cv = CvData.fromJson(json);

    // Hard-enforce canonical constraints so the dataset is guaranteed correct
    // regardless of model drift.
    if (brief.fixedName != null && brief.fixedName!.trim().isNotEmpty) {
      cv = _withName(cv, brief.fixedName!.trim());
    }
    return cv;
  }

  String _prompt(CvBrief b) {
    final lines = <String>[
      'Generate one fictional CV with these constraints:',
      '- Role / target position: ${b.role}',
      '- Seniority: ${b.seniority}',
      '- Based in: ${b.location}',
      '- Write the CV content in: ${b.contentLanguage}',
      '- 3 to 4 work experience entries with realistic companies and date ranges.',
      '- 1 to 2 education entries.',
      '- 8 to 12 concrete skills (tools, languages, frameworks).',
      '- 2 to 3 spoken languages with proficiency.',
      '- A 2-3 sentence professional summary.',
      '- A plausible fictional email and phone.',
      '- Use a DISTINCTIVE, uncommon full name appropriate to the location. '
          'Avoid very common names (NOT "Alex Johnson", "Elena Garcia", "Maria Garcia", "John Smith"). '
          'Vary cultural origin across candidates.',
    ];
    if (b.fixedName != null) lines.add('- The candidate MUST be named exactly "${b.fixedName}".');
    if (b.mustSkills.isNotEmpty) {
      lines.add('- The skills list MUST explicitly include: ${b.mustSkills.join(', ')}.');
    }
    if (b.mustSchool != null) {
      lines.add('- One education entry MUST be from "${b.mustSchool}".');
    }
    return lines.join('\n');
  }

  CvData _withName(CvData cv, String name) => CvData(
        name: name,
        role: cv.role,
        email: cv.email,
        phone: cv.phone,
        location: cv.location,
        summary: cv.summary,
        experience: cv.experience,
        education: cv.education,
        skills: cv.skills,
        languages: cv.languages,
      );
}
