import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/garage_profile.dart';
import '../../models/vehicle.dart';
import '../vehicle/add_vehicle_screen.dart';
import '../vehicle/my_vehicles_screen.dart';
import '../../services/garage_service.dart';
import '../../services/reminder_scheduler_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neuomorphic.dart';

class GarageTabBody extends StatefulWidget {
  const GarageTabBody({super.key});

  @override
  State<GarageTabBody> createState() => _GarageTabBodyState();
}

class _GarageTabBodyState extends State<GarageTabBody> {
  int? _editingStep;
  bool _syncingReminders = false;
  String? _promptCheckedVehicleId;
  bool _suppressNextGaragePrompt = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        VehicleService.instance,
        GarageService.instance,
      ]),
      builder: (context, _) {
        final vehicle = VehicleService.instance.selected;
        final profile = vehicle == null
            ? null
            : GarageService.instance.profileForVehicle(vehicle.id);

        if (vehicle == null) {
          return const _GarageNoVehicleState();
        }

        if (profile == null || _editingStep != null) {
          return GarageSetupWizard(
            vehicle: vehicle,
            existing: profile,
            initialStep: _editingStep ?? 0,
            editSingleStep: _editingStep != null,
            onSaved: (savedProfile) async {
              await GarageService.instance.saveProfile(
                savedProfile,
                vehicle: vehicle,
              );
              if (!mounted) return;
              _promptCheckedVehicleId = null;
              _suppressNextGaragePrompt = true;
              setState(() => _editingStep = null);
            },
            onCancel: profile == null
                ? null
                : () {
                    setState(() => _editingStep = null);
                  },
          );
        }

        _maybePromptForReminders(
          vehicle: vehicle,
          profile: profile,
        );

        return _GarageDashboard(
          vehicle: vehicle,
          profile: profile,
          remindersEnabled:
              ReminderSchedulerService.instance.hasReminderPermissions(),
          syncingReminders: _syncingReminders,
          onEnableReminders: () => _enableRemindersFromDashboard(
            vehicle: vehicle,
            profile: profile,
          ),
          onMarkOilDone: () => _markOilServiceDone(
            vehicle: vehicle,
            profile: profile,
          ),
          onEditSection: (step) => setState(() => _editingStep = step),
        );
      },
    );
  }

  Future<void> _enableRemindersFromDashboard({
    required Vehicle vehicle,
    required GarageProfile profile,
  }) async {
    final message = await _showReminderPermissionSheet(
      vehicle: vehicle,
      profile: profile,
      markPromptHandled: false,
    );
    if (mounted && message != null && message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _maybePromptForReminders({
    required Vehicle vehicle,
    required GarageProfile profile,
  }) async {
    if (_editingStep != null) return;
    if (_suppressNextGaragePrompt) {
      _suppressNextGaragePrompt = false;
      return;
    }
    if (_promptCheckedVehicleId == vehicle.id) return;
    _promptCheckedVehicleId = vehicle.id;

    final wasHandled =
        GarageService.instance.wasReminderPromptHandled(vehicle.id);
    if (wasHandled) return;

    final enabled =
        await ReminderSchedulerService.instance.hasReminderPermissions();
    if (enabled) {
      await GarageService.instance.markReminderPromptHandled(vehicle.id);
      return;
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showReminderPermissionSheet(
        vehicle: vehicle,
        profile: profile,
        markPromptHandled: true,
      );
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<String?> _showReminderPermissionSheet({
    required Vehicle vehicle,
    required GarageProfile profile,
    required bool markPromptHandled,
  }) async {
    final tt = Theme.of(context).textTheme;
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: SafeArea(
            top: false,
            child: NeuPane(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Turn On Local Reminders?', style: tt.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    'FixEase can remind you about oil, tire, and registration dates right on this phone. Nothing is sent to a server, and you can turn this on later from Garage too.',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: NeuSecondaryButton(
                          label: 'Not Now',
                          onPressed: () async {
                            if (markPromptHandled) {
                              await GarageService.instance
                                  .markReminderPromptHandled(vehicle.id);
                            }
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NeuPrimaryButton(
                          label: 'Enable',
                          icon: Icons.notifications_active_rounded,
                          onPressed: () async {
                            if (_syncingReminders) return;
                            setState(() => _syncingReminders = true);
                            final granted = await ReminderSchedulerService
                                .instance
                                .requestReminderPermissions();
                            if (granted) {
                              await ReminderSchedulerService.instance
                                  .syncVehicleReminders(
                                profile: profile,
                                vehicle: vehicle,
                              );
                            }
                            if (!sheetContext.mounted) return;
                            if (markPromptHandled) {
                              await GarageService.instance
                                  .markReminderPromptHandled(vehicle.id);
                            }
                            if (!sheetContext.mounted) return;
                            Navigator.of(sheetContext).pop(
                              granted
                                  ? 'Local reminders are now enabled for ${vehicle.displayName}.'
                                  : 'Reminders stayed off. You can enable them later from Garage.',
                            );
                            if (mounted) {
                              setState(() => _syncingReminders = false);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (markPromptHandled) {
      await GarageService.instance.markReminderPromptHandled(vehicle.id);
    }
    return result;
  }

  Future<void> _markOilServiceDone({
    required Vehicle vehicle,
    required GarageProfile profile,
  }) async {
    final now = DateTime.now();
    final updatedProfile = profile.copyWith(
      lastOilChangeDate: now,
      lastOilChangeMileageKm: profile.currentMileageKm,
      updatedAt: now,
    );

    await GarageService.instance.saveProfile(
      updatedProfile,
      vehicle: vehicle.copyWith(
        mileageKm: profile.currentMileageKm,
        lastServiceDate: now,
      ),
    );

    final remindersEnabled =
        await ReminderSchedulerService.instance.hasReminderPermissions();
    if (remindersEnabled) {
      await ReminderSchedulerService.instance.syncVehicleReminders(
        profile: updatedProfile,
        vehicle: vehicle.copyWith(
          mileageKm: profile.currentMileageKm,
          lastServiceDate: now,
        ),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Oil change marked as done. Garage reminders updated.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _GarageDashboard extends StatelessWidget {
  const _GarageDashboard({
    required this.vehicle,
    required this.profile,
    required this.remindersEnabled,
    required this.syncingReminders,
    required this.onEnableReminders,
    required this.onMarkOilDone,
    required this.onEditSection,
  });

  final Vehicle vehicle;
  final GarageProfile profile;
  final Future<bool> remindersEnabled;
  final bool syncingReminders;
  final Future<void> Function() onEnableReminders;
  final Future<void> Function() onMarkOilDone;
  final ValueChanged<int> onEditSection;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final oilState = _GarageDueState.forOil(profile);
    final tireState = _GarageDueState.forTires(profile);
    final registrationState = _GarageDueState.forRegistration(profile);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _openReminderDebugSheet(context),
            child: NeuPane(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.garage_rounded,
                          size: 24,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Garage', style: tt.headlineMedium),
                            const SizedBox(height: 4),
                            Text(
                              vehicle.displayName,
                              style: tt.bodyMedium?.copyWith(
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<bool>(
                    future: remindersEnabled,
                    builder: (context, snapshot) {
                      final enabled = snapshot.data ?? false;
                      if (enabled) {
                        return Text(
                          'Local reminders are active on this device.',
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        );
                      }
                      return GestureDetector(
                        onTap: syncingReminders
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                onEnableReminders();
                              },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: AppColors.accent.withValues(alpha: 0.12),
                            border: Border.all(
                              color: AppColors.accent.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                syncingReminders
                                    ? Icons.hourglass_top_rounded
                                    : Icons.notifications_none_rounded,
                                size: 16,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                syncingReminders
                                    ? 'Checking permissions...'
                                    : 'Turn on local reminders',
                                style: tt.bodySmall?.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Stay ahead of service, tire age, and registration with reminders that keep working on-device.',
                    style: tt.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _StatChip(
                        label: 'Mileage',
                        value: '${profile.currentMileageKm} km',
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        label: 'Oil Rule',
                        value:
                            '${profile.oilIntervalMonths} mo / ${profile.oilIntervalKm} km',
                      ),
                    ],
                  ),
                  if (profile.testReminderScheduledFor != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Offline ping armed for ${_formatDateTime(profile.testReminderScheduledFor!)}',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _GarageStatusCard(
            title: 'Oil Change',
            icon: Icons.oil_barrel_rounded,
            detail: 'Due by ${_formatDate(profile.oilDueDate)}',
            secondaryDetail: oilState.secondaryText,
            status: oilState.status,
            onEdit: () => onEditSection(1),
            secondaryActionLabel: 'Mark Done',
            onSecondaryAction: onMarkOilDone,
          ),
          const SizedBox(height: 12),
          _GarageStatusCard(
            title: 'Tire Check',
            icon: Icons.tire_repair_rounded,
            detail: tireState.primaryText,
            secondaryDetail: tireState.secondaryText,
            status: tireState.status,
            onEdit: () => onEditSection(3),
          ),
          const SizedBox(height: 12),
          _GarageStatusCard(
            title: 'Registration',
            icon: Icons.badge_rounded,
            detail: registrationState.primaryText,
            secondaryDetail: registrationState.secondaryText,
            status: registrationState.status,
            onEdit: () => onEditSection(4),
          ),
        ],
      ),
    );
  }

  Future<void> _openReminderDebugSheet(BuildContext context) async {
    final tt = Theme.of(context).textTheme;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: NeuPane(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reminder Test', style: tt.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Schedule an offline ping for 2 minutes from now to verify local delivery in Airplane Mode.',
                  style: tt.bodyMedium,
                ),
                const SizedBox(height: 16),
                NeuPrimaryButton(
                  label: 'Schedule 2-Minute Ping',
                  icon: Icons.notifications_active_rounded,
                  onPressed: () async {
                    final scheduledFor =
                        await ReminderSchedulerService.instance.scheduleTestReminder(
                      profile: profile,
                      vehicle: vehicle,
                    );
                    if (!sheetContext.mounted) return;
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Offline ping set for ${_formatDateTime(scheduledFor)}',
                        ),
                        behavior: SnackBarBehavior.floating,
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
}

class _GarageNoVehicleState extends StatelessWidget {
  const _GarageNoVehicleState();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: NeuPane(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.garage_rounded,
                  size: 34,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 18),
              Text('Build Your Garage', style: tt.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Add or select a vehicle first so FixEase can track upcoming oil changes, tire age, and registration reminders locally.',
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              NeuPrimaryButton(
                label: 'Add Vehicle',
                icon: Icons.add_rounded,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AddVehicleScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              NeuSecondaryButton(
                label: 'My Vehicles',
                icon: Icons.directions_car_rounded,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MyVehiclesScreen(),
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
}

class GarageSetupWizard extends StatefulWidget {
  const GarageSetupWizard({
    super.key,
    required this.vehicle,
    required this.onSaved,
    this.existing,
    this.initialStep = 0,
    this.editSingleStep = false,
    this.onCancel,
  });

  final Vehicle vehicle;
  final GarageProfile? existing;
  final int initialStep;
  final bool editSingleStep;
  final Future<void> Function(GarageProfile profile) onSaved;
  final VoidCallback? onCancel;

  @override
  State<GarageSetupWizard> createState() => _GarageSetupWizardState();
}

class _GarageSetupWizardState extends State<GarageSetupWizard> {
  late int _step;
  late final TextEditingController _mileageCtrl;
  late final TextEditingController _oilMileageCtrl;
  late DateTime _lastOilChangeDate;
  bool _tiresOlderThanFourYears = false;
  DateTime? _tireInstalledDate;
  DateTime? _registrationDueDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _step = widget.initialStep.clamp(0, 4);
    _mileageCtrl = TextEditingController(
      text: (existing?.currentMileageKm ?? widget.vehicle.mileageKm).toString(),
    );
    _oilMileageCtrl = TextEditingController(
      text: (existing?.lastOilChangeMileageKm ?? widget.vehicle.mileageKm)
          .toString(),
    );
    _lastOilChangeDate =
        existing?.lastOilChangeDate ?? widget.vehicle.lastServiceDate ?? DateTime.now();
    _tiresOlderThanFourYears = existing?.tiresOlderThanFourYears ?? false;
    _tireInstalledDate = existing?.tireInstalledDate;
    _registrationDueDate = existing?.registrationDueDate;
  }

  @override
  void dispose() {
    _mileageCtrl.dispose();
    _oilMileageCtrl.dispose();
    super.dispose();
  }

  bool get _canContinue {
    switch (_step) {
      case 0:
        return true;
      case 1:
        return true;
      case 2:
        return true;
      case 3:
        return true;
      case 4:
        return true;
      default:
        return false;
    }
  }

  Future<void> _next() async {
    if (!_canContinue || _saving) return;
    HapticFeedback.selectionClick();
    if (!widget.editSingleStep && _step < 4) {
      setState(() => _step += 1);
      return;
    }

    setState(() => _saving = true);
    final mileage = int.tryParse(_mileageCtrl.text.trim()) ?? widget.vehicle.mileageKm;
    final oilMileage =
        int.tryParse(_oilMileageCtrl.text.trim()) ?? mileage;
    final now = DateTime.now();
    final profile = GarageProfile(
      vehicleId: widget.vehicle.id,
      currentMileageKm: mileage,
      lastOilChangeDate: _lastOilChangeDate,
      lastOilChangeMileageKm: oilMileage,
      oilIntervalMonths: widget.existing?.oilIntervalMonths ?? 6,
      oilIntervalKm: widget.existing?.oilIntervalKm ?? 8000,
      tiresOlderThanFourYears: _tiresOlderThanFourYears,
      tireInstalledDate: _tiresOlderThanFourYears ? null : _tireInstalledDate,
      registrationDueDate: _registrationDueDate,
      lastReminderSyncAt: widget.existing?.lastReminderSyncAt,
      testReminderScheduledFor: widget.existing?.testReminderScheduledFor,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.onSaved(profile);
    if (!mounted) return;
    setState(() => _saving = false);
  }

  void _back() {
    HapticFeedback.lightImpact();
    if (_step > 0) {
      setState(() => _step -= 1);
      return;
    }
    widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
          child: Row(
            children: [
              if (!_saving && (widget.onCancel != null || _step > 0))
                FixEaseStepBackButton(onPressed: _back),
              const Spacer(),
              if (!_saving) Text('Step ${_step + 1} of 5', style: tt.bodySmall),
            ],
          ),
        ),
        if (!_saving && !widget.editSingleStep)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (_step + 1) / 5,
                minHeight: 4,
                backgroundColor: AppColors.surfaceHighlight,
                color: AppColors.accent,
              ),
            ),
          ),
        Expanded(
          child: _saving
              ? _GarageSavingState(vehicle: widget.vehicle)
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: switch (_step) {
                      0 => _WizardStep(
                          key: const ValueKey('garage-mileage'),
                          title: 'Current Mileage',
                          description:
                              'How many kilometers are on the vehicle right now?',
                          editMode: widget.editSingleStep,
                          child: NeuTextField(
                            hint: 'Enter current mileage',
                            icon: Icons.speed_rounded,
                            controller: _mileageCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      1 => _WizardStep(
                          key: const ValueKey('garage-oil-date'),
                          title: 'Last Oil Change',
                          description:
                              'When was the oil last changed on this vehicle?',
                          editMode: widget.editSingleStep,
                          child: _DatePromptTile(
                            icon: Icons.event_rounded,
                            label: 'Last oil change date',
                            value: _formatDate(_lastOilChangeDate),
                            onTap: () async {
                              final picked = await _pickDate(
                                context,
                                initial: _lastOilChangeDate,
                              );
                              if (picked == null) return;
                              setState(() => _lastOilChangeDate = picked);
                            },
                          ),
                        ),
                      2 => _WizardStep(
                          key: const ValueKey('garage-oil-mileage'),
                          title: 'Mileage At Oil Change',
                          description:
                              'What mileage was the car at when that oil change happened?',
                          editMode: widget.editSingleStep,
                          child: NeuTextField(
                            hint: 'Mileage at last oil change',
                            icon: Icons.route_rounded,
                            controller: _oilMileageCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      3 => _WizardStep(
                          key: const ValueKey('garage-tires'),
                          title: 'Tire Check',
                          description:
                              'If you know roughly how old the current tires are, FixEase can remind you when an age-based tire check may be worth doing.',
                          editMode: widget.editSingleStep,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _ChoiceTile(
                                      label: 'Yes, already 4+ years',
                                      selected: _tiresOlderThanFourYears,
                                      onTap: () {
                                        setState(() {
                                          _tiresOlderThanFourYears = true;
                                          _tireInstalledDate = null;
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ChoiceTile(
                                      label: 'No, estimate install date',
                                      selected: !_tiresOlderThanFourYears,
                                      onTap: () {
                                        setState(() {
                                          _tiresOlderThanFourYears = false;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              if (!_tiresOlderThanFourYears) ...[
                                const SizedBox(height: 14),
                                _DatePromptTile(
                                  icon: Icons.tire_repair_rounded,
                                  label: 'Approximate tire install date',
                                  value: _tireInstalledDate == null
                                      ? 'Choose approximate date'
                                      : _formatDate(_tireInstalledDate!),
                                  onTap: () async {
                                    final picked = await _pickDate(
                                      context,
                                      initial: _tireInstalledDate ?? DateTime.now(),
                                    );
                                    if (picked == null) return;
                                    setState(() => _tireInstalledDate = picked);
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      _ => _WizardStep(
                          key: const ValueKey('garage-registration'),
                          title: 'Registration Due Date',
                          description:
                              'When does the current registration or renewal expire?',
                          editMode: widget.editSingleStep,
                          child: _DatePromptTile(
                            icon: Icons.badge_rounded,
                            label: 'Registration due date',
                            value: _registrationDueDate == null
                                ? 'Choose due date'
                                : _formatDate(_registrationDueDate!),
                            onTap: () async {
                              final picked = await _pickDate(
                                context,
                                initial: _registrationDueDate ?? DateTime.now(),
                              );
                              if (picked == null) return;
                              setState(() => _registrationDueDate = picked);
                            },
                          ),
                        ),
                    },
                  ),
                ),
        ),
        if (!_saving)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: widget.editSingleStep
                ? Row(
                    children: [
                      Expanded(
                        child: NeuSecondaryButton(
                          label: 'Cancel',
                          onPressed: widget.onCancel ?? _back,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NeuPrimaryButton(
                          label: 'Save Changes',
                          icon: Icons.check_rounded,
                          onPressed: _canContinue ? _next : null,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: NeuSecondaryButton(
                          label: _step == 4 ? 'Skip For Now' : 'Skip',
                          onPressed: _skipCurrentStep,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: NeuPrimaryButton(
                          label: _step == 4 ? 'Save Garage' : 'Continue',
                          icon: _step == 4 ? Icons.check_rounded : null,
                          onPressed: _canContinue ? _next : null,
                        ),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  void _skipCurrentStep() {
    if (_saving) return;
    HapticFeedback.selectionClick();
    switch (_step) {
      case 0:
        if (_mileageCtrl.text.trim().isEmpty) {
          _mileageCtrl.text = widget.vehicle.mileageKm.toString();
        }
        break;
      case 1:
        break;
      case 2:
        if (_oilMileageCtrl.text.trim().isEmpty) {
          _oilMileageCtrl.text =
              (int.tryParse(_mileageCtrl.text.trim()) ?? widget.vehicle.mileageKm)
                  .toString();
        }
        break;
      case 3:
        _tiresOlderThanFourYears = false;
        _tireInstalledDate = null;
        break;
      case 4:
        _registrationDueDate = null;
        break;
    }
    if (_step < 4) {
      setState(() => _step += 1);
      return;
    }
    _next();
  }

  Future<DateTime?> _pickDate(
    BuildContext context, {
    required DateTime initial,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }
}

class _WizardStep extends StatelessWidget {
  const _WizardStep({
    super.key,
    required this.title,
    required this.description,
    required this.child,
    this.editMode = false,
  });

  final String title;
  final String description;
  final Widget child;
  final bool editMode;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(editMode ? 'Edit $title' : title, style: tt.headlineMedium),
        const SizedBox(height: 6),
        Text(description, style: tt.bodyMedium),
        const SizedBox(height: 20),
        child,
      ],
    );
  }
}

class _DatePromptTile extends StatelessWidget {
  const _DatePromptTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: NeuPane(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: tt.bodySmall),
                  const SizedBox(height: 4),
                  Text(value, style: tt.titleMedium),
                ],
              ),
            ),
            const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.14)
              : AppColors.surface,
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.3)
                : const Color(0x0CFFFFFF),
          ),
          boxShadow: const [],
        ),
        child: Text(
          label,
          style: tt.bodyMedium?.copyWith(
            color: selected ? AppColors.accent : AppColors.textPrimary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _GarageSavingState extends StatelessWidget {
  const _GarageSavingState({required this.vehicle});

  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.accent,
                backgroundColor: AppColors.surfaceHighlight,
              ),
            ),
            const SizedBox(height: 24),
            Text('Preparing Garage...', style: tt.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Saving ${vehicle.displayName} locally and scheduling offline reminders for oil, tires, and registration.',
              style: tt.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _GarageStatusCard extends StatelessWidget {
  const _GarageStatusCard({
    required this.title,
    required this.icon,
    required this.detail,
    required this.secondaryDetail,
    required this.status,
    required this.onEdit,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String title;
  final IconData icon;
  final String detail;
  final String secondaryDetail;
  final GarageHealthStatus status;
  final VoidCallback onEdit;
  final String? secondaryActionLabel;
  final Future<void> Function()? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = switch (status) {
      GarageHealthStatus.good => const Color(0xFF4CAF50),
      GarageHealthStatus.dueSoon => const Color(0xFFFFC107),
      GarageHealthStatus.overdue => const Color(0xFFFF5252),
    };
    final label = switch (status) {
      GarageHealthStatus.good => 'Good',
      GarageHealthStatus.dueSoon => 'Due Soon',
      GarageHealthStatus.overdue => 'Overdue',
    };

    return NeuPane(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: tt.titleLarge)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: color.withValues(alpha: 0.18),
                      ),
                      child: Text(
                        label,
                        style: tt.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(detail, style: tt.bodyMedium),
                if (secondaryDetail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    secondaryDetail,
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 8,
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onEdit();
                      },
                      child: Text(
                        'Edit',
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (secondaryActionLabel != null && onSecondaryAction != null)
                      GestureDetector(
                        onTap: () async {
                          HapticFeedback.selectionClick();
                          await onSecondaryAction!.call();
                        },
                        child: Text(
                          secondaryActionLabel!,
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.35),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: tt.bodySmall),
          const SizedBox(height: 2),
          Text(value, style: tt.titleSmall),
        ],
      ),
    );
  }
}

class _GarageDueState {
  const _GarageDueState({
    required this.status,
    required this.primaryText,
    required this.secondaryText,
  });

  final GarageHealthStatus status;
  final String primaryText;
  final String secondaryText;

  factory _GarageDueState.forOil(GarageProfile profile) {
    final now = DateTime.now();
    final kmRemaining = profile.oilDueMileageKm - profile.currentMileageKm;
    final dateRemaining = profile.oilDueDate.difference(now).inDays;
    if (kmRemaining <= 0 || profile.oilDueDate.isBefore(now)) {
      return _GarageDueState(
        status: GarageHealthStatus.overdue,
        primaryText:
            'Oil service overdue by ${kmRemaining <= 0 ? '${kmRemaining.abs()} km' : '${dateRemaining.abs()} day(s)'}',
        secondaryText:
            'Target was ${_formatDate(profile.oilDueDate)} or ${profile.oilDueMileageKm} km',
      );
    }
    if (kmRemaining <= 500 || dateRemaining <= 14) {
      return _GarageDueState(
        status: GarageHealthStatus.dueSoon,
        primaryText: 'Oil change is coming up soon',
        secondaryText:
            '$kmRemaining km remaining • due by ${_formatDate(profile.oilDueDate)}',
      );
    }
    return _GarageDueState(
      status: GarageHealthStatus.good,
      primaryText: 'Oil service is comfortably ahead',
      secondaryText:
          '$kmRemaining km remaining • due by ${_formatDate(profile.oilDueDate)}',
    );
  }

  factory _GarageDueState.forTires(GarageProfile profile) {
    final dueDate = profile.tireDueDate;
    if (profile.tiresOlderThanFourYears) {
      return const _GarageDueState(
        status: GarageHealthStatus.overdue,
        primaryText: 'An age-based tire check is due',
        secondaryText: 'Inspect tread, sidewall condition, rotation wear, and age markings.',
      );
    }
    if (dueDate == null) {
      return const _GarageDueState(
        status: GarageHealthStatus.dueSoon,
        primaryText: 'Tire age details not set yet',
        secondaryText: 'Add an approximate install date later if you want age-based reminders.',
      );
    }
    final now = DateTime.now();
    final daysRemaining = dueDate.difference(now).inDays;
    if (daysRemaining < 0) {
      return _GarageDueState(
        status: GarageHealthStatus.overdue,
        primaryText: 'An age-based tire check is overdue',
        secondaryText: 'The 4-year check point passed on ${_formatDate(dueDate)}',
      );
    }
    if (daysRemaining <= 30) {
      return _GarageDueState(
        status: GarageHealthStatus.dueSoon,
        primaryText: 'An age-based tire check is coming up soon',
        secondaryText: 'The 4-year check point lands on ${_formatDate(dueDate)}',
      );
    }
    return _GarageDueState(
      status: GarageHealthStatus.good,
      primaryText: 'Tire age check is not close yet',
      secondaryText: 'The 4-year check point lands on ${_formatDate(dueDate)}',
    );
  }

  factory _GarageDueState.forRegistration(GarageProfile profile) {
    final dueDate = profile.registrationDueDate;
    if (dueDate == null) {
      return const _GarageDueState(
        status: GarageHealthStatus.dueSoon,
        primaryText: 'Registration due date not set yet',
        secondaryText: 'Add the renewal date to activate reminders.',
      );
    }
    final now = DateTime.now();
    final daysRemaining = dueDate.difference(now).inDays;
    if (daysRemaining < 0) {
      return _GarageDueState(
        status: GarageHealthStatus.overdue,
        primaryText: 'Registration renewal is overdue',
        secondaryText: 'Due date was ${_formatDate(dueDate)}',
      );
    }
    if (daysRemaining <= 14) {
      return _GarageDueState(
        status: GarageHealthStatus.dueSoon,
        primaryText: 'Registration renewal is coming up soon',
        secondaryText: 'Due on ${_formatDate(dueDate)}',
      );
    }
    return _GarageDueState(
      status: GarageHealthStatus.good,
      primaryText: 'Registration is current',
      secondaryText: 'Due on ${_formatDate(dueDate)}',
    );
  }
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatDateTime(DateTime value) {
  final date = _formatDate(value);
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$date $hour:$minute';
}
