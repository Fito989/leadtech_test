import 'package:equatable/equatable.dart';

/// A CV that an answer was based on, shown to the user for attribution.
class Source extends Equatable {
  const Source({required this.candidate, required this.file, this.score});

  final String candidate;
  final String file;
  final double? score;

  factory Source.fromJson(Map<String, dynamic> json) => Source(
        candidate: json['candidate'] as String? ?? 'Unknown',
        file: json['file'] as String? ?? '',
        score: (json['score'] as num?)?.toDouble(),
      );

  @override
  List<Object?> get props => [candidate, file, score];
}
