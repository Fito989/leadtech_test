/// Structured representation of one generated CV. Persisted as the sidecar
/// `<slug>.json` next to the PDF, and used both to render the PDF and as the
/// fallback text source during ingestion (tech-prd §6.2).
class ExperienceEntry {
  ExperienceEntry({
    required this.title,
    required this.company,
    required this.period,
    required this.description,
  });

  final String title;
  final String company;
  final String period;
  final String description;

  String toLine() => '$title — $company ($period). $description';

  Map<String, dynamic> toJson() => {
        'title': title,
        'company': company,
        'period': period,
        'description': description,
      };

  factory ExperienceEntry.fromJson(Map<String, dynamic> j) => ExperienceEntry(
        title: j['title'] as String? ?? '',
        company: j['company'] as String? ?? '',
        period: j['period'] as String? ?? '',
        description: j['description'] as String? ?? '',
      );
}

class EducationEntry {
  EducationEntry({
    required this.degree,
    required this.institution,
    required this.period,
  });

  final String degree;
  final String institution;
  final String period;

  String toLine() => '$degree — $institution ($period)';

  Map<String, dynamic> toJson() => {
        'degree': degree,
        'institution': institution,
        'period': period,
      };

  factory EducationEntry.fromJson(Map<String, dynamic> j) => EducationEntry(
        degree: j['degree'] as String? ?? '',
        institution: j['institution'] as String? ?? '',
        period: j['period'] as String? ?? '',
      );
}

class CvData {
  CvData({
    required this.name,
    required this.role,
    required this.email,
    required this.phone,
    required this.location,
    required this.summary,
    required this.experience,
    required this.education,
    required this.skills,
    required this.languages,
  });

  final String name;
  final String role;
  final String email;
  final String phone;
  final String location;
  final String summary;
  final List<ExperienceEntry> experience;
  final List<EducationEntry> education;
  final List<String> skills;
  final List<String> languages;

  /// Filesystem-safe slug derived from the name, e.g. "Jane Doe" -> "jane_doe".
  String get slug => name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// The CV split into the sections the ingestion pipeline chunks on.
  Map<String, String> sections() => {
        'summary': summary,
        'experience': experience.map((e) => e.toLine()).join('\n'),
        'skills': skills.join(', '),
        'education': education.map((e) => e.toLine()).join('\n'),
        'languages': languages.join(', '),
        'contact': '$email | $phone | $location',
      };

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        'email': email,
        'phone': phone,
        'location': location,
        'summary': summary,
        'experience': experience.map((e) => e.toJson()).toList(),
        'education': education.map((e) => e.toJson()).toList(),
        'skills': skills,
        'languages': languages,
      };

  factory CvData.fromJson(Map<String, dynamic> j) => CvData(
        name: j['name'] as String? ?? 'Unknown',
        role: j['role'] as String? ?? '',
        email: j['email'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        location: j['location'] as String? ?? '',
        summary: j['summary'] as String? ?? '',
        experience: (j['experience'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ExperienceEntry.fromJson)
            .toList(),
        education: (j['education'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(EducationEntry.fromJson)
            .toList(),
        skills: (j['skills'] as List? ?? const []).map((e) => e.toString()).toList(),
        languages: (j['languages'] as List? ?? const []).map((e) => e.toString()).toList(),
      );
}
