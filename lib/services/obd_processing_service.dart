import 'dart:isolate';
import 'dart:math' as math;

import '../models/obd.dart';

abstract final class ObdMetricCatalog {
  static const rpm = 'rpm';
  static const speed = 'speed_kph';
  static const coolantTemp = 'coolant_temp_c';
  static const throttlePosition = 'throttle_position_pct';
  static const intakePressure = 'intake_pressure_kpa';
  static const shortFuelTrim = 'short_term_fuel_trim_pct';
  static const longFuelTrim = 'long_term_fuel_trim_pct';
  static const engineLoad = 'engine_load_pct';
  static const maf = 'maf_gps';
  static const ignitionTiming = 'ignition_timing_deg';

  static const labels = <String, String>{
    rpm: 'RPM',
    speed: 'Speed',
    coolantTemp: 'Coolant Temp',
    throttlePosition: 'Throttle Position',
    intakePressure: 'Intake Pressure',
    shortFuelTrim: 'Short Fuel Trim',
    longFuelTrim: 'Long Fuel Trim',
    engineLoad: 'Engine Load',
    maf: 'Mass Air Flow',
    ignitionTiming: 'Ignition Timing',
  };

  static const units = <String, String>{
    rpm: 'rpm',
    speed: 'km/h',
    coolantTemp: 'C',
    throttlePosition: '%',
    intakePressure: 'kPa',
    shortFuelTrim: '%',
    longFuelTrim: '%',
    engineLoad: '%',
    maf: 'g/s',
    ignitionTiming: 'deg',
  };

  static const idleMetrics = <String>[
    rpm,
    throttlePosition,
    intakePressure,
    shortFuelTrim,
    longFuelTrim,
  ];

  static const driveMetrics = <String>[
    rpm,
    speed,
    engineLoad,
    maf,
    ignitionTiming,
  ];
}

abstract final class ObdPartialRecoveryPolicy {
  static const minimumIdlePartialDuration = Duration(seconds: 10);
  static const minimumDrivePartialDuration = Duration(seconds: 20);

  static bool canFinalizeIdlePartial(Duration capturedDuration) =>
      capturedDuration >= minimumIdlePartialDuration;

  static bool canFinalizeDrivePartial({
    required bool isArmed,
    required Duration capturedDuration,
  }) =>
      isArmed && capturedDuration >= minimumDrivePartialDuration;
}

abstract final class ObdProcessingService {
  static Future<ObdProcessedScan> processIdle(
    List<ObdSampleFrame> samples,
  ) {
    return Isolate.run(() => _processIdle(samples));
  }

  static Future<ObdProcessedScan> processDrive(
    List<ObdSampleFrame> samples,
  ) {
    return Isolate.run(() => _processDrive(samples));
  }

  static ObdProcessedScan _processIdle(List<ObdSampleFrame> samples) {
    final stats = <String, ObdMetricStats>{};
    for (final metric in ObdMetricCatalog.idleMetrics) {
      final values = _valuesForMetric(samples, metric);
      final filtered = _filterOutliers(values);
      if (filtered.isEmpty) {
        continue;
      }
      stats[metric] = ObdMetricStats(
        minimum: filtered.reduce(math.min),
        maximum: filtered.reduce(math.max),
        average: filtered.reduce((a, b) => a + b) / filtered.length,
        sampleCount: filtered.length,
        droppedSampleCount: values.length - filtered.length,
      );
    }

    return ObdProcessedScan(
      kind: ObdScanKind.idle,
      idleStats: stats,
      sampleCount: samples.length,
    );
  }

  static ObdProcessedScan _processDrive(List<ObdSampleFrame> samples) {
    final sorted = [...samples]..sort((a, b) => a.elapsedMs.compareTo(b.elapsedMs));
    final summary = <String, ObdMetricStats>{};
    for (final metric in ObdMetricCatalog.driveMetrics) {
      final values = _valuesForMetric(sorted, metric);
      if (values.isEmpty) {
        continue;
      }
      summary[metric] = ObdMetricStats(
        minimum: values.reduce(math.min),
        maximum: values.reduce(math.max),
        average: values.reduce((a, b) => a + b) / values.length,
        sampleCount: values.length,
        droppedSampleCount: 0,
      );
    }

    if (sorted.isEmpty) {
      return ObdProcessedScan(
        kind: ObdScanKind.drive,
        driveTimeline: const [],
        timelineSummary: summary,
        sampleCount: 0,
      );
    }

    final totalDurationMs = sorted.last.elapsedMs.clamp(1, 120000);
    final frameCount = math.min(12, math.max(1, sorted.length));
    final timeline = <ObdDriveSnapshotFrame>[];
    final latest = <String, double>{};
    var sampleIndex = 0;

    for (var bucket = 1; bucket <= frameCount; bucket++) {
      final cutoff = ((bucket / frameCount) * totalDurationMs).round();
      while (sampleIndex < sorted.length &&
          sorted[sampleIndex].elapsedMs <= cutoff) {
        latest.addAll(sorted[sampleIndex].values);
        sampleIndex += 1;
      }
      if (latest.isEmpty) {
        continue;
      }
      timeline.add(
        ObdDriveSnapshotFrame(
          elapsedMs: cutoff,
          values: Map<String, double>.from(latest),
        ),
      );
    }

    return ObdProcessedScan(
      kind: ObdScanKind.drive,
      driveTimeline: timeline,
      timelineSummary: summary,
      sampleCount: samples.length,
    );
  }

  static List<double> _valuesForMetric(
    List<ObdSampleFrame> samples,
    String metric,
  ) {
    return samples
        .map((sample) => sample.values[metric])
        .whereType<double>()
        .toList();
  }

  static List<double> _filterOutliers(List<double> values) {
    if (values.length < 4) {
      return values;
    }
    final sorted = [...values]..sort();
    final q1 = _percentile(sorted, 0.25);
    final q3 = _percentile(sorted, 0.75);
    final iqr = q3 - q1;
    if (iqr <= 0) {
      return values;
    }
    final lower = q1 - (1.5 * iqr);
    final upper = q3 + (1.5 * iqr);
    final filtered =
        values.where((value) => value >= lower && value <= upper).toList();
    return filtered.isEmpty ? values : filtered;
  }

  static double _percentile(List<double> sorted, double percentile) {
    if (sorted.isEmpty) {
      return 0;
    }
    final position = (sorted.length - 1) * percentile;
    final lowerIndex = position.floor();
    final upperIndex = position.ceil();
    if (lowerIndex == upperIndex) {
      return sorted[lowerIndex];
    }
    final weight = position - lowerIndex;
    return sorted[lowerIndex] +
        ((sorted[upperIndex] - sorted[lowerIndex]) * weight);
  }
}
