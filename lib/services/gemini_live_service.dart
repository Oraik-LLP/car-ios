import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../config/ai_config.dart';
import '../models/conversation.dart';
import '../models/diagnostic.dart';
import '../models/vehicle.dart';
import 'conversation_service.dart';
import 'device_identity_service.dart';
import 'diagnostic_service.dart';
import 'quota_service.dart';
import 'subscription_service.dart';

enum LiveSessionState { idle, connecting, streaming, analyzing, done, error }

class LiveMessage {
  const LiveMessage({
    required this.text,
    required this.isUser,
    this.timestamp,
    this.source = ConversationMessageSource.text,
    this.attachmentPath,
    this.attachmentName,
    this.includeInHistory = true,
  });

  final String text;
  final bool isUser;
  final DateTime? timestamp;
  final ConversationMessageSource source;
  final String? attachmentPath;
  final String? attachmentName;
  final bool includeInHistory;

  bool get hasAttachment =>
      attachmentPath != null ||
      attachmentName != null ||
      source != ConversationMessageSource.text;

  String get previewText {
    if (text.trim().isNotEmpty) return text.trim();
    return switch (source) {
      ConversationMessageSource.audio => 'Voice note',
      ConversationMessageSource.image => 'Photo sent',
      ConversationMessageSource.file => 'File attached',
      ConversationMessageSource.text => 'Message',
    };
  }

  LiveMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    ConversationMessageSource? source,
    String? attachmentPath,
    String? attachmentName,
    bool? includeInHistory,
  }) {
    return LiveMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      attachmentPath: attachmentPath ?? this.attachmentPath,
      attachmentName: attachmentName ?? this.attachmentName,
      includeInHistory: includeInHistory ?? this.includeInHistory,
    );
  }
}

class _PendingLiveTurn {
  const _PendingLiveTurn({
    required this.messageIndex,
    required this.text,
    required this.source,
    this.attachmentPath,
    this.attachmentName,
  });

  final int messageIndex;
  final String text;
  final ConversationMessageSource source;
  final String? attachmentPath;
  final String? attachmentName;
}

