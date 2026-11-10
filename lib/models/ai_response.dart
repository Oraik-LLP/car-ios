import 'package:flutter/material.dart';

class InvoiceAuditLineItem {
  const InvoiceAuditLineItem({
    required this.item,
    required this.charge,
    required this.assessment,
    required this.reason,
    required this.confidence,
  });

  final String item;
  final String charge;
  final String assessment;
  final String reason;
  final String confidence;

  Map<String, dynamic> toJson() => {
        'item': item,
        'charge': charge,
        'assessment': assessment,
        'reason': reason,
        'confidence': confidence,
      };

  factory InvoiceAuditLineItem.fromJson(Map<String, dynamic> json) {
    return InvoiceAuditLineItem(
      item: json['item'] as String? ?? '',
      charge: json['charge'] as String? ?? '',
      assessment: json['assessment'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      confidence: json['confidence'] as String? ?? 'Low',
    );
  }
}

/// Structured response parsed from Gemini's output.
class AiDiagnosticResponse {
  const AiDiagnosticResponse({
    required this.summary,
    required this.healthScore,
    required this.confidence,
    this.possibleCauses = const [],
    this.recommendations = const [],
    this.subScores = const {},
    this.urgencyNote,
    this.rawText,
    this.mechanicScript,
    this.suggestedQuestion,
    this.documentType,
    this.verdict,
    this.topFlags = const [],
    this.lineItemAudit = const [],
    this.paddingPatternsDetected = const [],
    this.questionsToAsk = const [],
    this.negotiationScript,
    this.limitations,
    this.partialAudit = false,
    this.provider = 'local',
    this.isFallback = false,
    this.errorCode,
  });

  final String summary;

  /// Vehicle diagnostics use 0.0 - 10.0. Invoice audits may come back in mixed
  /// formats and are normalized through invoice-specific getters below.
  final double healthScore;

  /// Vehicle diagnostics usually use 0.0 - 1.0. Invoice audits are normalized
  /// through invoice-specific getters below.
  final double confidence;

  final List<String> possibleCauses;
  final List<String> recommendations;
  final Map<String, double> subScores;

  final String? urgencyNote;
  final String? rawText;
  final String? mechanicScript;
  final String? suggestedQuestion;
  final String? documentType;
  final String? verdict;
  final List<String> topFlags;
  final List<InvoiceAuditLineItem> lineItemAudit;
  final List<String> paddingPatternsDetected;
  final List<String> questionsToAsk;
  final String? negotiationScript;
  final String? limitations;
  final bool partialAudit;
  final String provider;
  final bool isFallback;
  final String? errorCode;

  bool get hasInvoiceAuditData =>
      documentType != null ||
      verdict != null ||
      topFlags.isNotEmpty ||
      lineItemAudit.isNotEmpty ||
      paddingPatternsDetected.isNotEmpty ||
      questionsToAsk.isNotEmpty ||
      (negotiationScript?.trim().isNotEmpty ?? false) ||
      (limitations?.trim().isNotEmpty ?? false);

  bool get isInvoiceAudit => hasInvoiceAuditData;

  bool get hasDisplayableScore =>
      !(isFallback && errorCode == 'parse_failed');

  bool get usesHundredPointScale {
    if (isInvoiceAudit) return true;
    if (healthScore > 10) return true;
    return subScores.values.any((value) => value > 10);
  }

  double get normalizedConfidencePercent {
    final normalized = confidence > 1 ? confidence : confidence * 100;
    return normalized.clamp(0.0, 100.0);
  }

  String get confidenceLabel => '${normalizedConfidencePercent.round()}%';

  double get confidenceProgress =>
      (normalizedConfidencePercent / 100).clamp(0.0, 1.0);

  double get _normalizedHundredPointScore {
    if (!usesHundredPointScale) {
      return (healthScore * 10).clamp(0.0, 100.0);
    }
    final scores = normalizedSubScores.values.toList();
    if (scores.isNotEmpty) {
      final total = scores.fold<double>(0.0, (sum, value) => sum + value);
      return (total / scores.length).clamp(0.0, 100.0);
    }
    return healthScore.clamp(0.0, 100.0);
  }

