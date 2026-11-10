import 'dart:io';

import 'package:flutter/services.dart';

abstract final class DeviceIdentityService {
  static const MethodChannel _channel = MethodChannel('fixease/device');
  static String? _cachedDeviceId;

  static Future<String?> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId;
    }

    if (!Platform.isAndroid) {
      return null;
    }

    final deviceId = await _channel.invokeMethod<String>('getDeviceId');
    if (deviceId == null || deviceId.trim().isEmpty) {
      return null;
    }

    _cachedDeviceId = deviceId.trim();
    return _cachedDeviceId;
  }
}
