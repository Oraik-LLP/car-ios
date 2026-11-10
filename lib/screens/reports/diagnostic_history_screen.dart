import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ai_response.dart';
import '../../models/diagnostic.dart';
import '../../models/obd.dart';
import '../../services/conversation_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neuomorphic.dart';
import '../conversations/conversation_chat_screen.dart';
import 'report_detail_screen.dart';

class DiagnosticHistoryScreen extends StatelessWidget {
  const DiagnosticHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                child: Row(
                  children: [
                    FixEaseStepBackButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Diagnostic History', style: tt.titleLarge),
                    ),
                    ListenableBuilder(
                      listenable: DiagnosticService.instance,
                      builder: (_, __) {
                        final hasReports =
                            DiagnosticService.instance.sessions.isNotEmpty;
                        return IconButton(
                          tooltip: 'Delete all reports',
                          onPressed: hasReports
                              ? () async {
                                  HapticFeedback.mediumImpact();
                                  final confirmed =
                                      await _confirmDeleteAll(context);
                                  if (confirmed != true || !context.mounted) {
                                    return;
                                  }
                                  await DiagnosticService.instance.deleteAll();
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('All reports deleted'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              : null,
                          icon: Icon(
                            Icons.delete_sweep_rounded,
                            color: hasReports
                                ? const Color(0xFFFF7043)
                                : AppColors.textTertiary,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Expanded(child: DiagnosticHistoryList()),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteAll(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text('Delete All Reports', style: tt.titleLarge),
        content: Text(
          'This will permanently delete every saved diagnostic report and its conversation history.',
          style: tt.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete All',
              style: TextStyle(color: Color(0xFFFF5252)),
            ),
          ),
        ],
      ),
    );
  }
}

class DiagnosticHistoryList extends StatelessWidget {
  const DiagnosticHistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        DiagnosticService.instance,
        ConversationService.instance,
        SubscriptionService.instance,
      ]),
      builder: (context, _) {
        final all = DiagnosticService.instance.sessions;

        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.insights_rounded,
                  size: 56,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: 16),
                Text('No reports yet', style: tt.bodyLarge),
                const SizedBox(height: 6),
                Text(
                  'Run a diagnostic to build your history here.',
                  style: tt.bodySmall,
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          itemCount: all.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _HistoryListCard(session: all[index]);
          },
        );
      },
    );
  }
}

class _HistoryListCard extends StatelessWidget {
  const _HistoryListCard({required this.session});

  final DiagnosticSession session;

  AiDiagnosticResponse? get _response {
    final json = session.aiResponseJson;
    if (json == null) return null;
    try {
      return AiDiagnosticResponse.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  ObdScanRecord? get _obdRecord {
    final context = session.contextJson;
    final recordJson = context?['obd_record'];
    if (recordJson is! Map) return null;
    try {
      return ObdScanRecord.fromJson(Map<String, dynamic>.from(recordJson));
    } catch (_) {
      return null;
    }
  }

  Color get _scoreColor {
    if (session.type == DiagnosticType.live) {
      return const Color(0xFF4CAF50);
    }
    final response = _response;
    if (response != null) return response.statusColor;
    final score = session.healthScore ?? 0;
    if (score >= 80) return const Color(0xFF4CAF50);
    if (score >= 60) return const Color(0xFFFFC107);
    if (score >= 40) return const Color(0xFFFF9800);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final response = _response;
    final isUrgent = session.type == DiagnosticType.urgent;
    final isInvoiceAudit = session.type == DiagnosticType.invoiceAudit;
    final isLive = session.type == DiagnosticType.live;
    final isObdIdle = session.type == DiagnosticType.obdIdle;
    final isObdDrive = session.type == DiagnosticType.obdDrive;
    final obdRecord = _obdRecord;
    final thread = ConversationService.instance.threadForSession(session.id);
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
                        : Icons.camera_alt_outlined;
    final iconColor = isUrgent
        ? const Color(0xFFFF9800)
        : isInvoiceAudit
            ? const Color(0xFFFF7043)
            : isLive
                ? const Color(0xFF4CAF50)
                : isObdIdle || isObdDrive
                    ? const Color(0xFF7DD3FC)
                    : AppColors.accent;
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
    final isLocked =
        DiagnosticService.instance.isOlderThanMostRecentSessions(
          session,
          allowedCount: 2,
        ) &&
        !checkAccess(
          FeatureType.olderHistoryAccess,
          session: session,
        );
    final ringProgress = response != null
        ? response.displayProgress
        : ((session.healthScore ?? 0) / 100).clamp(0.0, 1.0);
    final ringLabel = response != null
        ? response.displayScoreLabel
        : session.healthScore?.round().toString() ?? '-';

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0x33FF5252),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Color(0xFFFF5252),
        ),
      ),
      confirmDismiss: (_) => _confirmDeleteOne(context),
      onDismissed: (_) => DiagnosticService.instance.delete(session.id),
      child: Opacity(
        opacity: isLocked ? 0.68 : 1,
        child: GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            if (isLocked) {
              await ensureAccess(
                context,
                FeatureType.olderHistoryAccess,
                session: session,
                reason: 'Older Diagnostic History',
              );
              return;
            }
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => isLive
                    ? ConversationChatScreen(session: session)
                    : ReportDetailScreen(session: session),
              ),
            );
          },
          child: NeuPane(
            child: Row(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          value: ringProgress,
                          strokeWidth: 3,
                          backgroundColor: AppColors.surfaceHighlight,
                          color: _scoreColor,
                        ),
                      ),
                      Text(
                        ringLabel,
                        style: tt.bodySmall?.copyWith(
                          color: _scoreColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 15, color: iconColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              style: tt.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (session.vehicleName != null)
                        Text(
                          session.vehicleName!,
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.accent,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(session.dateLabel, style: tt.bodySmall),
                          const SizedBox(width: 8),
                          Text(
                            session.timeLabel,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const Spacer(),
                          if (isLive)
                            Flexible(
                              child: Text(
                                thread?.previewText ?? 'Saved conversation',
                                style: tt.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            )
                          else if (session.type == DiagnosticType.invoiceAudit)
                            Text(
                              session.aiResponseJson?['document_type'] as String? ??
                                  'Bill review',
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            )
                          else if (session.isObd && obdRecord != null)
                            Text(
                              obdRecord.isPartial
                                  ? '${obdRecord.capturedDurationSeconds}s / ${obdRecord.targetDurationSeconds}s'
                                  : '${obdRecord.targetDurationSeconds}s captured',
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            )
                          else if (session.symptoms.isNotEmpty)
                            Text(
                              '${session.symptoms.length} symptom(s)',
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete report',
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    final confirmed = await _confirmDeleteOne(context);
                    if (confirmed != true) return;
                    await DiagnosticService.instance.delete(session.id);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report deleted'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Color(0xFFFF7043),
                  ),
                ),
                Icon(
                  isLocked ? Icons.lock_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: isLocked ? AppColors.accent : AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDeleteOne(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text('Delete Report', style: tt.titleLarge),
        content: Text(
          'This report will be permanently deleted.',
          style: tt.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Color(0xFFFF5252)),
            ),
          ),
        ],
      ),
    );
  }
}
