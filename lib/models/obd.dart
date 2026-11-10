enum ObdSuiteState {
  disconnected,
  connecting,
  initializing,
  liveReady,
  idleRunning,
  driveWaiting,
  driveRunning,
  finalizing,
  interrupted,
  error,
}

enum ObdScanKind { idle, drive }

enum ObdCompletionReason {
  completed,
  bluetoothDisconnect,
  vehicleMoved,
  cancelled,
  backgroundInterrupted,
}

class BluetoothTarget {
  const BluetoothTarget({
    required this.name,
    required this.address,
  });

  final String name;
  final String address;

  String get displayName => name.isEmpty ? address : '$name ($address)';

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
      };

  factory BluetoothTarget.fromMap(Map<String, String> map) {
    return BluetoothTarget(
      name: map['name'] ?? 'Unknown',
      address: map['address'] ?? 'Unknown',
    );
  }

  factory BluetoothTarget.fromJson(Map<String, dynamic> json) {
    return BluetoothTarget(
      name: json['name'] as String? ?? 'Unknown',
      address: json['address'] as String? ?? 'Unknown',
    );
  }
}

class ObdStaticSnapshot {
  const ObdStaticSnapshot({
    this.vin,
    this.storedDtcs = const [],
    this.pendingDtcs = const [],
    this.controlModuleVoltage,
    this.distanceSinceCodesClearedKm,
    this.ambientAirTempC,
    this.capturedAt,
  });

  final String? vin;
  final List<String> storedDtcs;
  final List<String> pendingDtcs;
  final double? controlModuleVoltage;
  final int? distanceSinceCodesClearedKm;
  final double? ambientAirTempC;
  final DateTime? capturedAt;

  bool get hasAnyData =>
      (vin?.trim().isNotEmpty ?? false) ||
      storedDtcs.isNotEmpty ||
      pendingDtcs.isNotEmpty ||
      controlModuleVoltage != null ||
      distanceSinceCodesClearedKm != null ||
      ambientAirTempC != null;

  ObdStaticSnapshot copyWith({
    String? vin,
    List<String>? storedDtcs,
    List<String>? pendingDtcs,
    double? controlModuleVoltage,
    int? distanceSinceCodesClearedKm,
    double? ambientAirTempC,
    DateTime? capturedAt,
  }) {
    return ObdStaticSnapshot(
      vin: vin ?? this.vin,
      storedDtcs: storedDtcs ?? this.storedDtcs,
      pendingDtcs: pendingDtcs ?? this.pendingDtcs,
      controlModuleVoltage: controlModuleVoltage ?? this.controlModuleVoltage,
      distanceSinceCodesClearedKm: distanceSinceCodesClearedKm ??
          this.distanceSinceCodesClearedKm,
      ambientAirTempC: ambientAirTempC ?? this.ambientAirTempC,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'vin': vin,
        'stored_dtcs': storedDtcs,
        'pending_dtcs': pendingDtcs,
        'control_module_voltage': controlModuleVoltage,
        'distance_since_codes_cleared_km': distanceSinceCodesClearedKm,
        'ambient_air_temp_c': ambientAirTempC,
        'captured_at': capturedAt?.toIso8601String(),
      };

  factory ObdStaticSnapshot.fromJson(Map<String, dynamic> json) {
    return ObdStaticSnapshot(
      vin: json['vin'] as String?,
      storedDtcs: (json['stored_dtcs'] as List?)?.cast<String>() ?? const [],
      pendingDtcs:
          (json['pending_dtcs'] as List?)?.cast<String>() ?? const [],
      controlModuleVoltage:
          (json['control_module_voltage'] as num?)?.toDouble(),
      distanceSinceCodesClearedKm:
          (json['distance_since_codes_cleared_km'] as num?)?.toInt(),
      ambientAirTempC: (json['ambient_air_temp_c'] as num?)?.toDouble(),
      capturedAt: DateTime.tryParse(json['captured_at'] as String? ?? ''),
    );
  }
}

class ObdLiveVitals {
  const ObdLiveVitals({
    this.rpm,
    this.speedKph,
    this.coolantTempC,
    this.updatedAt,
  });

  final double? rpm;
  final int? speedKph;
  final double? coolantTempC;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'rpm': rpm,
        'speed_kph': speedKph,
        'coolant_temp_c': coolantTempC,
        'updated_at': updatedAt?.toIso8601String(),
      };

  factory ObdLiveVitals.fromJson(Map<String, dynamic> json) {
    return ObdLiveVitals(
      rpm: (json['rpm'] as num?)?.toDouble(),
      speedKph: (json['speed_kph'] as num?)?.toInt(),
      coolantTempC: (json['coolant_temp_c'] as num?)?.toDouble(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }
}

class ObdSampleFrame {
  const ObdSampleFrame({
    required this.timestamp,
    required this.elapsedMs,
    required this.values,
  });

  final DateTime timestamp;
  final int elapsedMs;
  final Map<String, double> values;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'elapsed_ms': elapsedMs,
        'values': values,
      };

  factory ObdSampleFrame.fromJson(Map<String, dynamic> json) {
    return ObdSampleFrame(
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      values: (json['values'] as Map? ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(
          key.toString(),
          (value as num).toDouble(),
        ),
      ),
    );
  }
}

class ObdMetricStats {
  const ObdMetricStats({
    required this.minimum,
    required this.maximum,
    required this.average,
    required this.sampleCount,
    required this.droppedSampleCount,
  });

  final double minimum;
  final double maximum;
  final double average;
  final int sampleCount;
  final int droppedSampleCount;

  Map<String, dynamic> toJson() => {
        'minimum': minimum,
        'maximum': maximum,
        'average': average,
        'sample_count': sampleCount,
        'dropped_sample_count': droppedSampleCount,
      };

