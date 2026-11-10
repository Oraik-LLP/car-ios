import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_response.dart';
import '../../models/diagnostic.dart';
import '../../models/obd.dart';
import '../conversations/conversation_chat_screen.dart';
import '../../services/conversation_service.dart';
import '../../services/obd_processing_service.dart';
import '../../services/diagnostic_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_markdown_text.dart';
import '../../widgets/health_score_card.dart';
import '../../widgets/neuomorphic.dart';
import '../../widgets/report_export_button.dart';

ObdScanRecord? _obdRecordFromSession(DiagnosticSession session) {
  final recordJson = session.contextJson?['obd_record'];
  if (recordJson is! Map) return null;
  try {
    return ObdScanRecord.fromJson(Map<String, dynamic>.from(recordJson));
  } catch (_) {
    return null;
  }
}

class _UnavailableReportCard extends StatelessWidget {
  const _UnavailableReportCard({required this.session});

  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final rawObdSaved =
        session.isObd && session.contextJson?['obd_record'] is Map;

    return NeuPane(
      child: Column(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            rawObdSaved
                ? 'Scan saved on this device'
                : 'Diagnosis temporarily unavailable',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            rawObdSaved
                ? 'AI analysis could not finish, but the raw scan and local summaries are saved below. You can share the technician PDF from this report.'
                : 'We could not complete the AI report because of a backend or connection issue. Please try again in a little while.',
            style: tt.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (session.aiResponseJson?['error_code'] != null ||
              session.aiResponse != null) ...[
            const SizedBox(height: 10),
            Text(
              'Error code: '
              '${session.aiResponseJson?['error_code'] ?? 'report_unavailable'}',
              style: tt.bodySmall?.copyWith(
                color: AppColors.textTertiary,
                fontFamily: 'monospace',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

String _obdCompletionLabel(ObdCompletionReason reason) => switch (reason) {
      ObdCompletionReason.completed => 'Completed',
      ObdCompletionReason.bluetoothDisconnect => 'Bluetooth disconnect',
      ObdCompletionReason.vehicleMoved => 'Vehicle moved',
      ObdCompletionReason.cancelled => 'Cancelled',
      ObdCompletionReason.backgroundInterrupted => 'App interrupted',
    };

String _obdMetricLabel(String metricKey) =>
    ObdMetricCatalog.labels[metricKey] ?? metricKey;

String _obdMetricUnit(String metricKey) =>
    ObdMetricCatalog.units[metricKey] ?? '';

String _formatObdValue(double value, String metricKey) {
  final rounded =
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  final unit = _obdMetricUnit(metricKey);
  return unit.isEmpty ? rounded : '$rounded $unit';
}

String _formatDurationChip(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  if (minutes == 0) return '${seconds}s';
  return '${minutes}m ${remaining.toString().padLeft(2, '0')}s';
}

class _ObdTelemetrySection extends StatelessWidget {
  const _ObdTelemetrySection({
    required this.record,
    required this.session,
  });

  final ObdScanRecord record;
  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeuPane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'OBD Scan Details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  RawObdReportExportButton(
                    session: session,
                    record: record,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ObdInfoChip(
                    label: record.isPartial ? 'Partial scan' : 'Full scan',
                    color: record.isPartial
                        ? const Color(0xFFFFB86C)
                        : const Color(0xFF7DD3FC),
                  ),
                  _ObdInfoChip(
                    label:
                        '${_formatDurationChip(record.capturedDurationSeconds)} / ${_formatDurationChip(record.targetDurationSeconds)}',
                  ),
                  _ObdInfoChip(
                    label: _obdCompletionLabel(record.completionReason),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (record.staticSnapshot.hasAnyData) ...[
          const SizedBox(height: 16),
          _ObdStaticSnapshotSection(snapshot: record.staticSnapshot),
        ],
        if (record.kind == ObdScanKind.idle &&
            record.processedScan.idleStats.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ObdIdleStatsSection(stats: record.processedScan.idleStats),
        ],
        if (record.kind == ObdScanKind.drive &&
            record.processedScan.timelineSummary.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ObdDriveSummarySection(
              summary: record.processedScan.timelineSummary),
        ],
        if (record.kind == ObdScanKind.drive &&
            record.processedScan.driveTimeline.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ObdDriveTimelineSection(frames: record.processedScan.driveTimeline),
        ],
      ],
    );
  }
}

class _ObdStaticSnapshotSection extends StatelessWidget {
  const _ObdStaticSnapshotSection({required this.snapshot});

  final ObdStaticSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Static Snapshot', style: tt.titleMedium),
          const SizedBox(height: 10),
          if (snapshot.vin?.trim().isNotEmpty == true)
            _MetaRow('VIN', snapshot.vin!.trim()),
          if (snapshot.storedDtcs.isNotEmpty)
            _MetaRow('Stored DTCs', snapshot.storedDtcs.join(', ')),
          if (snapshot.pendingDtcs.isNotEmpty)
            _MetaRow('Pending DTCs', snapshot.pendingDtcs.join(', ')),
          if (snapshot.controlModuleVoltage != null)
            _MetaRow(
              'Module Voltage',
              '${snapshot.controlModuleVoltage!.toStringAsFixed(1)} V',
            ),
          if (snapshot.distanceSinceCodesClearedKm != null)
            _MetaRow(
              'Distance Since Clear',
              '${snapshot.distanceSinceCodesClearedKm} km',
            ),
          if (snapshot.ambientAirTempC != null)
            _MetaRow(
              'Ambient Air Temp',
              '${snapshot.ambientAirTempC!.toStringAsFixed(1)} C',
            ),
        ],
      ),
    );
  }
}