class GeminiLiveService extends ChangeNotifier {
  GeminiLiveService._() {
    _tts = FlutterTts();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.0);
    _tts.awaitSpeakCompletion(true);
    _syncAudioLimit();
  }

  static final GeminiLiveService instance = GeminiLiveService._();

  LiveSessionState _state = LiveSessionState.idle;
  final List<LiveMessage> _messages = [];
  String? _errorMessage;
  Vehicle? _vehicle;
  DateTime? _sessionStart;
  DiagnosticSession? _historySession;
  bool _historySessionSaved = false;
  String? _threadId;
  int _sessionGeneration = 0;
  Map<String, dynamic>? _obdContext;

  final AudioRecorder _recorder = AudioRecorder();
  late final FlutterTts _tts;
  bool _isRecording = false;
  bool _isSpeaking = false;
  bool _isStoppingRecording = false;
  DateTime? _recordingStartedAt;
  Duration _recordingElapsed = Duration.zero;
  Duration _recordingLimit = const Duration(minutes: 3);
  Timer? _recordingTicker;
  int _recordingCapEvents = 0;

  LiveSessionState get state => _state;
  List<LiveMessage> get messages => List.unmodifiable(_messages);
  String? get errorMessage => _errorMessage;
  bool get isRecording => _isRecording;
  bool get isSpeaking => _isSpeaking;
  String? get threadId => _threadId;
  bool get isActive =>
      _state == LiveSessionState.streaming ||
      _state == LiveSessionState.analyzing;
  bool get hasObdContext => _obdContext != null && _obdContext!.isNotEmpty;
  Duration get sessionDuration => _sessionStart != null
      ? DateTime.now().difference(_sessionStart!)
      : Duration.zero;
  Duration get recordingElapsed => _recordingElapsed;
  Duration get recordingLimit => _recordingLimit;
  int get recordingCapEvents => _recordingCapEvents;
  double get recordingProgress {
    if (_recordingLimit.inMilliseconds == 0) return 0;
    return (_recordingElapsed.inMilliseconds / _recordingLimit.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  bool get isNearRecordingLimit {
    if (!_isRecording) return false;
    return _recordingLimit - _recordingElapsed <= const Duration(seconds: 30);
  }

  String get recordingTimeLabel => _formatDuration(_recordingElapsed);
  String get recordingLimitLabel => _formatDuration(_recordingLimit);

  static Future<DeviceCapability> checkCapability() async {
    final hasCamera = Platform.isAndroid || Platform.isIOS;
    final hasNetwork = await _checkBackend();
    final hasBackend = AiConfig.isConfigured;
    return DeviceCapability(
      hasCamera: hasCamera,
      hasNetwork: hasNetwork,
      hasBackend: hasBackend,
    );
  }

  static Future<bool> _checkBackend() async {
    if (!AiConfig.isConfigured) return false;
    try {
      final result = await http
          .get(AiConfig.endpoint('/health'))
          .timeout(const Duration(seconds: 10));
      return result.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> startSession(
    Vehicle vehicle, {
    Map<String, dynamic>? obdContext,
  }) async {
    _sessionGeneration++;
    _vehicle = vehicle;
    _messages.clear();
    _errorMessage = null;
    _sessionStart = DateTime.now();
    _historySession = null;
    _historySessionSaved = false;
    _threadId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _obdContext = obdContext == null ? null : Map<String, dynamic>.from(obdContext);
    _syncAudioLimit();
    _state = LiveSessionState.connecting;
    notifyListeners();

    if (!AiConfig.isConfigured) {
      _errorMessage = 'AI backend not configured';
      _state = LiveSessionState.error;
      notifyListeners();
      return;
    }

    _state = LiveSessionState.streaming;
    _addStatusMessage(
      'Session started. Tap the mic button to speak, or type a message.\nTap the camera strip to share a photo.',
    );
    notifyListeners();

    await _sendToBackend(
      text:
          'Greet the user briefly and ask what car issue they are experiencing.',
    );
  }

  void setObdContext(Map<String, dynamic>? obdContext) {
    _obdContext =
        obdContext == null ? null : Map<String, dynamic>.from(obdContext);
    notifyListeners();
  }

  Future<void> toggleRecording() async {
    if (_state == LiveSessionState.analyzing) return;

    if (_isRecording) {
      await _stopAndSend();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      throw const LiveSessionPermissionException(
        'Microphone access is required for live voice diagnosis.',
      );
    }

    if (_isSpeaking) {
      await _tts.stop();
      _isSpeaking = false;
    }

    _syncAudioLimit();
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/fixease_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    _recordingStartedAt = DateTime.now();
    _recordingElapsed = Duration.zero;
    _isStoppingRecording = false;

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
        path: path,
      );
    } catch (error) {
      throw LiveSessionException(
        'Could not start live voice recording.',
        cause: error,
      );
    }

    _isRecording = true;
    _startRecordingTicker();
    notifyListeners();
  }

  Future<void> _stopAndSend({bool reachedCap = false}) async {
    if (_isStoppingRecording) return;
    _isStoppingRecording = true;

    final path = await _recorder.stop();
    _stopRecordingTicker();
    _isRecording = false;
    _recordingElapsed = reachedCap ? _recordingLimit : _recordingElapsed;
    _recordingStartedAt = null;

    if (reachedCap && !SubscriptionService.instance.hasPremiumAccess) {
      _recordingCapEvents++;
    }
    notifyListeners();

    if (path == null) {
      _resetRecordingState();
      _isStoppingRecording = false;
      return;
    }

    final file = File(path);
    if (!await file.exists()) {
      _resetRecordingState();
      _isStoppingRecording = false;
      return;
    }

    final bytes = await Isolate.run(() => File(path).readAsBytesSync());
    if (bytes.length < 1000) {
      try {
        await file.delete();
      } catch (_) {}
      _resetRecordingState();
      _isStoppingRecording = false;
      notifyListeners();
      return;
    }

    if (_threadId == null ||
        !SubscriptionService.instance.checkAccess(
          FeatureType.liveAudioTurn,
          threadId: _threadId,
          threadType: DiagnosticType.live,
        )) {
      _resetRecordingState();
      _isStoppingRecording = false;
      notifyListeners();
      return;
    }

    final pendingTurn = _PendingLiveTurn(
      messageIndex: _addUserMessage(
        'Voice message',
        source: ConversationMessageSource.audio,
        includeInHistory: false,
      ),
      text: 'Voice note',
      source: ConversationMessageSource.audio,
    );
    _state = LiveSessionState.analyzing;
    notifyListeners();

    final encodedAudio = await Isolate.run(() => base64Encode(bytes));
    await _sendToBackend(
      audioData: encodedAudio,
      audioMimeType: 'audio/mp4',
      usageEvent: !SubscriptionService.instance.hasPremiumAccess
          ? ThreadUsageEvent.liveAudio
          : null,
      countsAsDiagnosisStart: true,
      pendingUserTurn: pendingTurn,
    );

    try {
      await file.delete();
    } catch (_) {}

    _resetRecordingState();
    _isStoppingRecording = false;
    notifyListeners();
  }

  Future<void> sendImage(Uint8List jpegBytes) async {
    if (!isActive) return;
    if (_threadId == null ||
        !SubscriptionService.instance.checkAccess(
          FeatureType.liveImageUpload,
          threadId: _threadId,
          threadType: DiagnosticType.live,
        )) {
      return;
    }

    final dir = await getTemporaryDirectory();
    final previewPath =
        '${dir.path}/fixease_live_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await Isolate.run(
      () => File(previewPath).writeAsBytesSync(jpegBytes, flush: true),
    );

    final pendingTurn = _PendingLiveTurn(
      messageIndex: _addUserMessage(
        'Photo sent',
        source: ConversationMessageSource.image,
        attachmentPath: previewPath,
        attachmentName: 'Live photo',
        includeInHistory: false,
      ),
      text: 'Photo attached',
      source: ConversationMessageSource.image,
      attachmentPath: previewPath,
      attachmentName: 'Live photo',
    );
    _state = LiveSessionState.analyzing;
    notifyListeners();

    final uploadBytes = await _compressLiveImage(jpegBytes);
    final encodedImage = await Isolate.run(() => base64Encode(uploadBytes));
    await _sendToBackend(
      text:
          'The user sent a photo of their car issue. Analyze it and describe what you see.',
      imageData: encodedImage,
      imageMimeType: 'image/jpeg',
      usageEvent: ThreadUsageEvent.liveImage,
      countsAsDiagnosisStart: true,
      pendingUserTurn: pendingTurn,
    );
  }

  Future<Uint8List> _compressLiveImage(Uint8List jpegBytes) async {
    if (jpegBytes.length <= 350 * 1024) {
      return jpegBytes;
    }

    try {
      final compressed = await FlutterImageCompress.compressWithList(
        jpegBytes,
        format: CompressFormat.jpeg,
        minWidth: 1600,
        minHeight: 1600,
        quality: 72,
      );
      if (compressed.isEmpty || compressed.length >= jpegBytes.length) {
        return jpegBytes;
      }
      return compressed;
    } catch (_) {
      return jpegBytes;
    }
  }

  Future<void> sendText(String text) async {
    if (!isActive) return;
    if (_threadId == null ||
        !SubscriptionService.instance.checkAccess(
          FeatureType.liveTextMessage,
          threadId: _threadId,
          threadType: DiagnosticType.live,
        )) {
      return;
    }

    final pendingTurn = _PendingLiveTurn(
      messageIndex: _addUserMessage(
        text,
        source: ConversationMessageSource.text,
        includeInHistory: false,
      ),
      text: text,
      source: ConversationMessageSource.text,
    );
    _state = LiveSessionState.analyzing;
    notifyListeners();

    await _sendToBackend(
      text: text,
      usageEvent: ThreadUsageEvent.liveText,
      countsAsDiagnosisStart: true,
      pendingUserTurn: pendingTurn,
    );
  }

  Future<void> _sendToBackend({
    String? text,
    String? audioData,
    String? audioMimeType,
    String? imageData,
    String? imageMimeType,
    ThreadUsageEvent? usageEvent,
    bool countsAsDiagnosisStart = false,
    _PendingLiveTurn? pendingUserTurn,
  }) async {
    final requestGeneration = _sessionGeneration;
    final requestThreadId = _threadId;
    try {
      final body = <String, dynamic>{
        'vehicle': _vehicle != null
            ? {
                'display_name': _vehicle!.displayName,
                'fuel_label': _vehicle!.fuelLabel,
                'mileage_km': _vehicle!.mileageKm,
              }
            : null,
        if (_obdContext != null && _obdContext!.isNotEmpty)
          'obd_context': _obdContext,
        'history': _messages
            .where(
              (message) =>
                  message.includeInHistory &&
                  message.text != 'Voice message' &&
                  message.text != 'Photo sent' &&
                  !message.text.startsWith('Session started.'),
            )
            .map(
              (message) => {
                'role': message.isUser ? 'user' : 'assistant',
                'text': message.text,
              },
            )
            .toList(),
      };

      if (text != null && audioData == null) {
        body['history'] = [
          ...body['history'] as List,
          {'role': 'user', 'text': text},
        ];
      }

      if (audioData != null && audioMimeType != null) {
        body['audio'] = {
          'data': audioData,
          'mimeType': audioMimeType,
        };
      }

      if (imageData != null && imageMimeType != null) {
        body['image'] = {
          'data': imageData,
          'mimeType': imageMimeType,
        };
      }

      final response = await _postLiveResponseWithRetry(
        body,
        consumeDiagnosticQuota: countsAsDiagnosisStart,
      );

      if (response.statusCode == 200) {
        if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
        _errorMessage = null;
        await _commitPendingUserTurn(pendingUserTurn);
        if (usageEvent != null && requestThreadId != null) {
          await SubscriptionService.instance.recordThreadEvent(
            sessionId: requestThreadId,
            sessionType: DiagnosticType.live,
            event: usageEvent,
          );
        }
        if (countsAsDiagnosisStart && requestThreadId != null) {
          await SubscriptionService.instance.recordLiveDiagnosisIfNeeded(
            sessionId: requestThreadId,
          );
          await QuotaService.instance.refreshStatus();
        }
        final data = await _parseJsonMap(response.body);
        final responseText = data['text'] as String? ??
            'I could not process that. Please try again.';

        _addAssistantMessage(responseText);
        await _persistAssistantTurn(responseText);
        _state = LiveSessionState.streaming;
        notifyListeners();

        if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
        _isSpeaking = true;
        notifyListeners();
        await _tts.speak(responseText);
        if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
        _isSpeaking = false;
        notifyListeners();
      } else {
        if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
        final data = await _parseJsonMap(response.body);
        final failureMessage =
            data['message'] as String? ?? 'Request failed. Please try again.';
        _errorMessage = failureMessage;
        final message = 'Error: $failureMessage';
        _addAssistantMessage(message, includeInHistory: false);
        _state = LiveSessionState.streaming;
        notifyListeners();
      }
    } on TimeoutException catch (_) {
      if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
      const message =
          'The live diagnosis server is taking longer than expected. Please try again in a moment.';
      _errorMessage = message;
      _addAssistantMessage(message, includeInHistory: false);
      _state = LiveSessionState.streaming;
      notifyListeners();
    } on SocketException catch (_) {
      if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
      const message =
          'Your connection dropped while contacting live diagnosis. Check your network and try again.';
      _errorMessage = message;
      _addAssistantMessage(message, includeInHistory: false);
      _state = LiveSessionState.streaming;
      notifyListeners();
    } on LiveSessionException catch (error) {
      if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
      final message = error.message;
      _errorMessage = message;
      _addAssistantMessage(message, includeInHistory: false);
      _state = LiveSessionState.streaming;
      notifyListeners();
    } catch (_) {
      if (!_isCurrentRequest(requestGeneration, requestThreadId)) return;
      const message = 'Connection error. Please try again.';
      _errorMessage = message;
      _addAssistantMessage(message, includeInHistory: false);
      _state = LiveSessionState.streaming;
      notifyListeners();
    }
  }

  Future<http.Response> _postLiveResponseWithRetry(Map<String, dynamic> body,
      {bool consumeDiagnosticQuota = false}) async {
    final deviceId = await DeviceIdentityService.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw const LiveSessionException(
        'FixEase could not verify this device for live scan access. Please restart the app and try again.',
      );
    }
    final encodedBody = await Isolate.run(() => jsonEncode(body));
    var delay = const Duration(seconds: 1);

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .post(
              AiConfig.endpoint('/api/live/voice'),
              headers: {
                'Content-Type': 'application/json',
                ...await SubscriptionService.instance.backendEntitlementHeaders(),
                'x-fixease-device-id': deviceId,
                'x-fixease-live-session-id': _threadId ?? '',
                'x-fixease-consume-diagnostic':
                    consumeDiagnosticQuota ? 'true' : 'false',
              },
              body: encodedBody,
            )
            .timeout(const Duration(seconds: 60));
        if (response.statusCode >= 500 && attempt < 2) {
          await Future<void>.delayed(delay);
          delay = Duration(seconds: delay.inSeconds * 2);
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt == 2) rethrow;
      } on SocketException {
        if (attempt == 2) rethrow;
      } on http.ClientException {
        if (attempt == 2) rethrow;
      }

      await Future<void>.delayed(delay);
      delay = Duration(seconds: delay.inSeconds * 2);
    }

    throw const LiveSessionException(
      'Could not reach the live diagnosis server after multiple attempts.',
    );
  }

  Future<Map<String, dynamic>> _parseJsonMap(String raw) async {
    if (raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = await Isolate.run(
      () => jsonDecode(raw) as Map<String, dynamic>,
    );
    return Map<String, dynamic>.from(decoded);
  }

  void endSession() {
    if (_state == LiveSessionState.idle) return;
    _sessionGeneration++;
    _addStatusMessage('Session ended.');
    _teardown();
    _state = LiveSessionState.done;
    notifyListeners();
  }

  void reset() {
    _sessionGeneration++;
    _teardown();
    _state = LiveSessionState.idle;
    _messages.clear();
    _errorMessage = null;
    _vehicle = null;
    _sessionStart = null;
    _historySession = null;
    _historySessionSaved = false;
    _threadId = null;
    _obdContext = null;
    notifyListeners();
  }

  void _teardown() {
    _stopRecordingTicker();
    _recorder.stop();
    _tts.stop();
    _isRecording = false;
    _isSpeaking = false;
    _recordingStartedAt = null;
    _resetRecordingState();
  }

  bool _isCurrentRequest(int generation, String? threadId) {
    return generation == _sessionGeneration &&
        threadId != null &&
        threadId == _threadId &&
        _state != LiveSessionState.done &&
        _state != LiveSessionState.idle;
  }

  int _addUserMessage(
    String text, {
    ConversationMessageSource source = ConversationMessageSource.text,
    String? attachmentPath,
    String? attachmentName,
    bool includeInHistory = true,
  }) {
    _messages.add(
      LiveMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
        source: source,
        attachmentPath: attachmentPath,
        attachmentName: attachmentName,
        includeInHistory: includeInHistory,
      ),
    );
    return _messages.length - 1;
  }

  void _addAssistantMessage(String text, {bool includeInHistory = true}) {
    _messages.add(
      LiveMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
        includeInHistory: includeInHistory,
      ),
    );
  }

  void _addStatusMessage(String text) {
    _messages.add(
      LiveMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
        includeInHistory: false,
      ),
    );
  }

  Future<void> _commitPendingUserTurn(_PendingLiveTurn? pendingTurn) async {
    if (pendingTurn == null) return;
    if (pendingTurn.messageIndex < 0 ||
        pendingTurn.messageIndex >= _messages.length) {
      return;
    }
    final existing = _messages[pendingTurn.messageIndex];
    if (!existing.isUser) return;
    _messages[pendingTurn.messageIndex] =
        existing.copyWith(includeInHistory: true);
    await _persistUserTurn(
      text: pendingTurn.text,
      source: pendingTurn.source,
      attachmentPath: pendingTurn.attachmentPath,
      attachmentName: pendingTurn.attachmentName,
    );
  }

  void _syncAudioLimit() {
    _recordingLimit = SubscriptionService.instance.liveAudioLimit;
  }

  void _startRecordingTicker() {
    _stopRecordingTicker();
    _recordingTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isRecording || _recordingStartedAt == null) {
        timer.cancel();
        return;
      }

      _recordingElapsed = DateTime.now().difference(_recordingStartedAt!);
      if (_recordingElapsed >= _recordingLimit) {
        timer.cancel();
        unawaited(_stopAndSend(reachedCap: true));
        return;
      }
      notifyListeners();
    });
  }

  void _stopRecordingTicker() {
    _recordingTicker?.cancel();
    _recordingTicker = null;
  }

  void _resetRecordingState() {
    _recordingElapsed = Duration.zero;
    _recordingStartedAt = null;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(1, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<DiagnosticSession?> _ensureHistorySession() async {
    if (_historySession != null) return _historySession;
    final vehicle = _vehicle;
    if (vehicle == null) return null;

    final session = DiagnosticSession(
      id: _threadId ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      vehicleId: vehicle.id,
      type: DiagnosticType.live,
      description: 'Gemini Live conversation',
      vehicleName: vehicle.displayName,
      createdAt: _sessionStart ?? DateTime.now(),
    );

    _historySession = session;
    await DiagnosticService.instance.save(session);
    await ConversationService.instance.createOrGetThread(
      sessionId: session.id,
      vehicleId: session.vehicleId,
    );
    return session;
  }

  Future<void> _persistUserTurn({
    required String text,
    required ConversationMessageSource source,
    String? attachmentPath,
    String? attachmentName,
  }) async {
    final session = await _ensureHistorySession();
    if (session == null) return;

    if (!_historySessionSaved) {
      await DiagnosticService.instance.save(session);
      _historySessionSaved = true;
    }

    await ConversationService.instance.appendMessage(
      sessionId: session.id,
      vehicleId: session.vehicleId,
      message: ConversationMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        role: ConversationMessageRole.user,
        text: text,
        createdAt: DateTime.now(),
        source: source,
        attachmentPath: attachmentPath,
        attachmentName: attachmentName,
      ),
    );
  }

  Future<void> _persistAssistantTurn(String text) async {
    final session = _historySession;
    if (session == null) return;

    await ConversationService.instance.appendMessage(
      sessionId: session.id,
      vehicleId: session.vehicleId,
      message: ConversationMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        role: ConversationMessageRole.assistant,
        text: text,
        createdAt: DateTime.now(),
      ),
    );
  }
}

class DeviceCapability {
  const DeviceCapability({
    required this.hasCamera,
    required this.hasNetwork,
    required this.hasBackend,
  });

  final bool hasCamera;
  final bool hasNetwork;
  final bool hasBackend;

  bool get isReady => hasCamera && hasNetwork && hasBackend;

  String? get blockerMessage {
    if (!hasBackend) return 'AI backend not configured';
    if (!hasNetwork) return 'No backend connection detected';
    if (!hasCamera) return 'Camera not available on this device';
    return null;
  }
}

class LiveSessionException implements Exception {
  const LiveSessionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class LiveSessionPermissionException extends LiveSessionException {
  const LiveSessionPermissionException(super.message, {super.cause});
}
