import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Small JSON-backed store for keeping app data on-device.
abstract final class LocalStoreService {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static List<Map<String, dynamic>> readJsonList(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic>? readJsonMap(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(
        decoded.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeJsonList(
    String key,
    List<Map<String, dynamic>> value,
  ) async {
    await _prefs?.setString(key, jsonEncode(value));
  }

  static Future<void> writeJsonMap(
    String key,
    Map<String, dynamic> value,
  ) async {
    await _prefs?.setString(key, jsonEncode(value));
  }
}
