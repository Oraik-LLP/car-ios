import 'dart:async';
import 'dart:io';

import 'package:bluetooth_serial_android/bluetooth_serial_android.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/ai_response.dart';
import '../models/diagnostic.dart';
import '../models/obd.dart';
import '../models/vehicle.dart';
import 'ai_service.dart';
import 'diagnostic_service.dart';
import 'local_store_service.dart';
import 'obd_processing_service.dart';
import 'obd_error_mapper.dart';
import 'obd_protocol.dart';
import 'vehicle_service.dart';

class ObdPromptContext {
  const ObdPromptContext({
    this.idleInsight,
    this.driveInsight,
  });

  final ObdInsightRecord? idleInsight;
  final ObdInsightRecord? driveInsight;

  bool get hasData => idleInsight != null || driveInsight != null;

  Map<String, dynamic> toJson() => {
        if (idleInsight != null) 'idle': _recordToJson(idleInsight!),
        if (driveInsight != null) 'drive': _recordToJson(driveInsight!),
      };

  Map<String, dynamic> _recordToJson(ObdInsightRecord insight) => {
        'summary': insight.summary,
        'created_at': insight.createdAt.toIso8601String(),
        'is_partial': insight.isPartial,
        'captured_duration_seconds': insight.capturedDurationSeconds,
        'target_duration_seconds': insight.targetDurationSeconds,
        'static_snapshot': _snapshotWithoutVin(
          insight.record.staticSnapshot,
        ),
        'processed_scan': insight.record.processedScan.toJson(),
      };

  Map<String, dynamic> _snapshotWithoutVin(ObdStaticSnapshot snapshot) {
    return Map<String, dynamic>.from(snapshot.toJson())..remove('vin');
  }
}

class ObdScanOutcome {
  const ObdScanOutcome({
    required this.session,
    required this.record,
    required this.response,
  });

  final DiagnosticSession session;
  final ObdScanRecord record;
  final AiDiagnosticResponse response;
}

class _PendingCommand {
  _PendingCommand({
    required this.command,
    required this.completer,
  });

  final String command;
  final Completer<ObdCommandResult> completer;
}

