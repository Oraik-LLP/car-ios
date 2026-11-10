import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/obd.dart';
import '../../services/diagnostic_service.dart';
import '../../services/obd_pro_service.dart';
import '../../services/subscription_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neuomorphic.dart';
import '../reports/report_detail_screen.dart';

Future<void> launchObdProSuite(BuildContext context) async {
  final vehicle = VehicleService.instance.selected;
  if (vehicle == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a vehicle first')),
    );
    return;
  }

  if (!Platform.isAndroid) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OBD Pro is Android-only in this build.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final unlocked = await ensureAccess(
    context,
    FeatureType.obdProSuite,
    reason: 'OBD Pro Diagnostic Suite',
  );
  if (!unlocked || !context.mounted) {
    return;
  }

  await ObdProService.instance.ensurePermissionsAndLoadDevices();
  if (!context.mounted) {
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const ObdProDashboardScreen(),
    ),
  );
}

class ObdProDashboardScreen extends StatefulWidget {
  const ObdProDashboardScreen({super.key});

  @override
  State<ObdProDashboardScreen> createState() => _ObdProDashboardScreenState();
}

class _ObdProDashboardScreenState extends State<ObdProDashboardScreen> {
  final GlobalKey _scanControlsKey = GlobalKey();
  bool _wasScanActive = false;

