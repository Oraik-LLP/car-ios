import 'package:flutter_test/flutter_test.dart';
import 'package:fixease/models/vehicle.dart';

void main() {
  group('Vehicle VIN persistence', () {
    test('round-trips a saved VIN', () {
      final vehicle = Vehicle(
        id: 'vehicle-1',
        make: 'Honda',
        model: 'BR-V',
        year: 2018,
        vin: 'MAKDG183GJ4006399',
      );

      final restored = Vehicle.fromJson(vehicle.toJson());

      expect(restored.vin, 'MAKDG183GJ4006399');
    });

    test('loads older saved vehicle data without a VIN', () {
      final restored = Vehicle.fromJson({
        'id': 'vehicle-1',
        'make': 'Honda',
        'model': 'BR-V',
        'year': 2018,
      });

      expect(restored.vin, isNull);
    });

    test('can remove an optional VIN later', () {
      final vehicle = Vehicle(
        id: 'vehicle-1',
        make: 'Honda',
        model: 'BR-V',
        year: 2018,
        vin: 'MAKDG183GJ4006399',
      );

      expect(vehicle.copyWith(clearVin: true).vin, isNull);
    });
  });
}
