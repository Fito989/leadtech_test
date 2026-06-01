import 'dart:convert';
import 'dart:io';

import 'package:backend/src/config/app_config.dart';
import 'package:backend/src/gemini/gemini_client.dart';
import 'package:backend/src/generation/cv_generator.dart';
import 'package:backend/src/generation/cv_pdf.dart';
import 'package:backend/src/generation/photo_fetcher.dart';
import 'package:backend/src/models/cv_data.dart';

/// Curated briefs. Canonical demo seeds come first so a small `--count` test
/// still includes Jane Doe and the UPC graduate. Includes several Python
/// candidates, shared schools/skills, and a duplicate first name ("Marc").
const _upc = 'Universitat Politècnica de Catalunya (UPC)';
final List<CvBrief> briefs = [
  // --- canonical seeds ---
  CvBrief(fixedName: 'Jane Doe', role: 'Senior Backend Engineer', seniority: 'Senior', location: 'Barcelona, Spain', mustSkills: ['Python'], mustSchool: _upc),
  CvBrief(role: 'Data Scientist', seniority: 'Mid-level', location: 'Barcelona, Spain', mustSkills: ['Python'], mustSchool: _upc),
  CvBrief(role: 'Machine Learning Engineer', seniority: 'Senior', location: 'Madrid, Spain', mustSkills: ['Python', 'TensorFlow']),
  CvBrief(role: 'Data Engineer', seniority: 'Mid-level', location: 'Remote (EU)', mustSkills: ['Python', 'SQL']),
  CvBrief(fixedName: 'Marc Soler', role: 'DevOps Engineer', seniority: 'Senior', location: 'Barcelona, Spain', mustSkills: ['Python', 'Kubernetes']),
  CvBrief(fixedName: 'Marc Vidal', role: 'Frontend Engineer', seniority: 'Mid-level', location: 'Valencia, Spain'),
  // --- diverse roster ---
  CvBrief(role: 'Fullstack Developer', seniority: 'Senior', location: 'Berlin, Germany'),
  CvBrief(role: 'Flutter Mobile Developer', seniority: 'Mid-level', location: 'Lisbon, Portugal', mustSkills: ['Dart', 'Flutter']),
  CvBrief(role: 'iOS Engineer', seniority: 'Senior', location: 'Amsterdam, Netherlands'),
  CvBrief(role: 'Android Engineer', seniority: 'Mid-level', location: 'Dublin, Ireland'),
  CvBrief(role: 'Product Manager', seniority: 'Senior', location: 'London, UK'),
  CvBrief(role: 'UX/UI Designer', seniority: 'Mid-level', location: 'Paris, France'),
  CvBrief(role: 'QA Automation Engineer', seniority: 'Mid-level', location: 'Barcelona, Spain', contentLanguage: 'Spanish'),
  CvBrief(role: 'Site Reliability Engineer', seniority: 'Senior', location: 'Remote (EU)', mustSkills: ['Kubernetes']),
  CvBrief(role: 'Cloud Solutions Architect', seniority: 'Principal', location: 'Madrid, Spain', mustSkills: ['AWS']),
  CvBrief(role: 'Security Engineer', seniority: 'Senior', location: 'Berlin, Germany'),
  CvBrief(role: 'Data Analyst', seniority: 'Junior', location: 'Valencia, Spain', mustSkills: ['SQL']),
  CvBrief(role: 'Engineering Manager', seniority: 'Lead', location: 'Barcelona, Spain'),
  CvBrief(role: 'Backend Engineer (Java)', seniority: 'Mid-level', location: 'Lisbon, Portugal', mustSkills: ['Java', 'Spring']),
  CvBrief(role: 'React Frontend Engineer', seniority: 'Senior', location: 'Remote (EU)', mustSkills: ['React', 'TypeScript']),
  CvBrief(role: 'Technical Writer', seniority: 'Mid-level', location: 'Dublin, Ireland'),
  CvBrief(role: 'Business Intelligence Analyst', seniority: 'Mid-level', location: 'Madrid, Spain', contentLanguage: 'Spanish'),
  CvBrief(role: 'Game Developer', seniority: 'Junior', location: 'Málaga, Spain', mustSkills: ['C++', 'Unity']),
  CvBrief(role: 'Embedded Systems Engineer', seniority: 'Senior', location: 'Munich, Germany', mustSkills: ['C']),
  CvBrief(role: 'Platform Engineer', seniority: 'Senior', location: 'Barcelona, Spain', mustSkills: ['Go', 'Kubernetes'], mustSchool: _upc),
  CvBrief(role: 'NLP Research Engineer', seniority: 'Senior', location: 'Edinburgh, UK', mustSkills: ['Python', 'PyTorch']),
  CvBrief(role: 'Scrum Master / Agile Coach', seniority: 'Senior', location: 'Rotterdam, Netherlands'),
  CvBrief(role: 'Junior Web Developer', seniority: 'Junior', location: 'Seville, Spain', mustSkills: ['JavaScript']),
];

