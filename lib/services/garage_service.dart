import 'package:flutter/foundation.dart';

import '../models/garage_profile.dart';
import '../models/vehicle.dart';
import 'local_store_service.dart';
import 'vehicle_service.dart';

class GarageService extends ChangeNotifier {
  GarageService._();
  static final instance = GarageService._();
  static const _storageKey = 'garage_profiles.v1';
  static const _reminderPromptStateKey = 'garage_reminder_prompt_state.v1';

  final Map<String, GarageProfile> _profiles = {};

  List<GarageProfile> get profiles =>
      _profiles.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  GarageProfile? profileForVehicle(String vehicleId) => _profiles[vehicleId];

  bool wasReminderPromptHandled(String vehicleId) {
    final state = LocalStoreService.readJsonMap(_reminderPromptStateKey) ?? const {};
    return state[vehicleId] == true;
  }

  Future<void> markReminderPromptHandled(String vehicleId) async {
    final state = Map<String, dynamic>.from(
      LocalStoreService.readJsonMap(_reminderPromptStateKey) ?? const {},
    );
    state[vehicleId] = true;
    await LocalStoreService.writeJsonMap(_reminderPromptStateKey, state);
  }

  Future<void> clearReminderPromptHandled(String vehicleId) async {
    final state = Map<String, dynamic>.from(
      LocalStoreService.readJsonMap(_reminderPromptStateKey) ?? const {},
    );
    if (state.remove(vehicleId) == null) return;
    await LocalStoreService.writeJsonMap(_reminderPromptStateKey, state);
  }

  Future<void> load() async {
    final rows = LocalStoreService.readJsonList(_storageKey);
    _profiles
      ..clear()
      ..addEntries(
        rows.map((row) {
          final profile = GarageProfile.fromJson(row);
          return MapEntry(profile.vehicleId, profile);
        }),
      );
    notifyListeners();
  }

  Future<void> saveProfile(
    GarageProfile profile, {
    Vehicle? vehicle,
  }) async {
    _profiles[profile.vehicleId] = profile.copyWith(updatedAt: DateTime.now());
    if (vehicle != null && vehicle.mileageKm != profile.currentMileageKm) {
      await VehicleService.instance.upsert(
        vehicle.copyWith(mileageKm: profile.currentMileageKm),
      );
    }
    notifyListeners();
    await _persist();
  }

  Future<void> clearTestReminderState(String vehicleId) async {
    final current = _profiles[vehicleId];
    if (current == null) return;
    _profiles[vehicleId] = current.copyWith(
      clearTestReminderScheduledFor: true,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deleteProfile(String vehicleId) async {
    if (_profiles.remove(vehicleId) == null) return;
    await clearReminderPromptHandled(vehicleId);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() {
    return LocalStoreService.writeJsonList(
      _storageKey,
      _profiles.values.map((profile) => profile.toJson()).toList(),
    );
  }
}