class ObdProService extends ChangeNotifier with WidgetsBindingObserver {
  ObdProService._() {
    _tts = FlutterTts();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.48);
    _tts.setPitch(1.0);
    _tts.awaitSpeakCompletion(true);
    WidgetsBinding.instance.addObserver(this);
  }

  static final ObdProService instance = ObdProService._();

  static const _storageKey = 'obd.pro.v1';
  static const _idleTargetDuration = Duration(seconds: 30);
  static const _driveTargetDuration = Duration(minutes: 2);
  static const _scanCommandDelay = Duration(milliseconds: 250);
  static const _liveCommandDelay = Duration(milliseconds: 1100);
  static const _backgroundInterruptionGrace = Duration(seconds: 5);

  late final FlutterTts _tts;

  List<BluetoothTarget> _pairedDevices = const [];
  List<BluetoothTarget> _scanDevices = const [];
  BluetoothTarget? _selectedDevice;
  bool _permissionsReady = false;
  bool _isLoadingDevices = false;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _keepReading = false;
  bool _userInitiatedDisconnect = false;
  Future<void> _readLoopFuture = Future<void>.value();
  Future<void> _commandQueue = Future<void>.value();
  _PendingCommand? _pendingCommand;
  String _rxBuffer = '';

  ObdSuiteState _state = ObdSuiteState.disconnected;
  String _status = 'OBD Pro idle.';
  String? _errorMessage;
  String? _errorCode;
  String? _errorRecovery;
  ObdStaticSnapshot _staticSnapshot = const ObdStaticSnapshot();
  ObdLiveVitals _liveVitals = const ObdLiveVitals();
  bool _initCompleted = false;

  bool _liveLoopEnabled = false;
  bool _liveLoopRunning = false;

  ObdScanKind? _activeScanKind;
  DateTime? _scanStartedAt;
  DateTime? _backgroundedAt;
  bool _wasBackgroundedDuringScan = false;
  int _driveAboveThresholdCount = 0;
  final List<ObdSampleFrame> _scanSamples = <ObdSampleFrame>[];
  Timer? _scanProgressTicker;
  bool _wakelockEnabled = false;

  final Map<String, Map<ObdScanKind, ObdInsightRecord>> _latestInsights = {};
  final Map<String, ObdStaticSnapshot> _snapshotsByVehicle = {};
  final Map<String, bool> _promptInjectionPrefs = {};
  ObdScanOutcome? _lastOutcome;

  List<BluetoothTarget> get pairedDevices => List.unmodifiable(_pairedDevices);
  List<BluetoothTarget> get scanDevices => List.unmodifiable(_scanDevices);
  BluetoothTarget? get selectedDevice => _selectedDevice;
  bool get permissionsReady => _permissionsReady;
  bool get isLoadingDevices => _isLoadingDevices;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  ObdSuiteState get state => _state;
  String get status => _status;
  String? get errorMessage => _errorMessage;
  String? get errorCode => _errorCode;
  String? get errorRecovery => _errorRecovery;
  ObdStaticSnapshot get staticSnapshot => _staticSnapshot;
  ObdStaticSnapshot staticSnapshotForVehicle(String vehicleId) {
    final snapshot =
        _snapshotsByVehicle[vehicleId] ?? const ObdStaticSnapshot();
    if (snapshot.vin?.trim().isNotEmpty == true) return snapshot;
    for (final vehicle in VehicleService.instance.vehicles) {
      if (vehicle.id == vehicleId && vehicle.vin?.trim().isNotEmpty == true) {
        return snapshot.copyWith(vin: vehicle.vin!.trim().toUpperCase());
      }
    }
    return snapshot;
  }

  ObdLiveVitals get liveVitals => _liveVitals;
  bool get initCompleted => _initCompleted;
  ObdScanKind? get activeScanKind => _activeScanKind;
  bool get isScanActive =>
      _state == ObdSuiteState.idleRunning ||
      _state == ObdSuiteState.driveWaiting ||
      _state == ObdSuiteState.driveRunning ||
      _state == ObdSuiteState.finalizing;
  bool get isDriveArmed => _state == ObdSuiteState.driveRunning;
  ObdScanOutcome? get lastOutcome => _lastOutcome;

  int get targetDurationSeconds => switch (_activeScanKind) {
        ObdScanKind.idle => _idleTargetDuration.inSeconds,
        ObdScanKind.drive => _driveTargetDuration.inSeconds,
        null => 0,
      };

  int get capturedDurationSeconds => _capturedDuration.inSeconds;

  double get scanProgress {
    final target = targetDurationSeconds;
    if (target == 0) return 0;
    return (capturedDurationSeconds / target).clamp(0.0, 1.0);
  }

  Duration get _capturedDuration {
    final startedAt = _scanStartedAt;
    if (startedAt == null) return Duration.zero;
    return DateTime.now().difference(startedAt);
  }

  Future<void> load() async {
    final json = LocalStoreService.readJsonMap(_storageKey);
    if (json == null) {
      notifyListeners();
      return;
    }
    final insightsJson =
        json['latest_insights'] as Map<String, dynamic>? ?? const {};
    _latestInsights
      ..clear()
      ..addEntries(
        insightsJson.entries.map((vehicleEntry) {
          final perKind = <ObdScanKind, ObdInsightRecord>{};
          final value = vehicleEntry.value;
          if (value is Map) {
            for (final insightEntry in value.entries) {
              try {
                final kind =
                    ObdScanKind.values.byName(insightEntry.key.toString());
                if (insightEntry.value is Map) {
                  perKind[kind] = ObdInsightRecord.fromJson(
                    Map<String, dynamic>.from(insightEntry.value as Map),
                  );
                }
              } catch (_) {}
            }
          }
          return MapEntry(vehicleEntry.key, perKind);
        }),
      );

    final snapshotsJson = json['static_snapshots'];
    _snapshotsByVehicle.clear();
    if (snapshotsJson is Map) {
      for (final entry in snapshotsJson.entries) {
        if (entry.value is Map) {
          try {
            _snapshotsByVehicle[entry.key.toString()] =
                ObdStaticSnapshot.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          } catch (_) {}
        }
      }
    }
    final selectedVehicle = VehicleService.instance.selected;
    if (selectedVehicle != null) {
      _staticSnapshot = staticSnapshotForVehicle(selectedVehicle.id);
    }

    final prefsJson =
        json['prompt_injection_prefs'] as Map<String, dynamic>? ?? const {};
    _promptInjectionPrefs
      ..clear()
      ..addEntries(
        prefsJson.entries.map(
          (entry) => MapEntry(entry.key, entry.value as bool? ?? true),
        ),
      );
    notifyListeners();
  }

  Future<void> ensurePermissionsAndLoadDevices() async {
    if (!Platform.isAndroid) {
      _permissionsReady = false;
      _status = 'OBD Pro is Android-only in this build.';
      notifyListeners();
      return;
    }

    _isLoadingDevices = true;
    _status = 'Requesting Bluetooth permissions...';
    notifyListeners();

    try {
      final granted = await FlutterBluetoothSerial.ensurePermissions();
      if (!granted) {
        _permissionsReady = false;
        _setBluetoothError(StateError('Bluetooth permission denied'));
        return;
      }

      _permissionsReady = true;
      await refreshDevices();
    } catch (error) {
      _setBluetoothError(error);
    } finally {
      _isLoadingDevices = false;
      notifyListeners();
    }
  }

  Future<void> refreshDevices() async {
    if (!_permissionsReady || !Platform.isAndroid) {
      return;
    }
    _isLoadingDevices = true;
    _status = 'Loading OBD adapters...';
    notifyListeners();

    try {
      final paired = await FlutterBluetoothSerial.getPairedDevices();
      final scanned = await FlutterBluetoothSerial.scanDevices();
      final pairedTargets = paired.map(BluetoothTarget.fromMap).toList();
      final scannedTargets = scanned.map(BluetoothTarget.fromMap).toList();
      final merged = <String, BluetoothTarget>{
        for (final device in scannedTargets) device.address: device,
        for (final device in pairedTargets) device.address: device,
      };

      _pairedDevices = pairedTargets;
      _scanDevices = merged.values.toList()
        ..sort((a, b) => a.displayName.compareTo(b.displayName));
      _selectedDevice ??= _pairedDevices.isNotEmpty
          ? _pairedDevices.first
          : _scanDevices.firstOrNull;
      _status = _selectedDevice == null
          ? 'No paired OBD adapters found yet.'
          : 'Adapter list ready.';
    } catch (error) {
      _setBluetoothError(error);
    } finally {
      _isLoadingDevices = false;
      notifyListeners();
    }
  }

  void selectDevice(BluetoothTarget? device) {
    _selectedDevice = device;
    notifyListeners();
  }

  Future<void> connect() async {
    final device = _selectedDevice;
    if (device == null || _isConnecting || !Platform.isAndroid) {
      return;
    }

    _isConnecting = true;
    _errorMessage = null;
    _errorCode = null;
    _errorRecovery = null;
    _status = 'Connecting to ${device.displayName}...';
    _state = ObdSuiteState.connecting;
    notifyListeners();

    try {
      await disconnect(clearStatus: false);
      final connected = await FlutterBluetoothSerial.connect(
        device.address,
        timeoutMs: 1500,
      );
      if (!connected) {
        throw Exception('The adapter did not accept the connection.');
      }

      _userInitiatedDisconnect = false;
      _isConnected = true;
      _keepReading = true;
      _readLoopFuture = _readLoop();
      _status = 'Connected to ${device.displayName}.';
      final vehicleId = VehicleService.instance.selected?.id;
      _staticSnapshot = vehicleId == null
          ? const ObdStaticSnapshot()
          : staticSnapshotForVehicle(vehicleId);
      _liveVitals = const ObdLiveVitals();
      _initCompleted = false;
      notifyListeners();

      await _runInitializationSequence();
      if (_isConnected && _state != ObdSuiteState.error) {
        _state = ObdSuiteState.liveReady;
        _status = 'Live vitals ready.';
        _startLiveLoop();
      }
    } catch (error) {
      _setBluetoothError(error);
      _state = ObdSuiteState.error;
      _isConnected = false;
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool clearStatus = true}) async {
    _liveLoopEnabled = false;
    _keepReading = false;
    _userInitiatedDisconnect = true;
    await _finishActiveScanIfNeeded(
      reason: ObdCompletionReason.cancelled,
      disconnected: true,
    );
    _disableWakelock();
    _stopScanTicker();

    try {
      await FlutterBluetoothSerial.disconnect();
      await _readLoopFuture.timeout(
        const Duration(milliseconds: 300),
        onTimeout: () async {},
      );
    } catch (_) {}

    _pendingCommand = null;
    _isConnected = false;
    _initCompleted = false;
    _activeScanKind = null;
    _state = ObdSuiteState.disconnected;
    if (clearStatus) {
      _status = 'Disconnected.';
    }
    notifyListeners();
  }

  Future<void> startIdleScan() async {
    if (!_isConnected || !_initCompleted || isScanActive) {
      return;
    }

    final speedCheck = await _sendCommand('010D');
    final speed = speedCheck.integerValue ?? liveVitals.speedKph;
    if ((speed ?? 0) > 0) {
      _status = 'Idle scan requires the vehicle to be stationary.';
      notifyListeners();
      return;
    }

    _activeScanKind = ObdScanKind.idle;
    _driveAboveThresholdCount = 0;
    _scanSamples.clear();
    _scanStartedAt = DateTime.now();
    _state = ObdSuiteState.idleRunning;
    _status = 'Running 30-second idle health scan...';
    _lastOutcome = null;
    _enableWakelock();
    _startScanTicker();
    _liveLoopEnabled = false;
    notifyListeners();

    unawaited(_runIdleScanLoop());
  }

  Future<void> startDriveScan() async {
    if (!_isConnected || !_initCompleted || isScanActive) {
      return;
    }

    _activeScanKind = ObdScanKind.drive;
    _driveAboveThresholdCount = 0;
    _scanSamples.clear();
    _scanStartedAt = null;
    _state = ObdSuiteState.driveWaiting;
    _status = 'Waiting for vehicle speed above 5 km/h...';
    _lastOutcome = null;
    _enableWakelock();
    _startScanTicker();
    _liveLoopEnabled = false;
    notifyListeners();

    unawaited(_runDriveScanLoop());
  }

  Future<void> cancelActiveScan() async {
    await _finishActiveScanIfNeeded(
      reason: ObdCompletionReason.cancelled,
    );
  }

  ObdInsightRecord? latestInsightForVehicle(
    String vehicleId,
    ObdScanKind kind,
  ) {
    return _latestInsights[vehicleId]?[kind];
  }

  bool hasInsightsForVehicle(String vehicleId) =>
      (_latestInsights[vehicleId]?.isNotEmpty ?? false);

  bool isPromptInjectionEnabled(String vehicleId) =>
      _promptInjectionPrefs[vehicleId] ?? true;

  Future<void> setPromptInjectionEnabled(String vehicleId, bool enabled) async {
    _promptInjectionPrefs[vehicleId] = enabled;
    notifyListeners();
    await _persist();
  }

  ObdPromptContext? promptContextForVehicle(String vehicleId) {
    if (!isPromptInjectionEnabled(vehicleId)) {
      return null;
    }
    return latestPromptContextForVehicle(vehicleId);
  }

  ObdPromptContext? latestPromptContextForVehicle(String vehicleId) {
    final insights = _latestInsights[vehicleId];
    if (insights == null || insights.isEmpty) {
      return null;
    }
    final context = ObdPromptContext(
      idleInsight: insights[ObdScanKind.idle],
      driveInsight: insights[ObdScanKind.drive],
    );
    return context.hasData ? context : null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!isScanActive) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _backgroundedAt = DateTime.now();
      _wasBackgroundedDuringScan = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgroundedDuringScan) {
      final startedAt = _backgroundedAt;
      _backgroundedAt = null;
      _wasBackgroundedDuringScan = false;
      if (startedAt == null) {
        return;
      }
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _backgroundInterruptionGrace) {
        return;
      }
      unawaited(
        _finishActiveScanIfNeeded(
          reason: ObdCompletionReason.backgroundInterrupted,
        ),
      );
    }
  }

  Future<void> _runInitializationSequence() async {
    _state = ObdSuiteState.initializing;
    _status = 'Running OBD adapter initialization...';
    notifyListeners();

    for (final command in ObdProtocol.initCommands) {
      await _sendCommand(command);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }

    _status = 'Collecting static snapshot...';
    notifyListeners();
    for (final command in ObdProtocol.initSnapshotCommands) {
      final response = await _sendCommand(command);
      _applyInitSnapshotResponse(command, response);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    _initCompleted = true;
  }

  void _applyInitSnapshotResponse(
    String command,
    ObdCommandResult response,
  ) {
    if (response.isNoData || response.isStopped || response.isTimedOut) {
      return;
    }
    switch (command) {
      case '0902':
        _staticSnapshot = _staticSnapshot.copyWith(
          vin: response.textValue,
          capturedAt: DateTime.now(),
        );
        break;
      case '03':
        _staticSnapshot = _staticSnapshot.copyWith(
          storedDtcs: response.codes,
          capturedAt: DateTime.now(),
        );
        break;
      case '07':
        _staticSnapshot = _staticSnapshot.copyWith(
          pendingDtcs: response.codes,
          capturedAt: DateTime.now(),
        );
        break;
      case '0142':
        _staticSnapshot = _staticSnapshot.copyWith(
          controlModuleVoltage: response.numericValue,
          capturedAt: DateTime.now(),
        );
        break;
      case '0131':
        _staticSnapshot = _staticSnapshot.copyWith(
          distanceSinceCodesClearedKm: response.integerValue,
          capturedAt: DateTime.now(),
        );
        break;
      case '0146':
        _staticSnapshot = _staticSnapshot.copyWith(
          ambientAirTempC: response.numericValue,
          capturedAt: DateTime.now(),
        );
        break;
    }
    final vehicleId = VehicleService.instance.selected?.id;
    if (vehicleId != null) {
      _snapshotsByVehicle[vehicleId] = _staticSnapshot;
      unawaited(_persist());
    }
    notifyListeners();
  }

  final Map<String, double> _pendingCycleValues = <String, double>{};

  Future<void> _runIdleScanLoop() async {
    var commandIndex = 0;
    _pendingCycleValues.clear();
    while (_isConnected && _state == ObdSuiteState.idleRunning) {
      final command = ObdProtocol.idleCommands[commandIndex];
      final response = await _sendCommand(command);
      _accumulateCycleMetric(command, response);
      commandIndex = (commandIndex + 1) % ObdProtocol.idleCommands.length;

      if (commandIndex == 0) {
        _flushCycleSnapshot();

        final speedCheck = await _sendCommand('010D');
        final speed = speedCheck.integerValue ?? liveVitals.speedKph;
        _updateLiveVitals('010D', speedCheck);
        if ((speed ?? 0) > 0) {
          final captured = _capturedDuration;
          if (ObdPartialRecoveryPolicy.canFinalizeIdlePartial(captured)) {
            await _finalizeScan(
              kind: ObdScanKind.idle,
              isPartial: true,
              reason: ObdCompletionReason.vehicleMoved,
            );
          } else {
            _discardInterruptedScan(
              'Idle scan stopped because the vehicle started moving.',
            );
          }
          return;
        }
      }

      if (_capturedDuration >= _idleTargetDuration) {
        _flushCycleSnapshot();
        await _finalizeScan(
          kind: ObdScanKind.idle,
          isPartial: false,
          reason: ObdCompletionReason.completed,
        );
        return;
      }

      await Future<void>.delayed(_scanCommandDelay);
    }
  }

  Future<void> _runDriveScanLoop() async {
    var commandIndex = 0;
    while (_isConnected &&
        (_state == ObdSuiteState.driveWaiting ||
            _state == ObdSuiteState.driveRunning)) {
      final command = ObdProtocol.driveCommands[commandIndex];
      final response = await _sendCommand(command);
      _updateLiveVitals(command, response);

      if (_state == ObdSuiteState.driveWaiting && command == '010D') {
        final speed = response.integerValue ?? 0;
        if (speed > 5) {
          _driveAboveThresholdCount += 1;
        } else {
          _driveAboveThresholdCount = 0;
        }
        if (_driveAboveThresholdCount >= 2) {
          _state = ObdSuiteState.driveRunning;
          _scanStartedAt = DateTime.now();
          _status = 'Drive scan armed. Recording under load...';
          notifyListeners();
        }
      }

      if (_state == ObdSuiteState.driveRunning) {
        _accumulateCycleMetric(command, response);

        final nextIndex = (commandIndex + 1) % ObdProtocol.driveCommands.length;
        if (nextIndex == 0) {
          _flushCycleSnapshot();
        }

        if (_capturedDuration >= _driveTargetDuration) {
          _flushCycleSnapshot();
          await _finalizeScan(
            kind: ObdScanKind.drive,
            isPartial: false,
            reason: ObdCompletionReason.completed,
            announceDriveCompletion: true,
          );
          return;
        }
      }

      commandIndex = (commandIndex + 1) % ObdProtocol.driveCommands.length;
      await Future<void>.delayed(_scanCommandDelay);
    }
  }

  void _accumulateCycleMetric(String command, ObdCommandResult response) {
    if (response.isNoData || response.isStopped || response.isTimedOut) {
      return;
    }
    final metricKey = _metricKeyForCommand(command);
    if (metricKey == null) {
      return;
    }
    final metricValue =
        response.numericValue ?? response.integerValue?.toDouble();
    if (metricValue == null) {
      return;
    }
    _pendingCycleValues[metricKey] = metricValue;
  }

  void _flushCycleSnapshot() {
    if (_pendingCycleValues.isEmpty) {
      return;
    }
    final startedAt = _scanStartedAt;
    if (startedAt == null) {
      return;
    }
    final now = DateTime.now();
    _scanSamples.add(
      ObdSampleFrame(
        timestamp: now,
        elapsedMs: now.difference(startedAt).inMilliseconds,
        values: Map<String, double>.from(_pendingCycleValues),
      ),
    );
    _pendingCycleValues.clear();
    notifyListeners();
  }

  Future<void> _finalizeScan({
    required ObdScanKind kind,
    required bool isPartial,
    required ObdCompletionReason reason,
    bool announceDriveCompletion = false,
  }) async {
    final vehicle = VehicleService.instance.selected;
    if (vehicle == null) {
      _discardInterruptedScan('Select a vehicle before running OBD Pro.');
      return;
    }

    if (kind == ObdScanKind.drive && announceDriveCompletion) {
      await _speakDriveCompletion();
    }

    _state = ObdSuiteState.finalizing;
    _status = isPartial
        ? 'Finalizing partial ${kind.name} scan...'
        : 'Finalizing ${kind.name} scan...';
    _stopScanTicker();
    notifyListeners();

    final capturedDuration = _capturedDuration;
    final samples = List<ObdSampleFrame>.from(_scanSamples);
    final processed = kind == ObdScanKind.idle
        ? await ObdProcessingService.processIdle(samples)
        : await ObdProcessingService.processDrive(samples);
    final record = ObdScanRecord(
      kind: kind,
      isPartial: isPartial,
      completionReason: reason,
      targetDurationSeconds: kind == ObdScanKind.idle
          ? _idleTargetDuration.inSeconds
          : _driveTargetDuration.inSeconds,
      capturedDurationSeconds: capturedDuration.inSeconds,
      staticSnapshot: _staticSnapshot,
      processedScan: processed,
    );

    final sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final createdAt = DateTime.now();
    final offlineSession = DiagnosticSession(
      id: sessionId,
      vehicleId: vehicle.id,
      type: kind == ObdScanKind.idle
          ? DiagnosticType.obdIdle
          : DiagnosticType.obdDrive,
      description: isPartial
          ? 'Partial ${kind.name} OBD scan'
          : '${kind.name[0].toUpperCase()}${kind.name.substring(1)} OBD scan',
      contextJson: {
        'obd_record': record.toJson(),
        'analysis_status': 'pending',
      },
      vehicleName: vehicle.displayName,
      createdAt: createdAt,
    );

    try {
      await DiagnosticService.instance.save(offlineSession);
    } catch (_) {
      _errorMessage =
          'The scan finished, but FixEase could not save it on this device.';
      _errorCode = 'local_report_save_failed';
      _status =
          'Report could not be saved. Check device storage and try again.';
      _state = ObdSuiteState.error;
      await _disableWakelock();
      notifyListeners();
      return;
    }

    _status = 'Scan saved on this device. Preparing AI analysis...';
    notifyListeners();

    if (samples.isEmpty) {
      await _completeOfflineReport(
        vehicle: vehicle,
        kind: kind,
        sessionId: sessionId,
        record: record,
        createdAt: createdAt,
        status:
            'No OBD data was received. An empty scan log was saved offline.',
      );
      return;
    }

    try {
      final aiResponse = await AiService.instance.analyzeObdPro(
        vehicle: vehicle,
        record: record,
      );
      final session = DiagnosticSession(
        id: sessionId,
        vehicleId: vehicle.id,
        type: kind == ObdScanKind.idle
            ? DiagnosticType.obdIdle
            : DiagnosticType.obdDrive,
        description: isPartial
            ? 'Partial ${kind.name} OBD scan'
            : '${kind.name[0].toUpperCase()}${kind.name.substring(1)} OBD scan',
        aiResponse: aiResponse.summary,
        aiResponseJson: aiResponse.toJson(),
        contextJson: {
          'obd_record': record.toJson(),
          'analysis_status': 'complete',
        },
        healthScore: aiResponse.healthScore,
        vehicleName: vehicle.displayName,
        createdAt: createdAt,
      );
      await DiagnosticService.instance.save(session);
      final insight = ObdInsightRecord(
        vehicleId: vehicle.id,
        kind: kind,
        sessionId: session.id,
        summary: aiResponse.summary,
        aiResponseJson: aiResponse.toJson(),
        record: record,
        createdAt: DateTime.now(),
      );
      (_latestInsights[vehicle.id] ??=
          <ObdScanKind, ObdInsightRecord>{})[kind] = insight;
      _lastOutcome = ObdScanOutcome(
        session: session,
        record: record,
        response: aiResponse,
      );
      await _persist();
      _status = isPartial
          ? 'Saved partial ${kind.name} scan.'
          : '${kind == ObdScanKind.idle ? 'Idle' : 'Drive'} scan complete.';
    } catch (_) {
      await _completeOfflineReport(
        vehicle: vehicle,
        kind: kind,
        sessionId: sessionId,
        record: record,
        createdAt: createdAt,
        status:
            'Scan saved offline. AI analysis could not finish; retry when online.',
      );
      return;
    }

    _activeScanKind = null;
    _scanStartedAt = null;
    _scanSamples.clear();
    _driveAboveThresholdCount = 0;
    _disableWakelock();
    if (_isConnected) {
      _state = ObdSuiteState.liveReady;
      _startLiveLoop();
    } else {
      _state = ObdSuiteState.interrupted;
    }
    notifyListeners();
  }

  Future<void> _completeOfflineReport({
    required Vehicle vehicle,
    required ObdScanKind kind,
    required String sessionId,
    required ObdScanRecord record,
    required DateTime createdAt,
    required String status,
  }) async {
    final offlineInsight = ObdInsightRecord(
      vehicleId: vehicle.id,
      kind: kind,
      sessionId: sessionId,
      summary: status,
      aiResponseJson: const <String, dynamic>{},
      record: record,
      createdAt: createdAt,
    );
    (_latestInsights[vehicle.id] ??= <ObdScanKind, ObdInsightRecord>{})[kind] =
        offlineInsight;
    await _persist();
    _status = status;
    _errorMessage = null;
    _errorCode = null;
    _activeScanKind = null;
    _scanStartedAt = null;
    _scanSamples.clear();
    _driveAboveThresholdCount = 0;
    _stopScanTicker();
    await _disableWakelock();
    if (_isConnected) {
      _state = ObdSuiteState.liveReady;
      _startLiveLoop();
    } else {
      _state = ObdSuiteState.interrupted;
    }
    notifyListeners();
  }

  Future<void> _finishActiveScanIfNeeded({
    required ObdCompletionReason reason,
    bool disconnected = false,
  }) async {
    final kind = _activeScanKind;
    if (kind == null || !isScanActive) {
      return;
    }
    final captured = _capturedDuration;
    final canFinalizePartial = switch (kind) {
      ObdScanKind.idle =>
        ObdPartialRecoveryPolicy.canFinalizeIdlePartial(captured),
      ObdScanKind.drive => ObdPartialRecoveryPolicy.canFinalizeDrivePartial(
          isArmed: _state == ObdSuiteState.driveRunning,
          capturedDuration: captured,
        ),
    };

    if (kind == ObdScanKind.drive && canFinalizePartial) {
      await _finalizeScan(
        kind: kind,
        isPartial: true,
        reason: reason,
        announceDriveCompletion: disconnected,
      );
      return;
    }
    if (kind == ObdScanKind.idle && canFinalizePartial) {
      await _finalizeScan(
        kind: kind,
        isPartial: true,
        reason: reason,
      );
      return;
    }

    await _finalizeScan(
      kind: kind,
      isPartial: true,
      reason: reason,
      announceDriveCompletion: disconnected &&
          kind == ObdScanKind.drive &&
          _state == ObdSuiteState.driveRunning,
    );
  }

  void _discardInterruptedScan(String message) {
    _activeScanKind = null;
    _scanStartedAt = null;
    _scanSamples.clear();
    _driveAboveThresholdCount = 0;
    _stopScanTicker();
    _disableWakelock();
    _status = message;
    if (_isConnected) {
      _state = ObdSuiteState.liveReady;
      _startLiveLoop();
    } else {
      _state = ObdSuiteState.interrupted;
    }
    notifyListeners();
  }

  Future<void> _readLoop() async {
    while (_keepReading) {
      try {
        final chunk = await FlutterBluetoothSerial.read();
        if (chunk != null && chunk.isNotEmpty) {
          _handleIncomingChunk(chunk);
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      } catch (error) {
        if (!_keepReading) {
          return;
        }
        await _handleTransportDrop(error.toString());
        return;
      }
    }
  }

  void _handleIncomingChunk(String chunk) {
    _rxBuffer += chunk;

    while (_rxBuffer.contains('>')) {
      final promptIndex = _rxBuffer.indexOf('>');
      final frame = _rxBuffer.substring(0, promptIndex + 1);
      _rxBuffer = _rxBuffer.substring(promptIndex + 1);
      _consumeElmFrame(frame);
    }
  }

  void _consumeElmFrame(String frame) {
    final pending = _pendingCommand;
    if (pending == null || pending.completer.isCompleted) {
      return;
    }
    pending.completer.complete(
      ObdProtocol.parseResponse(pending.command, frame),
    );
  }

  Future<ObdCommandResult> _sendCommand(String command) {
    return _runExclusive(() async {
      if (!_isConnected) {
        throw StateError('OBD adapter is not connected.');
      }
      final normalizedCommand = ObdProtocol.normalizeCommand(command);
      final completer = Completer<ObdCommandResult>();
      _pendingCommand = _PendingCommand(
        command: normalizedCommand,
        completer: completer,
      );

      await FlutterBluetoothSerial.write('$normalizedCommand\r');
      _status = 'Sent $normalizedCommand';
      notifyListeners();

      try {
        final response = await completer.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () => ObdCommandResult(
            command: normalizedCommand,
            raw: 'TIMEOUT',
            isTimedOut: true,
          ),
        );
        _pendingCommand = null;
        _updateLiveVitals(normalizedCommand, response);
        return response;
      } catch (error) {
        _pendingCommand = null;
        rethrow;
      }
    });
  }

  Future<T> _runExclusive<T>(Future<T> Function() action) {
    final resultCompleter = Completer<T>();
    final next = _commandQueue.catchError((_) {}).then((_) async {
      try {
        resultCompleter.complete(await action());
      } catch (error, stackTrace) {
        resultCompleter.completeError(error, stackTrace);
      }
    });
    _commandQueue = next.catchError((_) {});
    return resultCompleter.future;
  }

  void _updateLiveVitals(String command, ObdCommandResult response) {
    if (response.isNoData || response.isStopped || response.isTimedOut) {
      return;
    }

    switch (command) {
      case '010C':
        _liveVitals = ObdLiveVitals(
          rpm: response.numericValue ?? _liveVitals.rpm,
          speedKph: _liveVitals.speedKph,
          coolantTempC: _liveVitals.coolantTempC,
          updatedAt: DateTime.now(),
        );
        break;
      case '010D':
        _liveVitals = ObdLiveVitals(
          rpm: _liveVitals.rpm,
          speedKph: response.integerValue ?? _liveVitals.speedKph,
          coolantTempC: _liveVitals.coolantTempC,
          updatedAt: DateTime.now(),
        );
        break;
      case '0105':
        _liveVitals = ObdLiveVitals(
          rpm: _liveVitals.rpm,
          speedKph: _liveVitals.speedKph,
          coolantTempC: response.numericValue ?? _liveVitals.coolantTempC,
          updatedAt: DateTime.now(),
        );
        break;
      default:
        return;
    }
    notifyListeners();
  }

  void _startLiveLoop() {
    if (!_isConnected || !_initCompleted) {
      return;
    }
    _liveLoopEnabled = true;
    if (_liveLoopRunning) {
      return;
    }
    _liveLoopRunning = true;
    unawaited(_runLiveLoop());
  }

  Future<void> _runLiveLoop() async {
    var index = 0;
    while (
        _liveLoopEnabled && _isConnected && _state == ObdSuiteState.liveReady) {
      final command = ObdProtocol.liveCommands[index];
      await _sendCommand(command);
      index = (index + 1) % ObdProtocol.liveCommands.length;
      await Future<void>.delayed(_liveCommandDelay);
    }
    _liveLoopRunning = false;
  }

  Future<void> _handleTransportDrop(String error) async {
    _keepReading = false;
    _isConnected = false;
    _pendingCommand?.completer.complete(
      ObdCommandResult(
        command: _pendingCommand!.command,
        raw: 'STOPPED',
        isStopped: true,
      ),
    );
    _pendingCommand = null;
    if (!_userInitiatedDisconnect) {
      await _finishActiveScanIfNeeded(
        reason: ObdCompletionReason.bluetoothDisconnect,
        disconnected: true,
      );
    }
    _disableWakelock();
    _state = ObdSuiteState.interrupted;
    _setBluetoothError(StateError(error));
    notifyListeners();
  }

  void _setBluetoothError(Object error) {
    final info = ObdErrorMapper.from(error);
    _errorCode = info.code;
    _errorMessage = info.message;
    _errorRecovery = info.nextStep;
    _status = info.message;
  }

  Future<void> _persist() {
    return LocalStoreService.writeJsonMap(
      _storageKey,
      {
        'latest_insights': _latestInsights.map(
          (vehicleId, insights) => MapEntry(
            vehicleId,
            insights.map(
              (kind, insight) => MapEntry(kind.name, insight.toJson()),
            ),
          ),
        ),
        'static_snapshots': _snapshotsByVehicle.map(
          (vehicleId, snapshot) => MapEntry(vehicleId, snapshot.toJson()),
        ),
        'prompt_injection_prefs': _promptInjectionPrefs,
      },
    );
  }

  Future<void> _enableWakelock() async {
    if (_wakelockEnabled) {
      return;
    }
    _wakelockEnabled = true;
    await WakelockPlus.enable();
  }

  Future<void> _disableWakelock() async {
    if (!_wakelockEnabled) {
      return;
    }
    _wakelockEnabled = false;
    await WakelockPlus.disable();
  }

  void _startScanTicker() {
    _scanProgressTicker?.cancel();
    _scanProgressTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
  }

  void _stopScanTicker() {
    _scanProgressTicker?.cancel();
    _scanProgressTicker = null;
  }

  Future<void> _speakDriveCompletion() async {
    try {
      await _tts.stop();
      await _tts.speak('Diagnostic complete. You can safely pull over.');
    } catch (_) {}
  }

  String? _metricKeyForCommand(String command) => switch (command) {
        '010C' => ObdMetricCatalog.rpm,
        '010D' => ObdMetricCatalog.speed,
        '0105' => ObdMetricCatalog.coolantTemp,
        '0111' => ObdMetricCatalog.throttlePosition,
        '010B' => ObdMetricCatalog.intakePressure,
        '0106' => ObdMetricCatalog.shortFuelTrim,
        '0107' => ObdMetricCatalog.longFuelTrim,
        '0104' => ObdMetricCatalog.engineLoad,
        '0110' => ObdMetricCatalog.maf,
        '010E' => ObdMetricCatalog.ignitionTiming,
        _ => null,
      };
}

extension FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