  double get displayScore {
    if (usesHundredPointScale) {
      return _normalizedHundredPointScore;
    }
    return healthScore.clamp(0.0, 10.0);
  }

  double get displayProgress {
    if (usesHundredPointScale) {
      return (displayScore / 100).clamp(0.0, 1.0);
    }
    return (displayScore / 10).clamp(0.0, 1.0);
  }

  String get displayScoreLabel {
    if (usesHundredPointScale) return displayScore.round().toString();
    return displayScore.toStringAsFixed(1);
  }

  Map<String, double> get normalizedSubScores {
    if (!usesHundredPointScale) return subScores;
    return Map<String, double>.fromEntries(
      subScores.entries.map(
        (entry) => MapEntry(entry.key, entry.value.clamp(0.0, 100.0)),
      ),
    );
  }

  String get healthLabel {
    if (isInvoiceAudit) {
      return verdict ?? 'Invoice Audit';
    }
    if (usesHundredPointScale) {
      if (displayScore >= 80) return 'Good';
      if (displayScore >= 60) return 'Fair';
      if (displayScore >= 40) return 'Needs Attention';
      return 'Critical';
    }
    if (displayScore >= 8) return 'Good';
    if (displayScore >= 6) return 'Fair';
    if (displayScore >= 4) return 'Needs Attention';
    return 'Critical';
  }

  Color get statusColor {
    if (isInvoiceAudit) {
      switch (verdict) {
        case 'Fair':
          return const Color(0xFF4CAF50);
        case 'Mixed':
          return const Color(0xFFFFC107);
        case 'Suspicious':
          return const Color(0xFFFF9800);
        case 'Likely Overpriced':
          return const Color(0xFFFF5252);
        default:
          return const Color(0xFFFF7043);
      }
    }

    if (usesHundredPointScale) {
      if (displayScore >= 80) return const Color(0xFF4CAF50);
      if (displayScore >= 60) return const Color(0xFFFFC107);
      if (displayScore >= 40) return const Color(0xFFFF9800);
      return const Color(0xFFFF5252);
    }

    if (displayScore >= 8) return const Color(0xFF4CAF50);
    if (displayScore >= 6) return const Color(0xFFFFC107);
    if (displayScore >= 4) return const Color(0xFFFF9800);
    return const Color(0xFFFF5252);
  }

  String formatSubScore(double score) {
    if (usesHundredPointScale) {
      return score.round().toString();
    }
    return score.toStringAsFixed(1);
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'health_score': healthScore,
        'confidence': confidence,
        'possible_causes': possibleCauses,
        'recommendations': recommendations,
        'sub_scores': subScores,
        'urgency_note': urgencyNote,
        'mechanic_script': mechanicScript,
        'suggested_question': suggestedQuestion,
        'document_type': documentType,
        'verdict': verdict,
        'top_flags': topFlags,
        'line_item_audit': lineItemAudit.map((item) => item.toJson()).toList(),
        'padding_patterns_detected': paddingPatternsDetected,
        'questions_to_ask': questionsToAsk,
        'negotiation_script': negotiationScript,
        'limitations': limitations,
        'partial_audit': partialAudit,
        'provider': provider,
        'is_fallback': isFallback,
        'error_code': errorCode,
      };

