import 'package:flutter/foundation.dart';

import '../models/vehicle.dart';
import 'local_store_service.dart';

/// In-memory + on-device vehicle store.
class VehicleService extends ChangeNotifier {
  VehicleService._();
  static final instance = VehicleService._();
  static const _storageKey = 'vehicles.v1';

  final List<Vehicle> _vehicles = [];
  Vehicle? _selected;

  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);
  Vehicle? get selected => _selected;
  bool get hasVehicles => _vehicles.isNotEmpty;

  Future<void> load() async {
    final rows = LocalStoreService.readJsonList(_storageKey);
    _vehicles
      ..clear()
      ..addAll(rows.map(Vehicle.fromJson));
    _selected = _vehicles.isNotEmpty ? _vehicles.first : null;
    notifyListeners();
  }

  Future<void> add(Vehicle v) async {
    _vehicles.insert(0, v);
    _selected = v;
    notifyListeners();
    await _persist();
  }

  Future<void> upsert(Vehicle vehicle) async {
    final index = _vehicles.indexWhere((item) => item.id == vehicle.id);
    if (index == -1) {
      _vehicles.insert(0, vehicle);
    } else {
      _vehicles[index] = vehicle;
    }
    if (_selected?.id == vehicle.id) {
      _selected = vehicle;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> remove(String id) async {
    _vehicles.removeWhere((v) => v.id == id);
    if (_selected?.id == id) {
      _selected = _vehicles.isNotEmpty ? _vehicles.first : null;
    }
    notifyListeners();
    await _persist();
  }

  void select(Vehicle v) {
    _selected = v;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() {
    return LocalStoreService.writeJsonList(
      _storageKey,
      _vehicles.map((v) => v.toJson()).toList(),
    );
  }
}
