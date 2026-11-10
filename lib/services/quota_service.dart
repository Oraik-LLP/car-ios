import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/ai_config.dart';
import '../screens/subscription/paywall_screen.dart';
import 'device_identity_service.dart';
import 'subscription_service.dart';

class DiagnosticQuotaStatus {
  const DiagnosticQuotaStatus({
    required this.allowed,
    required this.unlimited,
    required this.limit,
    required this.remaining,
    required this.used,
    required this.windowDays,
    this.resetAt,
    this.reason,
  });

  final bool allowed;
  final bool unlimited;
  final int limit;
  final int remaining;
  final int used;
  final int windowDays;
  final DateTime? resetAt;
  final String? reason;

  factory DiagnosticQuotaStatus.fromJson(Map<String, dynamic> json) {
    return DiagnosticQuotaStatus(
      allowed: json['allowed'] as bool? ?? false,
      unlimited: json['unlimited'] as bool? ?? false,
      limit: json['limit'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      used: json['used'] as int? ?? 0,
      windowDays: (json['window_days'] ?? json['windowDays']) as int? ?? 30,
      resetAt: DateTime.tryParse(
        (json['reset_at'] ?? json['resetAt']) as String? ?? '',
      ),
      reason: json['reason'] as String?,
    );
  }
}

class QuotaService extends ChangeNotifier {
  QuotaService._();

  static final QuotaService instance = QuotaService._();

  DiagnosticQuotaStatus? _status;
  bool _isRefreshing = false;
  String? _lastErrorMessage;

  DiagnosticQuotaStatus? get status => _status;
  bool get isRefreshing => _isRefreshing;
  String? get lastErrorMessage => _lastErrorMessage;
  bool get hasKnownStatus => _status != null;

  int? get diagnosticsRemaining =>
      _status == null || _status!.unlimited ? null : _status!.remaining;
  String? get diagnosticsBadgeLabel {
    final status = _status;
    if (status == null || status.unlimited) return null;
    final noun = status.remaining == 1 ? 'Scan' : 'Scans';
    return '${status.remaining} Free $noun Left';
  }

  String? get diagnosticsSubtitleLabel {
    final status = _status;
    if (status == null || status.unlimited) return null;
    return _resetSummary(status.resetAt);
  }

  Future<void> refreshStatus() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    notifyListeners();

    try {
      _status = await fetchStatus();
      _lastErrorMessage = null;
    } catch (error) {
      _lastErrorMessage = error.toString().replaceFirst('Exception: ', '');
    } finally {
      _isRefreshing = false;
      notifyListeners();
    }
  }

  Future<DiagnosticQuotaStatus> fetchStatus() async {
    if (!AiConfig.isConfigured) {
      throw Exception(
        'FixEase could not verify your scan quota because the backend is unavailable.',
      );
    }

    final deviceId = await DeviceIdentityService.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception(
        'FixEase could not verify this device for scan access. Please restart the app and try again.',
      );
    }

    final response = await http.get(
      AiConfig.endpoint('/api/quota/diagnostics/status'),
      headers: {
        'Content-Type': 'application/json',
        'x-fixease-device-id': deviceId,
        ...await SubscriptionService.instance.backendEntitlementHeaders(),
      },
    ).timeout(const Duration(seconds: 15));

    final payload = _parseJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload['message'] as String? ??
            'FixEase could not verify your scan quota right now.',
      );
    }

    final quotaJson = payload['quota'] as Map<String, dynamic>? ?? payload;
    return DiagnosticQuotaStatus.fromJson(Map<String, dynamic>.from(quotaJson));
  }

  Future<bool> ensureCanStartDiagnosis(BuildContext context) async {
    try {
      final nextStatus = await fetchStatus();
      _status = nextStatus;
      _lastErrorMessage = null;
      notifyListeners();

      if (nextStatus.allowed) {
        return true;
      }

      if (!context.mounted) return false;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const PaywallScreen(
            requiredFeature: 'More diagnostics',
          ),
        ),
      );
      return false;
    } catch (error) {
      _lastErrorMessage = error.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      if (!context.mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_lastErrorMessage!),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }
  }

  Future<void> resetForTesting() async {
    if (!AiConfig.isConfigured) {
      throw Exception(
        'FixEase could not reset free scan credits because the backend is unavailable.',
      );
    }

    final deviceId = await DeviceIdentityService.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception(
        'FixEase could not verify this device for test reset. Please restart the app and try again.',
      );
    }

    final response = await http
        .post(
          AiConfig.endpoint('/api/quota/diagnostics/reset'),
          headers: {
            'Content-Type': 'application/json',
            'x-fixease-device-id': deviceId,
            ...await SubscriptionService.instance.backendEntitlementHeaders(),
            'x-fixease-testing-reset': 'true',
          },
        )
        .timeout(const Duration(seconds: 15));

    final payload = _parseJsonMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        payload['message'] as String? ??
            'FixEase could not reset the free scan quota right now.',
      );
    }

    final quotaJson = payload['quota'] as Map<String, dynamic>? ?? payload;
    _status = DiagnosticQuotaStatus.fromJson(Map<String, dynamic>.from(quotaJson));
    _lastErrorMessage = null;
    notifyListeners();
  }

  Map<String, dynamic> _parseJsonMap(String raw) {
    if (raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return Map<String, dynamic>.from(decoded);
  }


  String? _resetSummary(DateTime? resetAt) {
    if (resetAt == null) return null;

    final remaining = resetAt.toUtc().difference(DateTime.now().toUtc());
    if (remaining.isNegative) {
      return 'Reset updating...';
    }

    if (remaining.inHours < 1) {
      final minutes = remaining.inMinutes.clamp(1, 59);
      return 'Resets in $minutes min';
    }

    if (remaining.inHours < 24) {
      return 'Resets in ${remaining.inHours}h';
    }

    if (remaining.inDays < 14) {
      final days = (remaining.inHours / 24).ceil();
      return 'Resets in $days day${days == 1 ? '' : 's'}';
    }

    final localReset = resetAt.toLocal();
    return 'Resets on ${_monthName(localReset.month)} ${localReset.day}';
  }

  String _monthName(int month) {
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[(month - 1).clamp(0, months.length - 1)];
  }
}
