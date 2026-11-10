enum GarageHealthStatus { good, dueSoon, overdue }

class GarageProfile {
  const GarageProfile({
    required this.vehicleId,
    required this.currentMileageKm,
    required this.lastOilChangeDate,
    required this.lastOilChangeMileageKm,
    this.oilIntervalMonths = 6,
    this.oilIntervalKm = 8000,
    this.tiresOlderThanFourYears = false,
    this.tireInstalledDate,
    this.registrationDueDate,
    this.lastReminderSyncAt,
    this.testReminderScheduledFor,
    required this.createdAt,
    required this.updatedAt,
  });

  final String vehicleId;
  final int currentMileageKm;
  final DateTime lastOilChangeDate;
  final int lastOilChangeMileageKm;
  final int oilIntervalMonths;
  final int oilIntervalKm;
  final bool tiresOlderThanFourYears;
  final DateTime? tireInstalledDate;
  final DateTime? registrationDueDate;
  final DateTime? lastReminderSyncAt;
  final DateTime? testReminderScheduledFor;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get oilDueDate => _addMonths(lastOilChangeDate, oilIntervalMonths);

  int get oilDueMileageKm => lastOilChangeMileageKm + oilIntervalKm;

  DateTime? get tireDueDate {
    if (tiresOlderThanFourYears) {
      return DateTime.now().subtract(const Duration(days: 1));
    }
    if (tireInstalledDate == null) return null;
    return _addMonths(tireInstalledDate!, 48);
  }

  GarageProfile copyWith({
    int? currentMileageKm,
    DateTime? lastOilChangeDate,
    int? lastOilChangeMileageKm,
    int? oilIntervalMonths,
    int? oilIntervalKm,
    bool? tiresOlderThanFourYears,
    DateTime? tireInstalledDate,
    bool clearTireInstalledDate = false,
    DateTime? registrationDueDate,
    bool clearRegistrationDueDate = false,
    DateTime? lastReminderSyncAt,
    DateTime? testReminderScheduledFor,
    bool clearTestReminderScheduledFor = false,
    DateTime? updatedAt,
  }) {
    return GarageProfile(
      vehicleId: vehicleId,
      currentMileageKm: currentMileageKm ?? this.currentMileageKm,
      lastOilChangeDate: lastOilChangeDate ?? this.lastOilChangeDate,
      lastOilChangeMileageKm:
          lastOilChangeMileageKm ?? this.lastOilChangeMileageKm,
      oilIntervalMonths: oilIntervalMonths ?? this.oilIntervalMonths,
      oilIntervalKm: oilIntervalKm ?? this.oilIntervalKm,
      tiresOlderThanFourYears:
          tiresOlderThanFourYears ?? this.tiresOlderThanFourYears,
      tireInstalledDate: clearTireInstalledDate
          ? null
          : tireInstalledDate ?? this.tireInstalledDate,
      registrationDueDate: clearRegistrationDueDate
          ? null
          : registrationDueDate ?? this.registrationDueDate,
      lastReminderSyncAt: lastReminderSyncAt ?? this.lastReminderSyncAt,
      testReminderScheduledFor: clearTestReminderScheduledFor
          ? null
          : testReminderScheduledFor ?? this.testReminderScheduledFor,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'vehicle_id': vehicleId,
        'current_mileage_km': currentMileageKm,
        'last_oil_change_date': lastOilChangeDate.toIso8601String(),
        'last_oil_change_mileage_km': lastOilChangeMileageKm,
        'oil_interval_months': oilIntervalMonths,
        'oil_interval_km': oilIntervalKm,
        'tires_older_than_four_years': tiresOlderThanFourYears,
        'tire_installed_date': tireInstalledDate?.toIso8601String(),
        'registration_due_date': registrationDueDate?.toIso8601String(),
        'last_reminder_sync_at': lastReminderSyncAt?.toIso8601String(),
        'test_reminder_scheduled_for': testReminderScheduledFor?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory GarageProfile.fromJson(Map<String, dynamic> json) {
    return GarageProfile(
      vehicleId: json['vehicle_id'] as String,
      currentMileageKm: json['current_mileage_km'] as int? ?? 0,
      lastOilChangeDate: DateTime.tryParse(
            json['last_oil_change_date'] as String? ?? '',
          ) ??
          DateTime.now(),
      lastOilChangeMileageKm:
          json['last_oil_change_mileage_km'] as int? ?? 0,
      oilIntervalMonths: json['oil_interval_months'] as int? ?? 6,
      oilIntervalKm: json['oil_interval_km'] as int? ?? 8000,
      tiresOlderThanFourYears:
          json['tires_older_than_four_years'] as bool? ?? false,
      tireInstalledDate: json['tire_installed_date'] != null
          ? DateTime.tryParse(json['tire_installed_date'] as String)
          : null,
      registrationDueDate: json['registration_due_date'] != null
          ? DateTime.tryParse(json['registration_due_date'] as String)
          : null,
      lastReminderSyncAt: json['last_reminder_sync_at'] != null
          ? DateTime.tryParse(json['last_reminder_sync_at'] as String)
          : null,
      testReminderScheduledFor: json['test_reminder_scheduled_for'] != null
          ? DateTime.tryParse(json['test_reminder_scheduled_for'] as String)
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static DateTime _addMonths(DateTime date, int months) {
    final rawMonth = date.month + months;
    final year = date.year + ((rawMonth - 1) ~/ 12);
    final month = ((rawMonth - 1) % 12) + 1;
    final day = date.day > 28 ? 28 : date.day;
    return DateTime(year, month, day, date.hour, date.minute, date.second);
  }
}
