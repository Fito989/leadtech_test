import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/cv_data.dart';

/// Renders a [CvData] into a realistic one-page CV PDF.
///
/// Section titles are upper-cased (SUMMARY, EXPERIENCE, …) so the ingestion
/// pipeline can split the extracted text back into sections (tech-prd §6.3).
class CvPdf {
  static Future<Uint8List> render(CvData cv, Uint8List? photo) async {
    final doc = pw.Document();

    final pw.Widget avatar = photo != null
        ? pw.Image(pw.MemoryImage(photo), width: 96, height: 96, fit: pw.BoxFit.cover)
        : _initialsAvatar(cv.name);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(width: 96, height: 96, child: avatar),
              pw.SizedBox(width: 18),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(_safe(cv.name),
                        style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text(_safe(cv.role),
                        style: pw.TextStyle(fontSize: 13, color: PdfColors.blueGrey700)),
                    pw.SizedBox(height: 6),
                    pw.Text(_safe('${cv.email}   |   ${cv.phone}   |   ${cv.location}'),
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          ..._section('SUMMARY', [
            pw.Text(_safe(cv.summary), style: const pw.TextStyle(fontSize: 10, lineSpacing: 2)),
          ]),
          ..._section('EXPERIENCE', cv.experience.map(_experience).toList()),
          ..._section('SKILLS', [
            pw.Text(_safe(cv.skills.join('  •  ')), style: const pw.TextStyle(fontSize: 10)),
          ]),
          ..._section('EDUCATION', [
            for (final e in cv.education)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(_safe(e.toLine()), style: const pw.TextStyle(fontSize: 10)),
              ),
          ]),
          ..._section('LANGUAGES', [
            pw.Text(_safe(cv.languages.join('  •  ')), style: const pw.TextStyle(fontSize: 10)),
          ]),
        ],
      ),
    );

    return doc.save();
  }

  static List<pw.Widget> _section(String title, List<pw.Widget> body) => [
        pw.SizedBox(height: 12),
        pw.Text(title,
            style: pw.TextStyle(
                fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
        pw.Divider(thickness: 0.8, color: PdfColors.blue200),
        ...body,
      ];

  static pw.Widget _experience(ExperienceEntry e) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_safe('${e.title} — ${e.company}'),
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
            pw.Text(_safe(e.period),
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 1),
            pw.Text(_safe(e.description), style: const pw.TextStyle(fontSize: 9.5, lineSpacing: 1.5)),
          ],
        ),
      );

  static pw.Widget _initialsAvatar(String name) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0])
        .take(2)
        .join()
        .toUpperCase();
    return pw.Container(
      color: PdfColors.blueGrey300,
      alignment: pw.Alignment.center,
      child: pw.Text(initials,
          style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
    );
  }

  /// The built-in PDF fonts cover WinAnsi/Latin-1. Map common "smart"
  /// punctuation to ASCII and drop anything outside Latin-1 so a stray glyph
  /// (emoji, CJK) can never crash rendering.
  static String _safe(String s) {
    const replace = {
      '‘': "'", '’': "'", '‚': "'",
      '“': '"', '”': '"',
      '–': '-', '—': '-', '−': '-',
      '•': '-', '…': '...', ' ': ' ',
    };
    final sb = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (replace.containsKey(ch)) {
        sb.write(replace[ch]);
      } else if (rune <= 0xFF) {
        sb.write(ch);
      }
      // else: unsupported glyph dropped
    }
    return sb.toString();
  }
}
