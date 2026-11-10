enum DiagnosticType { urgent, photo, invoiceAudit, live, obdIdle, obdDrive }
enum Severity { low, medium, high, critical }

class SymptomCategory {
  const SymptomCategory({required this.label, required this.icon, required this.symptoms});
  final String label;
  final String icon;
  final List<String> symptoms;
}

const kSymptomCategories = [
  SymptomCategory(
    label: 'Engine',
    icon: '🔧',
    symptoms: [
      'Check engine light on',
      'Engine misfiring',
      'Rough idle',
      'Engine overheating',
      'Power loss',
      'Unusual engine noise',
      'Engine stalling',
      'Excessive smoke',
    ],
  ),
  SymptomCategory(
    label: 'Brakes',
    icon: '🛑',
    symptoms: [
      'Squeaking/grinding noise',
      'Spongy brake pedal',
      'Pulling to one side',
      'Vibration when braking',
      'Brake warning light',
      'Longer stopping distance',
    ],
  ),
  SymptomCategory(
    label: 'Transmission',
    icon: '⚙️',
    symptoms: [
      'Gear slipping',
      'Hard shifting',
      'Grinding noise in gear',
      'Transmission fluid leak',
      'Delayed engagement',
      'Won\'t go into gear',
    ],
  ),
  SymptomCategory(
    label: 'Suspension',
    icon: '🔩',
    symptoms: [
      'Bumpy ride',
      'Car pulling to one side',
      'Uneven tire wear',
      'Clunking over bumps',
      'Nose diving on brakes',
      'Steering wheel vibration',
    ],
  ),
  SymptomCategory(
    label: 'Electrical',
    icon: '⚡',
    symptoms: [
      'Battery draining fast',
      'Lights flickering',
      'Starter not engaging',
      'Dashboard warning lights',
      'Power windows stuck',
      'Fuse blowing repeatedly',
    ],
  ),
  SymptomCategory(
    label: 'AC / Climate',
    icon: '❄️',
    symptoms: [
      'Not cooling',
      'Bad odor from vents',
      'Unusual noise when AC on',
      'Fogging windshield',
      'Refrigerant leak',
    ],
  ),
];

class DiagnosticSession {
  DiagnosticSession({
    required this.id,
    required this.vehicleId,
    required this.type,
    this.symptoms = const [],
    this.severity = Severity.medium,
    this.description,
    this.imageUrls = const [],
    this.aiResponse,
    this.aiResponseJson,
    this.contextJson,
    this.healthScore,
    this.vehicleName,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String vehicleId;
  final DiagnosticType type;
  final List<String> symptoms;
  final Severity severity;
  final String? description;
  final List<String> imageUrls;
  final String? aiResponse;
  /// Full AI response stored as a JSON map for report detail rendering.
  final Map<String, dynamic>? aiResponseJson;
  final Map<String, dynamic>? contextJson;
  final double? healthScore;
  final String? vehicleName;
  final DateTime createdAt;

  bool get isObd =>
      type == DiagnosticType.obdIdle || type == DiagnosticType.obdDrive;

  bool get supportsPdfExport => !isObd;

  String get severityLabel => switch (severity) {
        Severity.low => 'Low',
        Severity.medium => 'Medium',
        Severity.high => 'High',
        Severity.critical => 'Critical',
      };

  String get typeTitle => switch (type) {
        DiagnosticType.urgent => 'Urgent Diagnosis',
        DiagnosticType.photo => 'Photo Diagnosis',
        DiagnosticType.invoiceAudit => 'Invoice Audit',
        DiagnosticType.live => 'Gemini Live',
        DiagnosticType.obdIdle => 'OBD Idle Scan',
        DiagnosticType.obdDrive => 'OBD Drive Scan',
      };

  String get dateLabel {
    final d = createdAt;
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  String get timeLabel {
    final h = createdAt.hour.toString().padLeft(2, '0');
    final m = createdAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'vehicle_id': vehicleId,
        'type': type.name,
        'symptoms': symptoms,
        'severity': severity.name,
        'description': description,
        'image_urls': imageUrls,
        'ai_response': aiResponse,
        'ai_response_json': aiResponseJson,
        'context_json': contextJson,
        'health_score': healthScore,
        'vehicle_name': vehicleName,
        'created_at': createdAt.toIso8601String(),
      };

  factory DiagnosticSession.fromJson(Map<String, dynamic> j) =>
      DiagnosticSession(
        id: j['id'] as String,
        vehicleId: j['vehicle_id'] as String,
        type: DiagnosticType.values.byName(j['type'] as String),
        symptoms: (j['symptoms'] as List?)?.cast<String>() ?? [],
        severity:
            Severity.values.byName(j['severity'] as String? ?? 'medium'),
        description: j['description'] as String?,
        imageUrls: (j['image_urls'] as List?)?.cast<String>() ?? [],
        aiResponse: j['ai_response'] as String?,
        aiResponseJson: j['ai_response_json'] is Map
            ? Map<String, dynamic>.from(j['ai_response_json'] as Map)
            : null,
        contextJson: j['context_json'] is Map
            ? Map<String, dynamic>.from(j['context_json'] as Map)
            : null,
        healthScore: (j['health_score'] as num?)?.toDouble(),
        vehicleName: j['vehicle_name'] as String?,
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
      );
}