  factory AiDiagnosticResponse.fromJson(Map<String, dynamic> json) =>
      AiDiagnosticResponse(
        summary: json['summary'] as String? ?? '',
        healthScore: (json['health_score'] as num?)?.toDouble() ?? 5.0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
        possibleCauses:
            (json['possible_causes'] as List?)?.cast<String>() ?? const [],
        recommendations:
            (json['recommendations'] as List?)?.cast<String>() ?? const [],
        subScores: _parseSubScores(json['sub_scores']),
        urgencyNote: json['urgency_note'] as String?,
        mechanicScript: json['mechanic_script'] as String?,
        suggestedQuestion: json['suggested_question'] as String?,
        documentType: json['document_type'] as String?,
        verdict: json['verdict'] as String?,
        topFlags: (json['top_flags'] as List?)?.cast<String>() ?? const [],
        lineItemAudit: _parseLineItemAudit(json['line_item_audit']),
        paddingPatternsDetected:
            (json['padding_patterns_detected'] as List?)?.cast<String>() ??
                const [],
        questionsToAsk:
            (json['questions_to_ask'] as List?)?.cast<String>() ?? const [],
        negotiationScript: json['negotiation_script'] as String?,
        limitations: json['limitations'] as String?,
        partialAudit: json['partial_audit'] as bool? ?? false,
        provider: json['provider'] as String? ?? 'local',
        isFallback: json['is_fallback'] as bool? ?? false,
        errorCode: json['error_code'] as String?,
      );

  static Map<String, double> _parseSubScores(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, double>{};
    for (final entry in raw.entries) {
      final key = entry.key?.toString();
      if (key == null) continue;
      final value = entry.value;
      if (value is num) {
        result[key] = value.toDouble();
      } else if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          result[key] = parsed;
        }
      }
    }
    return result;
  }

  static List<InvoiceAuditLineItem> _parseLineItemAudit(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => InvoiceAuditLineItem.fromJson(
            Map<String, dynamic>.from(
              item.map((k, v) => MapEntry(k.toString(), v)),
            ),
          ),
        )
        .toList();
  }

  AiDiagnosticResponse copyWith({
    String? summary,
    double? healthScore,
    double? confidence,
    List<String>? possibleCauses,
    List<String>? recommendations,
    Map<String, double>? subScores,
    String? urgencyNote,
    String? rawText,
    String? mechanicScript,
    String? suggestedQuestion,
    String? documentType,
    String? verdict,
    List<String>? topFlags,
    List<InvoiceAuditLineItem>? lineItemAudit,
    List<String>? paddingPatternsDetected,
    List<String>? questionsToAsk,
    String? negotiationScript,
    String? limitations,
    bool? partialAudit,
    String? provider,
    bool? isFallback,
    String? errorCode,
  }) {
    return AiDiagnosticResponse(
      summary: summary ?? this.summary,
      healthScore: healthScore ?? this.healthScore,
      confidence: confidence ?? this.confidence,
      possibleCauses: possibleCauses ?? this.possibleCauses,
      recommendations: recommendations ?? this.recommendations,
      subScores: subScores ?? this.subScores,
      urgencyNote: urgencyNote ?? this.urgencyNote,
      rawText: rawText ?? this.rawText,
      mechanicScript: mechanicScript ?? this.mechanicScript,
      suggestedQuestion: suggestedQuestion ?? this.suggestedQuestion,
      documentType: documentType ?? this.documentType,
      verdict: verdict ?? this.verdict,
      topFlags: topFlags ?? this.topFlags,
      lineItemAudit: lineItemAudit ?? this.lineItemAudit,
      paddingPatternsDetected:
          paddingPatternsDetected ?? this.paddingPatternsDetected,
      questionsToAsk: questionsToAsk ?? this.questionsToAsk,
      negotiationScript: negotiationScript ?? this.negotiationScript,
      limitations: limitations ?? this.limitations,
      partialAudit: partialAudit ?? this.partialAudit,
      provider: provider ?? this.provider,
      isFallback: isFallback ?? this.isFallback,
      errorCode: errorCode ?? this.errorCode,
    );
  }

  factory AiDiagnosticResponse.fallback(String rawText) => AiDiagnosticResponse(
        summary:
            rawText.length > 300 ? '${rawText.substring(0, 300)}...' : rawText,
        healthScore: 5.0,
        confidence: 0.3,
        possibleCauses: const ['Unable to parse structured response'],
        recommendations: const ['Please consult a mechanic for verification'],
        rawText: rawText,
        provider: 'local',
        isFallback: true,
        errorCode: 'parse_failed',
      );
}