  factory ObdMetricStats.fromJson(Map<String, dynamic> json) {
    return ObdMetricStats(
      minimum: (json['minimum'] as num?)?.toDouble() ?? 0,
      maximum: (json['maximum'] as num?)?.toDouble() ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0,
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
      droppedSampleCount:
          (json['dropped_sample_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ObdDriveSnapshotFrame {
  const ObdDriveSnapshotFrame({
    required this.elapsedMs,
    required this.values,
  });

  final int elapsedMs;
  final Map<String, double> values;

  Map<String, dynamic> toJson() => {
        'elapsed_ms': elapsedMs,
        'values': values,
      };

  factory ObdDriveSnapshotFrame.fromJson(Map<String, dynamic> json) {
    return ObdDriveSnapshotFrame(
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt() ?? 0,
      values: (json['values'] as Map? ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(
          key.toString(),
          (value as num).toDouble(),
        ),
      ),
    );
  }
}

class ObdProcessedScan {
  const ObdProcessedScan({
    required this.kind,
    this.idleStats = const {},
    this.driveTimeline = const [],
    this.timelineSummary = const {},
    this.sampleCount = 0,
  });

  final ObdScanKind kind;
  final Map<String, ObdMetricStats> idleStats;
  final List<ObdDriveSnapshotFrame> driveTimeline;
  final Map<String, ObdMetricStats> timelineSummary;
  final int sampleCount;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'idle_stats': idleStats.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'drive_timeline': driveTimeline.map((frame) => frame.toJson()).toList(),
        'timeline_summary': timelineSummary.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
        'sample_count': sampleCount,
      };

  factory ObdProcessedScan.fromJson(Map<String, dynamic> json) {
    return ObdProcessedScan(
      kind: ObdScanKind.values.byName(
        json['kind'] as String? ?? ObdScanKind.idle.name,
      ),
      idleStats: (json['idle_stats'] as Map? ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(
          key.toString(),
          ObdMetricStats.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      driveTimeline: (json['drive_timeline'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => ObdDriveSnapshotFrame.fromJson(
                  Map<String, dynamic>.from(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                ),
              )
              .toList() ??
          const [],
      timelineSummary:
          (json['timeline_summary'] as Map? ?? const <String, dynamic>{}).map(
        (key, value) => MapEntry(
          key.toString(),
          ObdMetricStats.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      sampleCount: (json['sample_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ObdScanRecord {
  const ObdScanRecord({
    required this.kind,
    required this.isPartial,
    required this.completionReason,
    required this.targetDurationSeconds,
    required this.capturedDurationSeconds,
    required this.staticSnapshot,
    required this.processedScan,
  });

  final ObdScanKind kind;
  final bool isPartial;
  final ObdCompletionReason completionReason;
  final int targetDurationSeconds;
  final int capturedDurationSeconds;
  final ObdStaticSnapshot staticSnapshot;
  final ObdProcessedScan processedScan;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'is_partial': isPartial,
        'completion_reason': completionReason.name,
        'target_duration_seconds': targetDurationSeconds,
        'captured_duration_seconds': capturedDurationSeconds,
        'static_snapshot': staticSnapshot.toJson(),
        'processed_scan': processedScan.toJson(),
      };

  factory ObdScanRecord.fromJson(Map<String, dynamic> json) {
    return ObdScanRecord(
      kind: ObdScanKind.values.byName(
        json['kind'] as String? ?? ObdScanKind.idle.name,
      ),
      isPartial: json['is_partial'] as bool? ?? false,
      completionReason: ObdCompletionReason.values.byName(
        json['completion_reason'] as String? ??
            ObdCompletionReason.completed.name,
      ),
      targetDurationSeconds:
          (json['target_duration_seconds'] as num?)?.toInt() ?? 0,
      capturedDurationSeconds:
          (json['captured_duration_seconds'] as num?)?.toInt() ?? 0,
      staticSnapshot: ObdStaticSnapshot.fromJson(
        Map<String, dynamic>.from(
          (json['static_snapshot'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      processedScan: ObdProcessedScan.fromJson(
        Map<String, dynamic>.from(
          (json['processed_scan'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
    );
  }
}

class ObdInsightRecord {
  const ObdInsightRecord({
    required this.vehicleId,
    required this.kind,
    required this.sessionId,
    required this.summary,
    required this.aiResponseJson,
    required this.record,
    required this.createdAt,
  });

  final String vehicleId;
  final ObdScanKind kind;
  final String sessionId;
  final String summary;
  final Map<String, dynamic> aiResponseJson;
  final ObdScanRecord record;
  final DateTime createdAt;

  bool get isPartial => record.isPartial;
  int get capturedDurationSeconds => record.capturedDurationSeconds;
  int get targetDurationSeconds => record.targetDurationSeconds;

  Map<String, dynamic> toJson() => {
        'vehicle_id': vehicleId,
        'kind': kind.name,
        'session_id': sessionId,
        'summary': summary,
        'ai_response_json': aiResponseJson,
        'record': record.toJson(),
        'created_at': createdAt.toIso8601String(),
      };

  factory ObdInsightRecord.fromJson(Map<String, dynamic> json) {
    return ObdInsightRecord(
      vehicleId: json['vehicle_id'] as String? ?? '',
      kind: ObdScanKind.values.byName(
        json['kind'] as String? ?? ObdScanKind.idle.name,
      ),
      sessionId: json['session_id'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      aiResponseJson: Map<String, dynamic>.from(
        (json['ai_response_json'] as Map?) ?? const <String, dynamic>{},
      ),
      record: ObdScanRecord.fromJson(
        Map<String, dynamic>.from(
          (json['record'] as Map?) ?? const <String, dynamic>{},
        ),
      ),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
