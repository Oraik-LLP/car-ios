import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../config/app_config.dart';
import '../models/ai_response.dart';
import '../models/diagnostic.dart';
import '../models/obd.dart';
import '../services/diagnostic_service.dart';
import '../services/report_export_service.dart';
import '../services/subscription_service.dart';
import '../theme/app_theme.dart';

class ReportExportButton extends StatefulWidget {
  const ReportExportButton({
    super.key,
    required this.session,
    required this.response,
  });

  final DiagnosticSession session;
  final AiDiagnosticResponse response;

  @override
  State<ReportExportButton> createState() => _ReportExportButtonState();
}

class _ReportExportButtonState extends State<ReportExportButton> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.session.supportsPdfExport) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _isExporting
          ? null
          : () async {
              final reportCount =
                  DiagnosticService.instance.reportCountForCurrentMonth();
              final needsUpgrade =
                  reportCount > AppConfig.freePdfReportsPerMonth &&
                      !checkAccess(FeatureType.techPdfAfterTwoReports);
              if (needsUpgrade) {
                final unlocked = await ensureAccess(
                  context,
                  FeatureType.techPdfAfterTwoReports,
                  reason: 'Download Tech PDF',
                );
                if (!unlocked) return;
              }
              if (!context.mounted) return;
              await _showActions(context);
            },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: AppColors.accent.withValues(alpha: 0.12),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.28),
            width: 0.7,
          ),
        ),
        child: Center(
          child: _isExporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.accent,
                  ),
                )
              : const Icon(
                  Icons.ios_share_rounded,
                  size: 18,
                  color: AppColors.accent,
                ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final tt = Theme.of(ctx).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Report PDF', style: tt.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Save this report to your device or share it as a PDF.',
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 18),
                _ExportActionTile(
                  icon: Icons.share_rounded,
                  label: 'Share PDF',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _run(
                      context,
                      action: () => ReportExportService.sharePdf(
                        session: widget.session,
                        response: widget.response,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _ExportActionTile(
                  icon: Icons.download_rounded,
                  label: 'Save PDF',
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    await _run(
                      context,
                      action: () => ReportExportService.savePdf(
                        session: widget.session,
                        response: widget.response,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _run(
    BuildContext context, {
    required Future<dynamic> Function() action,
  }) async {
    if (_isExporting) return;
    if (mounted) {
      setState(() => _isExporting = true);
    }
    try {
      final result = await action();
      if (!context.mounted) return;
      if (result is File) {
        await OpenFilex.open(result.path);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'PDF saved successfully: ${result.uri.pathSegments.last}',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            showCloseIcon: true,
            closeIconColor: AppColors.textPrimary,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not export report PDF',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          closeIconColor: AppColors.textPrimary,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }
}

class RawObdReportExportButton extends StatefulWidget {
  const RawObdReportExportButton({
    super.key,
    required this.session,
    required this.record,
  });

  final DiagnosticSession session;
  final ObdScanRecord record;

  @override
  State<RawObdReportExportButton> createState() =>
      _RawObdReportExportButtonState();
}

class _RawObdReportExportButtonState extends State<RawObdReportExportButton> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Export raw OBD report',
      onPressed: _isExporting ? null : () => _showActions(context),
      icon: _isExporting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
              ),
            )
          : const Icon(Icons.ios_share_rounded, color: AppColors.accent),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Raw OBD report PDF',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'This report contains the captured adapter data and local summaries, without AI analysis.',
                style: Theme.of(sheetContext).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              _ExportActionTile(
                icon: Icons.share_rounded,
                label: 'Share PDF',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _run(
                    context,
                    () => ReportExportService.shareRawObdPdf(
                      session: widget.session,
                      record: widget.record,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _ExportActionTile(
                icon: Icons.download_rounded,
                label: 'Save PDF',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _run(
                    context,
                    () => ReportExportService.saveRawObdPdf(
                      session: widget.session,
                      record: widget.record,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<dynamic> Function() action,
  ) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final result = await action();
      if (result is File) {
        await OpenFilex.open(result.path);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Raw report saved: ${result.uri.pathSegments.last}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not export the raw OBD report.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}

class _ExportActionTile extends StatelessWidget {
  const _ExportActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppColors.surfaceHighlight.withValues(alpha: 0.45),
            border: Border.all(
              color: const Color(0x10FFFFFF),
              width: 0.6,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.accent, size: 20),
              const SizedBox(width: 12),
              Text(label, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