  void _scrollToActiveScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scanContext = _scanControlsKey.currentContext;
      if (scanContext == null) return;
      Scrollable.ensureVisible(
        scanContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ObdProService.instance.ensurePermissionsAndLoadDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final vehicle = VehicleService.instance.selected;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: ObdProService.instance,
            builder: (context, _) {
              final service = ObdProService.instance;
              final scanIsActive = service.isScanActive;
              if (scanIsActive && !_wasScanActive) {
                _wasScanActive = true;
                _scrollToActiveScan();
              } else if (!scanIsActive) {
                _wasScanActive = false;
              }
              final idleInsight = vehicle == null
                  ? null
                  : service.latestInsightForVehicle(
                      vehicle.id, ObdScanKind.idle);
              final driveInsight = vehicle == null
                  ? null
                  : service.latestInsightForVehicle(
                      vehicle.id, ObdScanKind.drive);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                    child: Row(
                      children: [
                        FixEaseStepBackButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.accent.withValues(alpha: 0.14),
                          ),
                          child: Text(
                            'PRO',
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('OBD Pro Diagnostic Suite',
                              style: tt.headlineMedium),
                          const SizedBox(height: 6),
                          Text(
                            vehicle?.displayName ?? 'No vehicle selected',
                            style: tt.bodyMedium?.copyWith(
                              color: AppColors.accent,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Keep the app open during active scans. Screen auto-lock is prevented while a scan is running.',
                            style: tt.bodySmall,
                          ),
                          const SizedBox(height: 18),
                          _ConnectionCard(service: service),
                          const SizedBox(height: 14),
                          _StatusBanner(service: service),
                          const SizedBox(height: 14),
                          _LiveVitalsSection(service: service),
                          const SizedBox(height: 14),
                          _StaticSnapshotCard(
                            snapshot: service.staticSnapshotForVehicle(
                              vehicle?.id ?? '',
                            ),
                          ),
                          const SizedBox(height: 14),
                          KeyedSubtree(
                            key: _scanControlsKey,
                            child: _ScanControlsCard(service: service),
                          ),
                          const SizedBox(height: 14),
                          _LatestInsightSection(
                            title: 'Latest Idle Diagnosis',
                            insight: idleInsight,
                          ),
                          const SizedBox(height: 14),
                          _LatestInsightSection(
                            title: 'Latest Drive Diagnosis',
                            insight: driveInsight,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.service});

  final ObdProService service;

  @override
  Widget build(BuildContext context) {
    final devices = service.pairedDevices.isNotEmpty
        ? service.pairedDevices
        : service.scanDevices;
    final usingNearbyFallback =
        service.pairedDevices.isEmpty && service.scanDevices.isNotEmpty;
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Connection', style: tt.titleLarge),
              const Spacer(),
              NeuIconButton(
                icon: Icons.refresh_rounded,
                onPressed: service.refreshDevices,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (devices.isEmpty)
            Text(
              'Pair your ELM327 adapter in Android Bluetooth settings, then refresh here.',
              style: tt.bodyMedium,
            )
          else ...[
            if (usingNearbyFallback) ...[
              Text(
                'No paired adapter found yet. Showing nearby Bluetooth devices as a fallback.',
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            NeuDropdown<String>(
              value: service.selectedDevice?.address,
              hint: 'Select your adapter',
              onChanged: (value) {
                final next = devices
                    .where((device) => device.address == value)
                    .firstOrNull;
                service.selectDevice(next);
              },
              items: devices
                  .map(
                    (device) => DropdownMenuItem<String>(
                      value: device.address,
                      child: Text(device.displayName),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: NeuPrimaryButton(
                  label: service.isConnected ? 'Reconnect' : 'Connect',
                  icon: Icons.bluetooth_connected_rounded,
                  onPressed: service.isLoadingDevices ? null : service.connect,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: NeuSecondaryButton(
                  label: 'Disconnect',
                  icon: Icons.link_off_rounded,
                  onPressed: service.isConnected ? service.disconnect : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.service});

  final ObdProService service;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isInterrupted = service.state == ObdSuiteState.interrupted;
    final color = isInterrupted
        ? const Color(0xFFFFB366)
        : service.state == ObdSuiteState.error
            ? const Color(0xFFFF6B6B)
            : AppColors.accent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.12),
        border: Border.all(
          color: color.withValues(alpha: 0.24),
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            service.state.name,
            style: tt.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            service.status,
            style: tt.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
          if (service.errorCode != null) ...[
            const SizedBox(height: 7),
            Text(
              service.errorCode!,
              style: tt.bodySmall?.copyWith(
                color: color,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 3),
            Text(
              service.errorRecovery ?? '',
              style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (service.isScanActive ||
              service.state == ObdSuiteState.interrupted) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: service.scanProgress,
                minHeight: 6,
                backgroundColor: AppColors.surfaceHighlight,
                color: color,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              service.targetDurationSeconds == 0
                  ? 'Waiting for scan to arm'
                  : '${service.capturedDurationSeconds}s / ${service.targetDurationSeconds}s',
              style: tt.bodySmall?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}

class _LiveVitalsSection extends StatelessWidget {
  const _LiveVitalsSection({required this.service});

  final ObdProService service;

  @override
  Widget build(BuildContext context) {
    final vitals = service.liveVitals;
    return Row(
      children: [
        Expanded(
          child: _VitalCard(
            label: 'RPM',
            value: vitals.rpm == null ? '--' : vitals.rpm!.toStringAsFixed(0),
            unit: 'rpm',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _VitalCard(
            label: 'Speed',
            value: vitals.speedKph?.toString() ?? '--',
            unit: 'km/h',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _VitalCard(
            label: 'Coolant',
            value: vitals.coolantTempC == null
                ? '--'
                : vitals.coolantTempC!.toStringAsFixed(0),
            unit: 'C',
          ),
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  const _VitalCard({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          const SizedBox(height: 8),
          Text(
            value,
            style: tt.displayLarge?.copyWith(
              fontSize: 34,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(unit, style: tt.bodySmall),
        ],
      ),
    );
  }
}

class _StaticSnapshotCard extends StatelessWidget {
  const _StaticSnapshotCard({required this.snapshot});

  final ObdStaticSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Static Snapshot', style: tt.titleLarge),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _SnapshotPill(
                label: 'VIN',
                value: snapshot.vin ?? '--',
              ),
              _SnapshotPill(
                label: 'Stored DTCs',
                value: snapshot.storedDtcs.isEmpty
                    ? '0'
                    : snapshot.storedDtcs.join(', '),
              ),
              _SnapshotPill(
                label: 'Pending DTCs',
                value: snapshot.pendingDtcs.isEmpty
                    ? '0'
                    : snapshot.pendingDtcs.join(', '),
              ),
              _SnapshotPill(
                label: 'Battery',
                value: snapshot.controlModuleVoltage == null
                    ? '--'
                    : '${snapshot.controlModuleVoltage!.toStringAsFixed(2)} V',
              ),
              _SnapshotPill(
                label: 'Distance Since Clear',
                value: snapshot.distanceSinceCodesClearedKm == null
                    ? '--'
                    : '${snapshot.distanceSinceCodesClearedKm} km',
              ),
              _SnapshotPill(
                label: 'Ambient Air',
                value: snapshot.ambientAirTempC == null
                    ? '--'
                    : '${snapshot.ambientAirTempC!.toStringAsFixed(0)} C',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SnapshotPill extends StatelessWidget {
  const _SnapshotPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: 156,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.32),
        border: Border.all(color: const Color(0x14FFFFFF), width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanControlsCard extends StatelessWidget {
  const _ScanControlsCard({required this.service});

  final ObdProService service;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final canStart = service.isConnected &&
        service.initCompleted &&
        !service.isScanActive &&
        service.state != ObdSuiteState.finalizing;

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Smart Recording', style: tt.titleLarge),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFFFFB366).withValues(alpha: 0.16),
                ),
                child: Text(
                  'BETA',
                  style: tt.bodySmall?.copyWith(
                    color: const Color(0xFFFFB366),
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Idle Scan requires the vehicle to stay stationary. Drive Scan waits until speed is above 5 km/h before the 2-minute timer begins.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackVertically = constraints.maxWidth < 430;
              if (stackVertically) {
                return Column(
                  children: [
                    NeuPrimaryButton(
                      label: 'Run Idle Health Scan',
                      icon: Icons.air_rounded,
                      onPressed: canStart ? service.startIdleScan : null,
                    ),
                    const SizedBox(height: 10),
                    NeuSecondaryButton(
                      label: 'Run Drive Load Scan',
                      icon: Icons.route_rounded,
                      onPressed: canStart ? service.startDriveScan : null,
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: NeuPrimaryButton(
                      label: 'Run Idle Health Scan',
                      icon: Icons.air_rounded,
                      onPressed: canStart ? service.startIdleScan : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeuSecondaryButton(
                      label: 'Run Drive Load Scan',
                      icon: Icons.route_rounded,
                      onPressed: canStart ? service.startDriveScan : null,
                    ),
                  ),
                ],
              );
            },
          ),
          if (service.isScanActive) ...[
            const SizedBox(height: 10),
            NeuSecondaryButton(
              label: 'Cancel Active Scan',
              icon: Icons.stop_circle_outlined,
              onPressed: service.cancelActiveScan,
            ),
          ],
        ],
      ),
    );
  }
}

class _LatestInsightSection extends StatelessWidget {
  const _LatestInsightSection({
    required this.title,
    required this.insight,
  });

  final String title;
  final ObdInsightRecord? insight;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    if (insight == null) {
      return NeuPane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: tt.titleLarge),
            const SizedBox(height: 8),
            Text('No saved diagnosis yet.', style: tt.bodyMedium),
          ],
        ),
      );
    }

    final session = DiagnosticService.instance.sessions
        .where((item) => item.id == insight!.sessionId)
        .firstOrNull;

    return GestureDetector(
      onTap: session == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportDetailScreen(session: session),
                ),
              );
            },
      child: NeuPane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: tt.titleLarge)),
                if (insight!.isPartial)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFFFFB366).withValues(alpha: 0.16),
                    ),
                    child: Text(
                      'PARTIAL',
                      style: tt.bodySmall?.copyWith(
                        color: const Color(0xFFFFB366),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              insight!.summary,
              style: tt.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricChip(
                  label: 'Duration',
                  value:
                      '${insight!.capturedDurationSeconds}s / ${insight!.targetDurationSeconds}s',
                ),
                _MetricChip(
                  label: 'Captured',
                  value:
                      '${insight!.createdAt.day}/${insight!.createdAt.month} ${insight!.createdAt.hour.toString().padLeft(2, '0')}:${insight!.createdAt.minute.toString().padLeft(2, '0')}',
                ),
              ],
            ),
            if (session != null) ...[
              const SizedBox(height: 10),
              Text(
                'Tap to open full report',
                style: tt.bodySmall?.copyWith(color: AppColors.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.36),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: tt.bodySmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
