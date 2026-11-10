import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/ai_response.dart';
import '../models/diagnostic.dart';
import '../models/obd.dart';
import 'obd_processing_service.dart';

/// Builds and exports diagnostic reports as PDFs.
abstract final class ReportExportService {
  static Future<File> savePdf({
    required DiagnosticSession session,
    required AiDiagnosticResponse response,
  }) async {
    final bytes = await _buildPdfBytes(session: session, response: response);
    final dir = await _resolveSaveDirectory();
    final filePath = p.join(dir.path, fileName(session));
    await Isolate.run(
      () => File(filePath).writeAsBytesSync(bytes, flush: true),
    );
    final file = File(filePath);
    return file;
  }

  static Future<void> sharePdf({
    required DiagnosticSession session,
    required AiDiagnosticResponse response,
  }) async {
    final bytes = await _buildPdfBytes(session: session, response: response);
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName(session),
    );
  }

  static Future<File> saveRawObdPdf({
    required DiagnosticSession session,
    required ObdScanRecord record,
  }) async {
    final pdf = _buildRawObdPdf(session: session, record: record);
    final bytes = await pdf.save();
    final dir = await _resolveSaveDirectory();
    final path = p.join(dir.path, rawObdFileName(session));
    await Isolate.run(
      () => File(path).writeAsBytesSync(bytes, flush: true),
    );
    return File(path);
  }

  static Future<void> shareRawObdPdf({
    required DiagnosticSession session,
    required ObdScanRecord record,
  }) async {
    final pdf = _buildRawObdPdf(session: session, record: record);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: rawObdFileName(session),
    );
  }

  static String rawObdFileName(DiagnosticSession session) {
    final date = session.createdAt.toIso8601String().split('T').first;
    return 'fixease_obd_raw_${date}_${session.id}.pdf';
  }

  static pw.Document _buildRawObdPdf({
    required DiagnosticSession session,
    required ObdScanRecord record,
  }) {
    final pdf = pw.Document();
    final stats = record.kind == ObdScanKind.idle
        ? record.processedScan.idleStats
        : record.processedScan.timelineSummary;
    final snapshot = record.staticSnapshot;

    pdf.addPage(
      pw.MultiPage(
        pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(30)),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'FixEase raw OBD record · ${context.pageNumber}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#111114'),
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'OBD-II Scan Report',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 7),
                pw.Text(
                  session.vehicleName ?? 'Unknown vehicle',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#8DBDFF'),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Raw scan record · No AI diagnosis included',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'This report contains data returned by the OBD adapter and simple local summaries only. It is not a confirmed diagnosis.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          _section('Scan details', [
            _detailRow('Scan type', record.kind.name.toUpperCase()),
            _detailRow(
                'Date and time', '${session.dateLabel} · ${session.timeLabel}'),
            _detailRow(
              'Status',
              record.isPartial ? 'Partial / interrupted' : 'Completed',
            ),
            _detailRow(
              'Duration',
              '${record.capturedDurationSeconds}s of ${record.targetDurationSeconds}s',
            ),
            _detailRow('Completion', record.completionReason.name),
            _detailRow('Samples', record.processedScan.sampleCount.toString()),
          ]),
          if (snapshot.hasAnyData) ...[
            _section('Vehicle data returned', [
              if (snapshot.vin?.trim().isNotEmpty == true)
                _detailRow('VIN', snapshot.vin!.trim()),
              if (snapshot.storedDtcs.isNotEmpty)
                _detailRow('Stored DTCs', snapshot.storedDtcs.join(', ')),
              if (snapshot.pendingDtcs.isNotEmpty)
                _detailRow('Pending DTCs', snapshot.pendingDtcs.join(', ')),
              if (snapshot.controlModuleVoltage != null)
                _detailRow(
                  'Module voltage',
                  '${snapshot.controlModuleVoltage!.toStringAsFixed(2)} V',
                ),
              if (snapshot.distanceSinceCodesClearedKm != null)
                _detailRow(
                  'Distance since clear',
                  '${snapshot.distanceSinceCodesClearedKm} km',
                ),
              if (snapshot.ambientAirTempC != null)
                _detailRow(
                  'Ambient air',
                  '${snapshot.ambientAirTempC!.toStringAsFixed(1)} C',
                ),
            ]),
          ],
          if (stats.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Local telemetry summary',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'Bars compare minimum, average and maximum readings for each available metric.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 12),
            ...stats.entries
                .map((entry) => _rawObdMetric(entry.key, entry.value)),
          ] else
            _section('Telemetry', [
              _detailRow('Result',
                  'No telemetry samples were received during this scan.'),
            ]),
          if (record.kind == ObdScanKind.drive &&
              record.processedScan.driveTimeline.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _driveTimelineChart(record),
          ],
          pw.SizedBox(height: 14),
          pw.Text(
            'Use this record as supporting information for a qualified technician. Verify readings with suitable diagnostic equipment before making repair decisions.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return pdf;
  }

  static pw.Widget _rawObdMetric(String key, ObdMetricStats stats) {
    final label = ObdMetricCatalog.labels[key] ?? key;
    final unit = ObdMetricCatalog.units[key] ?? '';
    final magnitudes = [
      stats.minimum.abs(),
      stats.average.abs(),
      stats.maximum.abs(),
    ];
    final maxMagnitude = magnitudes.reduce((a, b) => a > b ? a : b);
    final scale = maxMagnitude == 0 ? 1.0 : maxMagnitude;
    final bars = [stats.minimum, stats.average, stats.maximum];
    final valueText = [
      'Min ',
      stats.minimum.toStringAsFixed(1),
      ' ',
      unit,
      ' · Avg ',
      stats.average.toStringAsFixed(1),
      ' ',
      unit,
      ' · Max ',
      stats.maximum.toStringAsFixed(1),
      ' ',
      unit,
    ].join();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 105,
            child: pw.Text(label,
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < bars.length; i++)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(right: 5),
                  child: pw.Container(
                    width: 15,
                    height: 8 + (bars[i].abs() / scale * 30),
                    color: i == 1
                        ? PdfColor.fromHex('#009DFF')
                        : PdfColor.fromHex('#8DBDFF'),
                  ),
                ),
            ],
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Text(valueText, style: const pw.TextStyle(fontSize: 8)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _driveTimelineChart(ObdScanRecord record) {
    final frames = record.processedScan.driveTimeline;
    final metric = ObdMetricCatalog.driveMetrics.firstWhere(
      (key) => frames.any((frame) => frame.values.containsKey(key)),
      orElse: () => frames.first.values.keys.first,
    );
    final values = frames
        .map((frame) => frame.values[metric])
        .whereType<double>()
        .toList();
    if (values.isEmpty) return pw.SizedBox();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${ObdMetricCatalog.labels[metric] ?? metric} drive timeline',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Container(
          width: double.infinity,
          height: 62,
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#EFF7FF'),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (final value in values)
                pw.Expanded(
                  child: pw.Container(
                    height:
                        8 + (range == 0 ? 1 : (value - minValue) / range * 44),
                    margin: const pw.EdgeInsets.symmetric(horizontal: 2),
                    color: PdfColor.fromHex('#009DFF'),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Minimum ${minValue.toStringAsFixed(1)} · Maximum ${maxValue.toStringAsFixed(1)} · ${ObdMetricCatalog.units[metric] ?? ''}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    );
  }

  static String fileName(DiagnosticSession session) {
    final date = session.createdAt.toIso8601String().split('T').first;
    return 'fixease_report_${date}_${session.id}.pdf';
  }

  static Future<Directory> _resolveSaveDirectory() async {
    if (Platform.isAndroid) {
      final dirs =
          await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (dirs != null && dirs.isNotEmpty) {
        return dirs.first;
      }
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<Uint8List> _buildPdfBytes({
    required DiagnosticSession session,
    required AiDiagnosticResponse response,
  }) {
    final sessionJson = Map<String, dynamic>.from(session.toJson());
    final responseJson = Map<String, dynamic>.from(response.toJson());
    return Isolate.run(() async {
      final rebuiltSession = DiagnosticSession.fromJson(sessionJson);
      final rebuiltResponse = AiDiagnosticResponse.fromJson(responseJson);
      final pdf = _buildPdfDocument(
        session: rebuiltSession,
        response: rebuiltResponse,
      );
      final bytes = await pdf.save();
      return Uint8List.fromList(bytes);
    });
  }

  static pw.Document _buildPdfDocument({
    required DiagnosticSession session,
    required AiDiagnosticResponse response,
  }) {
    final pdf = pw.Document();
    final isUrgent = session.type == DiagnosticType.urgent;
    final isInvoiceAudit = session.type == DiagnosticType.invoiceAudit;
    final reportTitle = isUrgent
        ? 'Urgent Diagnosis Report'
        : isInvoiceAudit
            ? 'Invoice Audit Report'
            : 'Photo Diagnosis Report';
    final typeLabel = isUrgent
        ? 'Urgent'
        : isInvoiceAudit
            ? 'Invoice Audit'
            : 'Photo';

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(28),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            'FixEase - Powered by Oraik Systems',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#111114'),
              borderRadius: pw.BorderRadius.circular(16),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  reportTitle,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  session.vehicleName ?? 'Unknown Vehicle',
                  style: pw.TextStyle(
                    color: PdfColor.fromHex('#8DBDFF'),
                    fontSize: 12,
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Row(
                  children: [
                    _metricChip(
                      isInvoiceAudit ? 'Fairness' : 'Health',
                      response.displayScoreLabel,
                    ),
                    pw.SizedBox(width: 8),
                    _metricChip('Confidence', response.confidenceLabel),
                    pw.SizedBox(width: 8),
                    _metricChip(
                      isInvoiceAudit ? 'Verdict' : 'Severity',
                      isInvoiceAudit
                          ? (response.verdict ?? 'Audit')
                          : session.severityLabel,
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          _section(
            'Report Details',
            [
              _detailRow('Type', typeLabel),
              _detailRow('Date', session.dateLabel),
              _detailRow('Time', session.timeLabel),
              if (isInvoiceAudit &&
                  response.documentType != null &&
                  response.documentType!.isNotEmpty)
                _detailRow('Document', response.documentType!),
              if (session.description != null &&
                  session.description!.isNotEmpty)
                _detailRow(
                  isInvoiceAudit ? 'Visit Purpose' : 'Description',
                  session.description!,
                ),
            ],
          ),
          if (isInvoiceAudit)
            _section(
              'Important',
              [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FFF3E0'),
                    borderRadius: pw.BorderRadius.circular(12),
                    border: pw.Border.all(
                      color: PdfColor.fromHex('#E0A04B'),
                      width: 1,
                    ),
                  ),
                  child: pw.Text(
                    'This audit highlights possible overcharges and upsells. It is not a legal or mechanical diagnosis. Always confirm major repairs with a qualified mechanic or a second opinion.',
                    style: pw.TextStyle(
                      color: PdfColor.fromHex('#6A4300'),
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          _section(isInvoiceAudit ? 'Audit Summary' : 'Summary',
              [pw.Text(response.summary)]),
          if (response.urgencyNote != null && response.urgencyNote!.isNotEmpty)
            _section(
              'Urgency',
              [
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FFF1F1'),
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Text(
                    response.urgencyNote!,
                    style: pw.TextStyle(color: PdfColor.fromHex('#B72A2A')),
                  ),
                ),
              ],
            ),
          if (session.symptoms.isNotEmpty)
            _section(
              'Symptoms',
              session.symptoms.map(_bulletText).toList(),
            ),
          if (!isInvoiceAudit && response.possibleCauses.isNotEmpty)
            _section(
              'Possible Causes',
              response.possibleCauses.map(_bulletText).toList(),
            ),
          if (isInvoiceAudit && response.topFlags.isNotEmpty)
            _section(
              'Top Flags',
              response.topFlags.map(_bulletText).toList(),
            ),
          if (isInvoiceAudit && response.lineItemAudit.isNotEmpty)
            _section(
              'Line Item Audit',
              response.lineItemAudit
                  .map(
                    (item) => pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F6F7FB'),
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            '${item.item}${item.charge.isNotEmpty ? ' - ${item.charge}' : ''}',
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            item.assessment,
                            style: pw.TextStyle(
                              color: PdfColor.fromHex('#2357A5'),
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(item.reason),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Confidence: ${item.confidence}',
                            style: pw.TextStyle(color: PdfColors.grey700),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (isInvoiceAudit && response.paddingPatternsDetected.isNotEmpty)
            _section(
              'Padding Patterns Detected',
              response.paddingPatternsDetected.map(_bulletText).toList(),
            ),
          if (response.recommendations.isNotEmpty)
            _section(
              isInvoiceAudit ? 'Next Steps' : 'Recommendations',
              response.recommendations.map(_bulletText).toList(),
            ),
          if (isInvoiceAudit && response.questionsToAsk.isNotEmpty)
            _section(
              'Questions To Ask The Shop',
              response.questionsToAsk.map(_bulletText).toList(),
            ),
          if (isInvoiceAudit &&
              response.negotiationScript != null &&
              response.negotiationScript!.trim().isNotEmpty)
            _section(
              'Negotiation Script',
              [pw.Text(response.negotiationScript!)],
            ),
          if (isInvoiceAudit &&
              (response.limitations?.trim().isNotEmpty ?? false))
            _section(
              'Limitations',
              [pw.Text(response.limitations!)],
            ),
          if (response.mechanicScript != null &&
              response.mechanicScript!.trim().isNotEmpty)
            _mechanicSection(
              title: isInvoiceAudit
                  ? 'Show This To The Shop'
                  : 'Show This To The Mechanic',
              script: response.mechanicScript!,
            ),
          if (response.subScores.isNotEmpty)
            _section(
              isInvoiceAudit ? 'Fairness Breakdown' : 'Component Scores',
              response.normalizedSubScores.entries
                  .map((entry) => _detailRow(
                        entry.key,
                        response.formatSubScore(entry.value),
                      ))
                  .toList(),
            ),
          pw.SizedBox(height: 26),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Mechanic Signature: __________________',
                style: const pw.TextStyle(fontSize: 11),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Date of Repair: __________________',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );

    return pdf;
  }

  static pw.Widget _metricChip(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#1D1F24'),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              color: PdfColors.grey400,
              fontSize: 9,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _section(String title, List<pw.Widget> children) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  static pw.Widget _mechanicSection({
    required String title,
    required String script,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF7D6'),
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(
                color: PdfColor.fromHex('#D4A100'),
                width: 1,
              ),
            ),
            child: pw.Text(
              script,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10.5,
                color: PdfColor.fromHex('#5E4300'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _detailRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 90,
            child: pw.Text(
              label,
              style: pw.TextStyle(color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(child: pw.Text(value)),
        ],
      ),
    );
  }

  static pw.Widget _bulletText(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, right: 6),
            child: pw.Container(
              width: 4,
              height: 4,
              decoration: const pw.BoxDecoration(
                color: PdfColors.black,
                shape: pw.BoxShape.circle,
              ),
            ),
          ),
          pw.Expanded(child: pw.Text(text)),
        ],
      ),
    );
  }
}
