import 'package:flutter/foundation.dart';

import '../models/diagnostic.dart';
import 'conversation_service.dart';
import 'local_store_service.dart';
import 'subscription_service.dart';

/// Manages diagnostic sessions on-device.
class DiagnosticService extends ChangeNotifier {
  DiagnosticService._();
  static final instance = DiagnosticService._();
  static const _storageKey = 'diagnostics.v1';
  static const _historyKey = 'diagnostics.history.v1';

  final List<DiagnosticSession> _sessions = [];
  final List<String> _historyOrder = [];

  List<DiagnosticSession> get sessions => List.unmodifiable(_sessions);

  int reportCountForCurrentMonth() {
    final now = DateTime.now();
    return _sessions.where((session) {
      if (session.type == DiagnosticType.live || session.isObd) return false;
      return session.createdAt.year == now.year &&
          session.createdAt.month == now.month;
    }).length;
  }

  bool isNewestSession(DiagnosticSession session) {
    return _sessions.isNotEmpty && identical(_sessions.first, session) ||
        (_sessions.isNotEmpty && _sessions.first.id == session.id);
  }

  bool isWithinMostRecentSessions(
    DiagnosticSession session, {
    int allowedCount = 2,
  }) {
    if (_historyOrder.isEmpty) return false;
    final index = _historyOrder.indexOf(session.id);
    if (index == -1) return false;
    return index < allowedCount;
  }

  bool isOlderThanMostRecentSessions(
    DiagnosticSession session, {
    int allowedCount = 2,
  }) {
    if (_historyOrder.isEmpty) return false;
    final index = _historyOrder.indexOf(session.id);
    if (index == -1) return false;
    return index >= allowedCount;
  }

  bool isOlderThanNewest(DiagnosticSession session) {
    return _sessions.isNotEmpty && _sessions.first.id != session.id;
  }

  List<DiagnosticSession> sessionsForVehicle(String vehicleId) =>
      _sessions.where((s) => s.vehicleId == vehicleId).toList();

  Future<void> load() async {
    final rows = LocalStoreService.readJsonList(_storageKey);
    final history = LocalStoreService.readJsonList(_historyKey)
        .map((row) => row['id'] as String?)
        .whereType<String>()
        .toList();
    _sessions
      ..clear()
      ..addAll(rows.map(DiagnosticSession.fromJson));
    _historyOrder
      ..clear()
      ..addAll(history);
    for (final session in _sessions) {
      if (!_historyOrder.contains(session.id)) {
        _historyOrder.add(session.id);
      }
    }
    notifyListeners();
  }

  Future<void> save(DiagnosticSession s) async {
    final existingIndex = _sessions.indexWhere((session) => session.id == s.id);
    if (existingIndex == -1) {
      _sessions.insert(0, s);
    } else {
      _sessions[existingIndex] = s;
    }
    _historyOrder.remove(s.id);
    _historyOrder.insert(0, s.id);
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    _sessions.removeWhere((s) => s.id == id);
    notifyListeners();
    await ConversationService.instance.deleteForSession(id);
    await SubscriptionService.instance.clearThreadUsage(id);
    await _persist();
  }

  Future<void> deleteAll() async {
    final ids = _sessions.map((session) => session.id).toList();
    _sessions.clear();
    _historyOrder.clear();
    notifyListeners();
    for (final id in ids) {
      await ConversationService.instance.deleteForSession(id);
    }
    await SubscriptionService.instance.clearThreadUsageForAll(ids);
    await _persist();
  }

  Future<void> _persist() {
    return Future.wait([
      LocalStoreService.writeJsonList(
        _storageKey,
        _sessions.map((s) => s.toJson()).toList(),
      ),
      LocalStoreService.writeJsonList(
        _historyKey,
        _historyOrder.map((id) => {'id': id}).toList(),
      ),
    ]);
  }
}