int? _argInt(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i >= 0 && i + 1 < args.length) return int.tryParse(args[i + 1]);
  return null;
}

Future<void> main(List<String> args) async {
  final count = _argInt(args, '--count') ?? briefs.length;
  final cfg = AppConfig.fromEnv();
  final gemini = GeminiClient(
    apiKey: cfg.geminiApiKey,
    chatModel: cfg.chatModel,
    embedModel: cfg.embedModel,
    embedDim: cfg.embedDim,
    maxAttempts: 6, // free-tier models occasionally 503 under load
  );
  final generator = CvGenerator(gemini);
  final photos = PhotoFetcher();
  final outDir = Directory(cfg.cvsDir)..createSync(recursive: true);

  final selected = briefs.take(count).toList();
  stdout.writeln('Generating ${selected.length} CV(s) into ${outDir.path} ...');

  var ok = 0;
  var withPhoto = 0;
  var skipped = 0;
  final existing = outDir.listSync().map((f) => f.uri.pathSegments.last).toList();
  for (var i = 0; i < selected.length; i++) {
    final n = '${i + 1}/${selected.length}';
    final id = 'cv${(i + 1).toString().padLeft(2, '0')}';
    // Resumable: skip briefs already generated so an interrupted run (e.g. on a
    // quota 429) can resume without wasting requests.
    if (existing.any((f) => f.startsWith('${id}_') && f.endsWith('.pdf'))) {
      skipped++;
      stdout.writeln('  [$n] skip $id (already generated)');
      continue;
    }
    // Retry each CV a few times: free-tier models throw transient 503s.
    CvData? cv;
    Object? lastError;
    for (var attempt = 1; attempt <= 3 && cv == null; attempt++) {
      try {
        cv = await generator.generate(selected[i]);
      } catch (e) {
        lastError = e;
        if (attempt < 3) await Future<void>.delayed(Duration(seconds: 4 * attempt));
      }
    }
    if (cv == null) {
      stdout.writeln('  [$n] FAILED (${selected[i].role}): $lastError');
      continue;
    }
    final photo = await photos.fetch();
    if (photo != null) withPhoto++;
    final pdfBytes = await CvPdf.render(cv, photo);
    final outSlug = '${id}_${cv.slug}';
    File('${outDir.path}/$outSlug.pdf').writeAsBytesSync(pdfBytes);
    File('${outDir.path}/$outSlug.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cv.toJson()));
    ok++;
    stdout.writeln('  [$n] ${cv.name} — ${cv.role} -> $outSlug.pdf${photo == null ? '  (avatar fallback)' : ''}');
    // Pace requests to stay under the free-tier per-minute rate limit.
    await Future<void>.delayed(const Duration(milliseconds: 4000));
  }

  gemini.close();
  photos.close();
  stdout.writeln('Done: $ok generated, $skipped skipped (existing), $withPhoto with AI photos. '
      'Total in ${outDir.path}: ${outDir.listSync().where((f) => f.path.endsWith('.pdf')).length} CVs.');
}
