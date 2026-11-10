import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import '../models/garage_profile.dart';
import '../models/vehicle.dart';
import 'garage_service.dart';
import 'local_store_service.dart';
import 'vehicle_service.dart';

const garageReminderTaskName = 'garage_reminder_reconcile';

@pragma('vm:entry-point')
void garageReminderCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await LocalStoreService.init();
    await VehicleService.instance.load();
    await GarageService.instance.load();
    await ReminderSchedulerService.instance.initialize(
      requestPermissions: false,
      registerWorkmanager: false,
    );
    await ReminderSchedulerService.instance.syncAllProfiles();
    return Future.value(true);
  });
}

class ReminderSchedulerService {
  ReminderSchedulerService._();
  static final instance = ReminderSchedulerService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _workmanagerRegistered = false;

  Future<void> initialize({
    bool requestPermissions = true,
    bool registerWorkmanager = true,
  }) async {
    if (!_initialized) {
      tz_data.initializeTimeZones();
      await _configureLocalTimezone();

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
      );
      await _notifications.initialize(settings: initSettings);
      _initialized = true;
    }

    if (Platform.isAndroid && requestPermissions) {
      final android = _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
    }

    if (Platform.isAndroid &&
        registerWorkmanager &&
        !_workmanagerRegistered) {
      await Workmanager().initialize(
        garageReminderCallbackDispatcher,
      );
      await Workmanager().registerPeriodicTask(
        'fixease-garage-reminders',
        garageReminderTaskName,
        frequency: const Duration(hours: 12),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        constraints: Constraints(
          networkType: NetworkType.notRequired,
        ),
      );
      _workmanagerRegistered = true;
    }
  }

  Future<bool> areNotificationsEnabled() async {
    await initialize(requestPermissions: false);
    if (!Platform.isAndroid) return true;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? false;
  }

  Future<bool> canScheduleExactNotifications() async {
    await initialize(requestPermissions: false);
    if (!Platform.isAndroid) return true;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.canScheduleExactNotifications() ?? true;
  }

  Future<bool> hasReminderPermissions() async {
    final notificationsEnabled = await areNotificationsEnabled();
    final exactAlarmsEnabled = await canScheduleExactNotifications();
    return notificationsEnabled && exactAlarmsEnabled;
  }

  Future<bool> requestReminderPermissions() async {
    await initialize(requestPermissions: false);
    if (!Platform.isAndroid) return true;
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final notificationsGranted =
        await android?.requestNotificationsPermission() ?? true;
    final exactAlarmsGranted =
        await android?.requestExactAlarmsPermission() ?? true;
    return notificationsGranted && exactAlarmsGranted;
  }

  Future<void> syncAllProfiles() async {
    for (final profile in GarageService.instance.profiles) {
      final vehicle = VehicleService.instance.vehicles
          .cast<Vehicle?>()
          .firstWhere(
            (item) => item?.id == profile.vehicleId,
            orElse: () => null,
          );
      await syncVehicleReminders(profile: profile, vehicle: vehicle);
    }
  }

  Future<void> syncVehicleReminders({
    required GarageProfile profile,
    Vehicle? vehicle,
  }) async {
    await initialize(requestPermissions: false);
    await cancelVehicleReminders(profile.vehicleId);

    final now = DateTime.now();
    final oilDate = profile.oilDueDate;
    final tireDate = profile.tireDueDate;
    final registrationDate = profile.registrationDueDate;

    await _scheduleIfFuture(
      id: _notificationId(profile.vehicleId, 1),
      title: 'Oil change due soon',
      body:
          '${vehicle?.displayName ?? 'Your vehicle'} is due for an oil change on ${_formatDate(oilDate)}.',
      fireAt: oilDate.subtract(const Duration(days: 3)),
    );
    if (tireDate != null) {
      await _scheduleIfFuture(
        id: _notificationId(profile.vehicleId, 2),
        title: 'Tire service due soon',
        body:
            '${vehicle?.displayName ?? 'Your vehicle'} may need tire service by ${_formatDate(tireDate)}.',
        fireAt: tireDate.subtract(const Duration(days: 3)),
      );
    }
    if (registrationDate != null) {
      await _scheduleIfFuture(
        id: _notificationId(profile.vehicleId, 3),
        title: 'Registration renewal coming up',
        body:
            '${vehicle?.displayName ?? 'Your vehicle'} registration is due on ${_formatDate(registrationDate)}.',
        fireAt: registrationDate.subtract(const Duration(days: 3)),
      );
    }

    await GarageService.instance.saveProfile(
      profile.copyWith(lastReminderSyncAt: now),
      vehicle: vehicle,
    );
  }

  Future<void> cancelVehicleReminders(String vehicleId) async {
    await initialize(requestPermissions: false);
    await _notifications.cancel(id: _notificationId(vehicleId, 1));
    await _notifications.cancel(id: _notificationId(vehicleId, 2));
    await _notifications.cancel(id: _notificationId(vehicleId, 3));
    await _notifications.cancel(id: _notificationId(vehicleId, 9));
  }

  Future<DateTime> scheduleTestReminder({
    required GarageProfile profile,
    Vehicle? vehicle,
  }) async {
    await initialize();
    final scheduledFor = DateTime.now().add(const Duration(minutes: 2));
    await _scheduleAt(
      id: _notificationId(profile.vehicleId, 9),
      title: 'FixEase offline ping',
      body:
          'Reminder test for ${vehicle?.displayName ?? 'your vehicle'} fired while offline.',
      fireAt: scheduledFor,
    );
    await GarageService.instance.saveProfile(
      profile.copyWith(testReminderScheduledFor: scheduledFor),
      vehicle: vehicle,
    );
    return scheduledFor;
  }

  Future<void> _scheduleIfFuture({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    if (!fireAt.isAfter(DateTime.now())) return;
    await _scheduleAt(
      id: id,
      title: title,
      body: body,
      fireAt: fireAt,
    );
  }

  Future<void> _scheduleAt({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
  }) async {
    final scheduledDate = tz.TZDateTime.from(
      fireAt,
      tz.local,
    );
    await _notifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'garage_reminders',
          'Garage Reminders',
          channelDescription:
              'Offline service and renewal reminders for your vehicle.',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  int _notificationId(String vehicleId, int slot) {
    final base = _stableVehicleHash(vehicleId);
    return base + slot;
  }

  int _stableVehicleHash(String value) {
    var hash = 17;
    for (final unit in value.codeUnits) {
      hash = 37 * hash + unit;
    }
    return hash.abs() % 1000000;
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }
}