class _ObdIdleStatsSection extends StatelessWidget {
  const _ObdIdleStatsSection({required this.stats});

  final Map<String, ObdMetricStats> stats;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final orderedKeys =
        ObdMetricCatalog.idleMetrics.where(stats.containsKey).followedBy(
              stats.keys
                  .where((key) => !ObdMetricCatalog.idleMetrics.contains(key)),
            );

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Clean Idle Metrics', style: tt.titleMedium),
          const SizedBox(height: 10),
          for (final key in orderedKeys) ...[
            _ObdMetricStatsTile(
              metricKey: key,
              stats: stats[key]!,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ObdDriveSummarySection extends StatelessWidget {
  const _ObdDriveSummarySection({required this.summary});

  final Map<String, ObdMetricStats> summary;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final orderedKeys =
        ObdMetricCatalog.driveMetrics.where(summary.containsKey).followedBy(
              summary.keys
                  .where((key) => !ObdMetricCatalog.driveMetrics.contains(key)),
            );

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Drive Summary', style: tt.titleMedium),
          const SizedBox(height: 10),
          for (final key in orderedKeys) ...[
            _ObdMetricStatsTile(
              metricKey: key,
              stats: summary[key]!,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ObdDriveTimelineSection extends StatelessWidget {
  const _ObdDriveTimelineSection({required this.frames});

  final List<ObdDriveSnapshotFrame> frames;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Drive Timeline', style: tt.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Downsampled snapshot frames showing how the load run evolved over time.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final frame in frames) ...[
            _ObdTimelineFrameCard(frame: frame),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ObdMetricStatsTile extends StatelessWidget {
  const _ObdMetricStatsTile({
    required this.metricKey,
    required this.stats,
  });

  final String metricKey;
  final ObdMetricStats stats;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.32),
        border: Border.all(color: const Color(0x10FFFFFF), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_obdMetricLabel(metricKey), style: tt.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ObdInfoChip(
                  label: 'Avg ${_formatObdValue(stats.average, metricKey)}'),
              _ObdInfoChip(
                  label: 'Min ${_formatObdValue(stats.minimum, metricKey)}'),
              _ObdInfoChip(
                  label: 'Max ${_formatObdValue(stats.maximum, metricKey)}'),
              _ObdInfoChip(label: 'Samples ${stats.sampleCount}'),
              if (stats.droppedSampleCount > 0)
                _ObdInfoChip(label: 'Dropped ${stats.droppedSampleCount}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObdTimelineFrameCard extends StatelessWidget {
  const _ObdTimelineFrameCard({required this.frame});

  final ObdDriveSnapshotFrame frame;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final orderedEntries = ObdMetricCatalog.driveMetrics
        .where(frame.values.containsKey)
        .map((key) => MapEntry(key, frame.values[key]!));

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.28),
        border: Border.all(color: const Color(0x10FFFFFF), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'T + ${_formatDurationChip((frame.elapsedMs / 1000).round())}',
            style: tt.titleSmall?.copyWith(color: const Color(0xFF7DD3FC)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in orderedEntries)
                _ObdInfoChip(
                  label:
                      '${_obdMetricLabel(entry.key)} ${_formatObdValue(entry.value, entry.key)}',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObdInfoChip extends StatelessWidget {
  const _ObdInfoChip({
    required this.label,
    this.color = AppColors.textSecondary,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
          width: 0.6,
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.session});
  final DiagnosticSession session;

  AiDiagnosticResponse? get _aiResponse {
    try {
      if (session.aiResponseJson != null) {
        final response = AiDiagnosticResponse.fromJson(session.aiResponseJson!);
        return response.hasDisplayableScore ? response : null;
      }
      if (session.aiResponse != null) {
        final fallback = AiDiagnosticResponse.fallback(session.aiResponse!);
        return fallback.hasDisplayableScore ? fallback : null;
      }
    } catch (_) {
      if (session.aiResponse != null) {
        final fallback = AiDiagnosticResponse.fallback(session.aiResponse!);
        return fallback.hasDisplayableScore ? fallback : null;
      }
    }
    return null;
  }

  ObdScanRecord? get _obdRecord => _obdRecordFromSession(session);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final resp = _aiResponse;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              // top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Row(
                  children: [
                    FixEaseStepBackButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // header
                      _ReportHeader(session: session),
                      const SizedBox(height: 20),

                      if (session.type == DiagnosticType.live) ...[
                        _LiveConversationSection(session: session),
                        const SizedBox(height: 16),
                      ] else if (session.isObd) ...[
                        if (resp != null)
                          DiagnosticResultCard(
                            response: resp,
                            session: session,
                          )
                        else
                          _UnavailableReportCard(session: session),
                        if (_obdRecord != null) ...[
                          const SizedBox(height: 16),
                          _ObdTelemetrySection(
                            record: _obdRecord!,
                            session: session,
                          ),
                        ],
                      ] else if (resp != null &&
                          session.type == DiagnosticType.invoiceAudit) ...[
                        DiagnosticResultCard(
                          response: resp,
                          session: session,
                        ),
                        const SizedBox(height: 16),
                      ] else if (resp != null) ...[
                        // health ring + badge
                        _HealthSection(
                          response: resp,
                          session: session,
                        ),
                        const SizedBox(height: 16),

                        // sub-score bars
                        if (resp.normalizedSubScores.isNotEmpty) ...[
                          _SubScoresSection(response: resp),
                          const SizedBox(height: 16),
                        ],

                        // radar chart for sub-scores
                        if (resp.normalizedSubScores.length >= 3) ...[
                          _RadarSection(response: resp),
                          const SizedBox(height: 16),
                        ],

                        // urgency alert
                        if (resp.urgencyNote != null) ...[
                          _UrgencyBanner(note: resp.urgencyNote!),
                          const SizedBox(height: 16),
                        ],

                        // AI summary
                        NeuPane(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_awesome_rounded,
                                      size: 18, color: AppColors.accent),
                                  const SizedBox(width: 8),
                                  Text('AI Summary', style: tt.titleMedium),
                                ],
                              ),
                              const SizedBox(height: 10),
                              AppMarkdownText(resp.summary,
                                  style: tt.bodyMedium),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // possible causes
                        if (resp.possibleCauses.isNotEmpty) ...[
                          _CausesSection(causes: resp.possibleCauses),
                          const SizedBox(height: 16),
                        ],

                        // recommendations
                        if (resp.recommendations.isNotEmpty) ...[
                          _RecommendationsSection(items: resp.recommendations),
                          const SizedBox(height: 16),
                        ],
                      ] else
                        _UnavailableReportCard(session: session),

                      const SizedBox(height: 16),
                      _PastConversationsSection(session: session),

                      // symptoms detail
                      if (session.symptoms.isNotEmpty) ...[
                        _SymptomsSection(symptoms: session.symptoms),
                        const SizedBox(height: 16),
                      ],

                      // metadata
                      _MetadataSection(session: session),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    HapticFeedback.mediumImpact();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Report', style: Theme.of(ctx).textTheme.titleLarge),
        content: Text(
          'This report will be permanently deleted.',
          style: Theme.of(ctx).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              DiagnosticService.instance.delete(session.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Report header — vehicle name, type, date/time
// ═══════════════════════════════════════════════════════════════════════════════

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.session});
  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isUrgent = session.type == DiagnosticType.urgent;
    final isInvoiceAudit = session.type == DiagnosticType.invoiceAudit;
    final isLive = session.type == DiagnosticType.live;
    final isObdIdle = session.type == DiagnosticType.obdIdle;
    final isObdDrive = session.type == DiagnosticType.obdDrive;
    final obdRecord = _obdRecordFromSession(session);
    final invoiceResponse = session.aiResponseJson != null
        ? AiDiagnosticResponse.fromJson(session.aiResponseJson!)
        : null;
    final accentColor = isInvoiceAudit && invoiceResponse != null
        ? invoiceResponse.statusColor
        : isLive
            ? const Color(0xFF4CAF50)
            : isUrgent
                ? const Color(0xFFFF9800)
                : isObdIdle || isObdDrive
                    ? const Color(0xFF7DD3FC)
                    : AppColors.accent;
    final icon = isUrgent
        ? Icons.warning_amber_rounded
        : isInvoiceAudit
            ? Icons.receipt_long_rounded
            : isLive
                ? Icons.videocam_rounded
                : isObdIdle
                    ? Icons.nights_stay_rounded
                    : isObdDrive
                        ? Icons.route_rounded
                        : Icons.camera_alt_rounded;
    final title = isUrgent
        ? 'Urgent Diagnosis'
        : isInvoiceAudit
            ? 'Invoice Audit'
            : isLive
                ? 'Gemini Live'
                : isObdIdle
                    ? (obdRecord?.isPartial == true
                        ? 'Partial Idle Scan'
                        : 'Idle Health Scan')
                    : isObdDrive
                        ? (obdRecord?.isPartial == true
                            ? 'Partial Drive Scan'
                            : 'Drive Load Scan')
                        : 'Photo Diagnosis';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.15),
              ),
              child: Icon(
                icon,
                color: accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: tt.headlineMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    session.vehicleName ?? 'Unknown Vehicle',
                    style: tt.bodyMedium?.copyWith(color: AppColors.accent),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 13, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(session.dateLabel, style: tt.bodySmall),
            const SizedBox(width: 16),
            const Icon(Icons.schedule_rounded,
                size: 13, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(session.timeLabel, style: tt.bodySmall),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: accentColor.withValues(alpha: 0.12),
              ),
              child: Text(
                isLive
                    ? 'Conversation'
                    : isInvoiceAudit
                        ? (invoiceResponse?.healthLabel ?? 'Audit')
                        : session.isObd
                            ? (obdRecord?.isPartial == true
                                ? 'Partial OBD Scan'
                                : 'OBD Scan')
                            : session.severityLabel,
                style: tt.bodySmall?.copyWith(
                  color: accentColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Health section — big ring + label + confidence
// ═══════════════════════════════════════════════════════════════════════════════

class _HealthSection extends StatelessWidget {
  const _HealthSection({
    required this.response,
    required this.session,
  });
  final AiDiagnosticResponse response;
  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Row(
        children: [
          NeuProgressRing(
            progress: response.displayProgress,
            size: 100,
            label: response.displayScoreLabel,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Overall Health', style: tt.titleLarge),
                    ),
                    if (session.supportsPdfExport)
                      ReportExportButton(
                        session: session,
                        response: response,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                _HealthChip(
                  label: response.healthLabel,
                  color: response.statusColor,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.verified_rounded,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      'AI Confidence: ${response.confidenceLabel}',
                      style: tt.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _ConfidenceBar(confidenceProgress: response.confidenceProgress),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthChip extends StatelessWidget {
  const _HealthChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.18),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ConfidenceBar extends StatelessWidget {
  const _ConfidenceBar({required this.confidenceProgress});
  final double confidenceProgress;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: LinearProgressIndicator(
          value: confidenceProgress.clamp(0, 1),
          backgroundColor: AppColors.surfaceHighlight,
          color: AppColors.accent.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Sub-scores — horizontal bar chart table
// ═══════════════════════════════════════════════════════════════════════════════

class _SubScoresSection extends StatelessWidget {
  const _SubScoresSection({required this.response});
  final AiDiagnosticResponse response;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text('Component Breakdown', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          for (final e in response.normalizedSubScores.entries) ...[
            _ScoreBar(
              label: e.key,
              score: e.value,
              usesHundredPointScale: response.usesHundredPointScale,
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({
    required this.label,
    required this.score,
    required this.usesHundredPointScale,
  });
  final String label;
  final double score;
  final bool usesHundredPointScale;

  Color get _barColor {
    if (usesHundredPointScale) {
      if (score >= 80) return const Color(0xFF4CAF50);
      if (score >= 60) return const Color(0xFFFFC107);
      if (score >= 40) return const Color(0xFFFF9800);
      return const Color(0xFFFF5252);
    }
    if (score >= 8) return const Color(0xFF4CAF50);
    if (score >= 6) return const Color(0xFFFFC107);
    if (score >= 4) return const Color(0xFFFF9800);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pct = usesHundredPointScale
        ? (score / 100).clamp(0.0, 1.0)
        : (score / 10).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: AppColors.surfaceHighlight,
                ),
              ),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    gradient: LinearGradient(
                      colors: [
                        _barColor.withValues(alpha: 0.6),
                        _barColor,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: usesHundredPointScale ? 38 : 32,
          child: Text(
            usesHundredPointScale
                ? score.round().toString()
                : score.toStringAsFixed(1),
            style: tt.bodySmall?.copyWith(
              color: _barColor,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Radar / Spider chart for sub-scores
// ═══════════════════════════════════════════════════════════════════════════════

class _RadarSection extends StatelessWidget {
  const _RadarSection({required this.response});
  final AiDiagnosticResponse response;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.radar_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text('Health Radar', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: Center(
              child: CustomPaint(
                size: const Size(220, 220),
                painter: _RadarPainter(
                  labels: response.normalizedSubScores.keys.toList(),
                  values: response.normalizedSubScores.values
                      .map((v) => response.usesHundredPointScale
                          ? (v / 100).clamp(0.0, 1.0)
                          : (v / 10).clamp(0.0, 1.0))
                      .toList(),
                  accentColor: AppColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.labels,
    required this.values,
    required this.accentColor,
  });
  final List<String> labels;
  final List<double> values;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 28;
    final n = labels.length;
    final angleStep = 2 * math.pi / n;
    const startAngle = -math.pi / 2;

    // grid rings
    final gridPaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;

    for (var ring = 1; ring <= 5; ring++) {
      final rr = r * ring / 5;
      final path = Path();
      for (var i = 0; i < n; i++) {
        final a = startAngle + i * angleStep;
        final p = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    // axis lines
    for (var i = 0; i < n; i++) {
      final a = startAngle + i * angleStep;
      final end = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
      canvas.drawLine(c, end, gridPaint);
    }

    // data polygon
    final fillPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final a = startAngle + i * angleStep;
      final v = values[i] * r;
      final p = Offset(c.dx + v * math.cos(a), c.dy + v * math.sin(a));
      if (i == 0) {
        dataPath.moveTo(p.dx, p.dy);
      } else {
        dataPath.lineTo(p.dx, p.dy);
      }
    }
    dataPath.close();
    canvas.drawPath(dataPath, fillPaint);
    canvas.drawPath(dataPath, strokePaint);

    // data dots
    final dotPaint = Paint()..color = accentColor;
    for (var i = 0; i < n; i++) {
      final a = startAngle + i * angleStep;
      final v = values[i] * r;
      final p = Offset(c.dx + v * math.cos(a), c.dy + v * math.sin(a));
      canvas.drawCircle(p, 3.5, dotPaint);
    }

    // labels
    final labelStyle = TextStyle(
      color: const Color(0x99FFFFFF),
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );
    for (var i = 0; i < n; i++) {
      final a = startAngle + i * angleStep;
      final lp = Offset(
        c.dx + (r + 18) * math.cos(a),
        c.dy + (r + 18) * math.sin(a),
      );

      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      var dx = lp.dx - tp.width / 2;
      var dy = lp.dy - tp.height / 2;

      // nudge labels that overlap
      if (a.abs() < 0.1 || (a + math.pi).abs() < 0.1) {
        // top / bottom — center horizontally
      } else if (math.cos(a) > 0) {
        dx = lp.dx;
      } else {
        dx = lp.dx - tp.width;
      }

      tp.paint(canvas, Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      !_listEq(old.values, values);

  bool _listEq(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Urgency banner
// ═══════════════════════════════════════════════════════════════════════════════

class _UrgencyBanner extends StatelessWidget {
  const _UrgencyBanner({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0x22FF5252),
        border: Border.all(color: const Color(0x44FF5252), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.priority_high_rounded,
              size: 20, color: Color(0xFFFF5252)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Urgency Alert',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFFFF8A80),
                        )),
                const SizedBox(height: 4),
                Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFF8A80),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Possible causes table
// ═══════════════════════════════════════════════════════════════════════════════

class _CausesSection extends StatelessWidget {
  const _CausesSection({required this.causes});
  final List<String> causes;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.troubleshoot_rounded,
                  size: 18, color: Color(0xFFFF9800)),
              const SizedBox(width: 8),
              Text('Possible Causes', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < causes.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFFF9800).withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: tt.bodySmall?.copyWith(
                          color: const Color(0xFFFF9800),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppMarkdownText(causes[i], style: tt.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Recommendations
// ═══════════════════════════════════════════════════════════════════════════════

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({required this.items});
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text('Recommendations', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppMarkdownText(items[i], style: tt.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Symptoms chips
// ═══════════════════════════════════════════════════════════════════════════════

class _SymptomsSection extends StatelessWidget {
  const _SymptomsSection({required this.symptoms});
  final List<String> symptoms;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rounded,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('Reported Symptoms', style: tt.titleMedium),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: symptoms
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.accent.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.25),
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        s,
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Metadata footer
// ═══════════════════════════════════════════════════════════════════════════════

class _LiveConversationSection extends StatelessWidget {
  const _LiveConversationSection({required this.session});

  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: ConversationService.instance,
      builder: (context, _) {
        final thread =
            ConversationService.instance.threadForSession(session.id);
        final messageCount = thread?.messages.length ?? 0;

        return NeuPane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.14),
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Saved Gemini Live Session', style: tt.titleLarge),
                        const SizedBox(height: 4),
                        Text(
                          messageCount > 0
                              ? '$messageCount saved message${messageCount == 1 ? '' : 's'}'
                              : 'No saved turns yet',
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                thread?.previewText ??
                    'This Gemini Live session is stored locally and can be continued with text, voice, or attachments.',
                style: tt.bodyMedium,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PastConversationsSection extends StatelessWidget {
  const _PastConversationsSection({required this.session});

  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: ConversationService.instance,
      builder: (context, _) {
        final thread =
            ConversationService.instance.threadForSession(session.id);
        final hasThread = thread != null && thread.messages.isNotEmpty;

        return NeuPane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.forum_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  Text('Past Conversations', style: tt.titleMedium),
                ],
              ),
              const SizedBox(height: 12),
              if (hasThread)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.surfaceHighlight.withValues(alpha: 0.35),
                    border: Border.all(
                      color: const Color(0x12FFFFFF),
                      width: 0.6,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent.withValues(alpha: 0.12),
                        ),
                        child: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 18,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              thread.previewText,
                              style: tt.bodyMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Updated ${_formatThreadTimestamp(thread.updatedAt)}',
                              style: tt.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => openConversationChat(
                          context,
                          session: session,
                        ),
                        child: Text(
                          'Continue',
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.type == DiagnosticType.live
                            ? 'No saved turns yet. Start chatting to keep this Gemini Live session around.'
                            : 'No follow-up conversation yet. Start one to keep asking questions about this diagnosis.',
                        style: tt.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => openConversationChat(
                        context,
                        session: session,
                      ),
                      child: Text(
                        'Start Conversation',
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatThreadTimestamp(DateTime updatedAt) {
    final day = updatedAt.day.toString().padLeft(2, '0');
    final month = updatedAt.month.toString().padLeft(2, '0');
    final hour = updatedAt.hour.toString().padLeft(2, '0');
    final minute = updatedAt.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}

class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.session});
  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final obdRecord = _obdRecordFromSession(session);

    return NeuPane(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Report Details', style: tt.titleSmall),
          const SizedBox(height: 8),
          _MetaRow('Report ID', session.id),
          _MetaRow(
              'Type',
              switch (session.type) {
                DiagnosticType.urgent => 'Urgent',
                DiagnosticType.photo => 'Photo',
                DiagnosticType.invoiceAudit => 'Invoice Audit',
                DiagnosticType.live => 'Gemini Live',
                DiagnosticType.obdIdle => 'OBD Idle Scan',
                DiagnosticType.obdDrive => 'OBD Drive Scan',
              }),
          _MetaRow(
            session.isObd
                ? 'Scan Status'
                : session.type == DiagnosticType.invoiceAudit
                    ? 'Assessment'
                    : session.type == DiagnosticType.live
                        ? 'Session'
                        : 'Severity',
            session.isObd
                ? (obdRecord == null
                    ? 'OBD telemetry'
                    : obdRecord.isPartial
                        ? 'Partial - ${_obdCompletionLabel(obdRecord.completionReason)}'
                        : 'Complete - ${_obdCompletionLabel(obdRecord.completionReason)}')
                : session.type == DiagnosticType.invoiceAudit
                    ? (session.aiResponseJson?['verdict'] as String? ?? 'Audit')
                    : session.type == DiagnosticType.live
                        ? 'Conversation'
                        : session.severityLabel,
          ),
          _MetaRow('Date', '${session.dateLabel} ${session.timeLabel}'),
          if (session.isObd && obdRecord != null)
            _MetaRow(
              'Duration',
              '${_formatDurationChip(obdRecord.capturedDurationSeconds)} / ${_formatDurationChip(obdRecord.targetDurationSeconds)}',
            ),
          if (session.description != null && session.description!.isNotEmpty)
            _MetaRow('Description', session.description!),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: tt.bodySmall?.copyWith(color: AppColors.textTertiary)),
          ),
          Expanded(
            child: Text(value, style: tt.bodySmall),
          ),
        ],
      ),
    );
  }
}
