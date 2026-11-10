import 'package:flutter/foundation.dart';

import '../models/conversation.dart';
import 'local_store_service.dart';

/// Manages saved conversation threads on-device.
class ConversationService extends ChangeNotifier {
  ConversationService._();
  static final instance = ConversationService._();
  static const _storageKey = 'conversations.v1';

  final Map<String, ConversationThread> _threads = {};

  List<ConversationThread> get threads =>
      _threads.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ConversationThread? threadForSession(String sessionId) => _threads[sessionId];

  Future<void> load() async {
    final rows = LocalStoreService.readJsonList(_storageKey);
    _threads
      ..clear()
      ..addEntries(
        rows.map((row) {
          final thread = ConversationThread.fromJson(row);
          return MapEntry(thread.sessionId, thread);
        }),
      );
    notifyListeners();
  }

  Future<ConversationThread> createOrGetThread({
    required String sessionId,
    required String vehicleId,
  }) async {
    final existing = _threads[sessionId];
    if (existing != null) return existing;

    final thread = ConversationThread(
      sessionId: sessionId,
      vehicleId: vehicleId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _threads[sessionId] = thread;
    notifyListeners();
    await _persist();
    return thread;
  }

  Future<void> appendMessage({
    required String sessionId,
    required String vehicleId,
    required ConversationMessage message,
  }) async {
    final thread = await createOrGetThread(
      sessionId: sessionId,
      vehicleId: vehicleId,
    );
    _threads[sessionId] = thread.copyWith(
      updatedAt: message.createdAt,
      messages: [...thread.messages, message],
    );
    notifyListeners();
    await _persist();
  }

  Future<void> deleteForSession(String sessionId) async {
    if (_threads.remove(sessionId) == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() {
    return LocalStoreService.writeJsonList(
      _storageKey,
      _threads.values.map((thread) => thread.toJson()).toList(),
    );
  }
}
