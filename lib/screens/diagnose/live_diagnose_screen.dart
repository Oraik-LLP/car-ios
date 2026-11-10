import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';

import '../../config/feature_flags.dart';
import '../../models/conversation.dart';
import '../../models/diagnostic.dart';
import '../../services/file_validation_service.dart';
import '../../services/gemini_live_service.dart';
import '../../services/obd_pro_service.dart';
import '../../services/quota_service.dart';
import '../../services/subscription_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_markdown_text.dart';
import '../../widgets/neuomorphic.dart';

class LiveDiagnoseScreen extends StatefulWidget {
  const LiveDiagnoseScreen({super.key});

  @override
  State<LiveDiagnoseScreen> createState() => _LiveDiagnoseScreenState();
}

class _LiveDiagnoseScreenState extends State<LiveDiagnoseScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  CameraController? _cameraCtrl;
  Offset _cameraOffset = Offset.zero;
  bool _cameraEnabled = true;
  bool _cameraBusy = false;
  bool _checking = true;
  DeviceCapability? _capability;
  bool _useObdInsight = true;
  int _lastRecordingCapEvent = 0;
  String? _lastHardCapPromptedThreadId;
  static const _pipWidth = 118.0;
  static const _pipHeight = 158.0;
  static const _pipMargin = 14.0;

  @override
  void initState() {
    super.initState();
    final vehicleId = VehicleService.instance.selected?.id;
    if (vehicleId != null) {
      _useObdInsight = ObdProService.instance.isPromptInjectionEnabled(vehicleId);
    }
    _initCamera();
    _runChecks();
  }

  Map<String, dynamic>? _selectedObdPromptContextJson({
    bool respectToggle = true,
  }) {
    final vehicleId = VehicleService.instance.selected?.id;
    if (vehicleId == null) return null;
    final context = ObdProService.instance.latestPromptContextForVehicle(vehicleId);
    if (context == null) return null;
    if (respectToggle && !_useObdInsight) return null;
    return context.toJson();
  }

  Future<void> _setUseObdInsight(bool value) async {
    final vehicleId = VehicleService.instance.selected?.id;
    if (mounted) {
      setState(() => _useObdInsight = value);
    } else {
      _useObdInsight = value;
    }
    GeminiLiveService.instance.setObdContext(
      value ? _selectedObdPromptContextJson(respectToggle: false) : null,
    );
    if (vehicleId != null) {
      await ObdProService.instance.setPromptInjectionEnabled(vehicleId, value);
    }
  }

  Future<void> _initCamera() async {
    if (_cameraBusy || !_cameraEnabled) return;
    _cameraBusy = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final controller = CameraController(
          cameras.first,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        await controller.initialize();
        final previous = _cameraCtrl;
        _cameraCtrl = controller;
        if (previous != null) {
          await previous.dispose();
        }
        if (mounted) setState(() {});
      }
    } on CameraException catch (error) {
      if (!mounted) return;
      _showMessage(_cameraErrorMessage(error));
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code == 'CameraAccessDenied'
            ? 'Camera access is required to capture live photos.'
            : 'Could not start the camera. Please check camera permissions and try again.',
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage(
        'Could not start the camera. Please check camera permissions and try again.',
      );
    } finally {
      _cameraBusy = false;
    }
  }

  bool _disposed = false;

  Future<void> _runChecks() async {
    try {
      final cap = await GeminiLiveService.checkCapability();
      if (!mounted) return;
      setState(() {
        _capability = cap;
        _checking = false;
      });

      if (cap.isReady) {
        final vehicle = VehicleService.instance.selected;
        if (vehicle != null) {
          await GeminiLiveService.instance.startSession(
            vehicle,
            obdContext: _selectedObdPromptContextJson(),
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _checking = false);
      _showMessage(
        'We could not verify live diagnosis readiness right now. Please try again shortly.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    if (_cameraCtrl != null && _cameraCtrl!.value.isInitialized) {
      _cameraCtrl!.dispose();
    }
    if (GeminiLiveService.instance.isActive) {
      GeminiLiveService.instance.endSession();
    }
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _captureAndSend() async {
    final threadId = GeminiLiveService.instance.threadId;
    if (threadId != null &&
        !await ensureAccess(
          context,
          FeatureType.liveImageUpload,
          threadId: threadId,
          threadType: DiagnosticType.live,
          reason: 'More Live Photo Uploads',
        )) {
      return;
    }
    if (_cameraCtrl == null || !_cameraCtrl!.value.isInitialized) return;
    HapticFeedback.heavyImpact();
    String? capturedPath;
    try {
      final xfile = await _cameraCtrl!.takePicture();
      capturedPath = xfile.path;
      if (!mounted) return;
      final file = File(capturedPath);
      final validation = await FileValidationService.validatePhoto(file);
      if (!validation.isValid) {
        _showMessage(validation.message ?? 'Could not use that photo.');
        return;
      }
      final bytes =
          await Isolate.run(() => File(capturedPath!).readAsBytesSync());
      if (!mounted) return;
      await GeminiLiveService.instance.sendImage(Uint8List.fromList(bytes));
      _scrollToBottom();
    } on CameraException catch (error) {
      if (!mounted) return;
      _showMessage(_cameraErrorMessage(error));
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showMessage(
        error.code == 'CameraAccessDenied'
            ? 'Camera access is required to capture live photos.'
            : 'Could not capture a photo. Please try again.',
      );
    } on LiveSessionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not capture a photo. Please try again.');
    } finally {
      try {
        if (capturedPath != null) {
          await File(capturedPath).delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final threadId = GeminiLiveService.instance.threadId;
    if (threadId != null &&
        !await ensureAccess(
          context,
          FeatureType.liveTextMessage,
          threadId: threadId,
          threadType: DiagnosticType.live,
          reason: 'Continue Gemini Live',
        )) {
      return;
    }
    HapticFeedback.selectionClick();
    _msgCtrl.clear();

    await GeminiLiveService.instance.sendText(text);
    _scrollToBottom();
  }

  Future<void> _toggleMic() async {
    final threadId = GeminiLiveService.instance.threadId;
    if (!GeminiLiveService.instance.isRecording &&
        threadId != null &&
        !await ensureAccess(
          context,
          FeatureType.liveAudioTurn,
          threadId: threadId,
          threadType: DiagnosticType.live,
          reason: 'More Live Voice Turns',
        )) {
      return;
    }
    HapticFeedback.mediumImpact();
    try {
      await GeminiLiveService.instance.toggleRecording();
    } on LiveSessionPermissionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } on LiveSessionException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not use the microphone. Please try again.');
    }
    _scrollToBottom();
  }

  void _updateCameraOffset(DragUpdateDetails details, Size bounds) {
    final maxDx = math.max(0.0, bounds.width - _pipWidth - (_pipMargin * 2));
    final maxDy = math.max(0.0, bounds.height - _pipHeight - (_pipMargin * 2));
    final next = _cameraOffset + details.delta;
    setState(() {
      _cameraOffset = Offset(
        next.dx.clamp(-maxDx, 0.0),
        next.dy.clamp(0.0, maxDy),
      );
    });
  }

  Future<void> _setCameraEnabled(bool enabled) async {
    if (_cameraBusy || _cameraEnabled == enabled) return;
    _cameraEnabled = enabled;

    if (!enabled) {
      final controller = _cameraCtrl;
      _cameraCtrl = null;
      if (mounted) setState(() {});
      if (controller != null) {
        await controller.dispose();
      }
      return;
    }

    if (mounted) setState(() {});
    await _initCamera();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cameraErrorMessage(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'Camera access is required to capture live photos during diagnosis.';
      default:
        return 'Could not use the camera right now. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        GeminiLiveService.instance.endSession();
        Navigator.of(context).pop();
      },
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      FixEaseStepBackButton(
                        onPressed: () {
                          GeminiLiveService.instance.endSession();
                          Navigator.of(context).pop();
                        },
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color:
                              const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4CAF50),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE',
                              style: tt.bodySmall?.copyWith(
                                color: const Color(0xFF4CAF50),
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Gemini Live',
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: const Color(0xFFFF9800).withValues(alpha: 0.2),
                        ),
                        child: Text(
                          'BETA',
                          style: tt.bodySmall?.copyWith(
                            color: const Color(0xFFFF9800),
                            fontWeight: FontWeight.w700,
                            fontSize: 8,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _checking
                      ? _buildLoading(tt)
                      : _capability != null && !_capability!.isReady
                          ? _buildBlocker(tt)
                          : _buildChatView(tt),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.accent,
          ),
          const SizedBox(height: 20),
          Text('Checking device capabilities...', style: tt.bodyMedium),
        ],
      ),
    );
  }

  Widget _buildBlocker(TextTheme tt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Color(0xFFFF9800)),
            const SizedBox(height: 16),
            Text('Cannot Start Live Session',
                style: tt.headlineMedium, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              _capability?.blockerMessage ?? 'Unknown issue',
              style: tt.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            NeuSecondaryButton(
              label: 'Go Back',
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatView(TextTheme tt) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        GeminiLiveService.instance,
        ObdProService.instance,
        SubscriptionService.instance,
      ]),
      builder: (context, _) {
        final svc = GeminiLiveService.instance;
        final msgs = svc.messages;
        final isAnalyzing = svc.state == LiveSessionState.analyzing;
        final isDone = svc.state == LiveSessionState.done;
        final cameraEnabled = _cameraEnabled;
        final threadId = svc.threadId;
        final vehicleId = VehicleService.instance.selected?.id;
        final latestObdContext = vehicleId == null
            ? null
            : ObdProService.instance.latestPromptContextForVehicle(vehicleId);
        final showObdToggle = latestObdContext != null;
        final limits = threadId == null
            ? null
            : SubscriptionService.instance.threadLimitStatus(
                sessionId: threadId,
                sessionType: DiagnosticType.live,
              );
        final liveHardBlocked = limits?.liveHardBlocked ?? false;
        final liveImageBlocked = limits?.liveImageLimitReached ?? false;
        final liveWarningText = !SubscriptionService
                    .instance.hasPremiumAccess &&
                (limits?.liveAudioRemaining ?? 99) <= 2 &&
                (limits?.liveAudioRemaining ?? 99) > 0
            ? '${limits!.liveAudioRemaining} free voice turn${limits.liveAudioRemaining == 1 ? '' : 's'} remaining'
            : null;

        if (svc.recordingCapEvents != _lastRecordingCapEvent) {
          _lastRecordingCapEvent = svc.recordingCapEvents;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Free voice turns auto-send after 3:00. Unlock 10-minute live audio for longer recordings.',
                ),
                behavior: SnackBarBehavior.floating,
                action: SnackBarAction(
                  label: 'Unlock',
                  onPressed: () {
                    ensureAccess(
                      context,
                      FeatureType.extendedLiveAudio,
                      reason: '10-minute Live Audio',
                    );
                  },
                ),
              ),
            );
          });
        }

        if (liveHardBlocked &&
            threadId != null &&
            _lastHardCapPromptedThreadId != threadId) {
          _lastHardCapPromptedThreadId = threadId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ensureAccess(
              context,
              limits?.liveAudioLimitReached == true
                  ? FeatureType.liveAudioTurn
                  : limits?.liveTextLimitReached == true
                      ? FeatureType.liveTextMessage
                      : FeatureType.liveImageUpload,
              threadId: threadId,
              threadType: DiagnosticType.live,
              reason: 'Continue Gemini Live',
            );
          });
        }

        _scrollToBottom();

        return Column(
          children: [
            if (showObdToggle)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _LiveObdPromptToggle(
                  value: _useObdInsight,
                  onChanged: _setUseObdInsight,
                ),
              ),
            if (SubscriptionService.instance.isDemoMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _LiveUsageStrip(limits: limits),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showCamera =
                      _cameraCtrl != null && _cameraCtrl!.value.isInitialized;
                  final topInset =
                      showCamera ? (_pipHeight + (_pipMargin * 2)) : 0.0;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: msgs.isEmpty
                            ? _buildWelcome(tt, topPadding: topInset)
                            : ListView.builder(
                                controller: _scrollCtrl,
                                padding: EdgeInsets.fromLTRB(
                                  16,
                                  8 + topInset,
                                  16,
                                  12,
                                ),
                                itemCount: msgs.length + (isAnalyzing ? 1 : 0),
                                itemBuilder: (_, i) {
                                  if (i == msgs.length && isAnalyzing) {
                                    return _TypingIndicator();
                                  }
                                  return _ChatBubble(message: msgs[i]);
                                },
                              ),
                      ),
                      if (showCamera)
                        Positioned(
                          top: _pipMargin + _cameraOffset.dy,
                          right: _pipMargin + (-_cameraOffset.dx),
                          child: GestureDetector(
                            onPanUpdate: (details) => _updateCameraOffset(
                              details,
                              constraints.biggest,
                            ),
                            onTap: isAnalyzing ||
                                    liveHardBlocked ||
                                    liveImageBlocked
                                ? () {
                                    ensureAccess(
                                      context,
                                      FeatureType.liveImageUpload,
                                      threadId: threadId,
                                      threadType: DiagnosticType.live,
                                      reason: 'More Live Photo Uploads',
                                    );
                                  }
                                : _captureAndSend,
                            child: _LiveCameraPip(
                              cameraController: _cameraCtrl!,
                              isRecording: svc.isRecording,
                              liveImageBlocked: liveImageBlocked,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (liveWarningText != null || liveHardBlocked || liveImageBlocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: NeuPane(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          liveHardBlocked
                              ? 'This free live thread has reached its cap. Upgrade to keep sending text, voice, or photos.'
                              : liveImageBlocked
                                  ? 'This live thread has used all included photo uploads.'
                                  : liveWarningText!,
                          style: tt.bodySmall?.copyWith(
                            color: liveHardBlocked
                                ? const Color(0xFFFFB4A9)
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 110,
                        child: NeuPrimaryButton(
                          expanded: false,
                          label: 'Upgrade',
                          onPressed: () {
                            ensureAccess(
                              context,
                              liveImageBlocked
                                  ? FeatureType.liveImageUpload
                                  : FeatureType.liveAudioTurn,
                              threadId: threadId,
                              threadType: DiagnosticType.live,
                              reason: 'Continue Gemini Live',
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (!isDone)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.5),
                  border:
                      const Border(top: BorderSide(color: Color(0x0CFFFFFF))),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: isAnalyzing
                                ? null
                                : () {
                                    if (liveHardBlocked) {
                                      ensureAccess(
                                        context,
                                        FeatureType.liveAudioTurn,
                                        threadId: threadId,
                                        threadType: DiagnosticType.live,
                                        reason: 'More Live Voice Turns',
                                      );
                                      return;
                                    }
                                    _toggleMic();
                                  },
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (svc.isRecording)
                                    SizedBox(
                                      width: 52,
                                      height: 52,
                                      child: CircularProgressIndicator(
                                        value: svc.recordingProgress,
                                        strokeWidth: 3,
                                        backgroundColor:
                                            AppColors.surfaceHighlight,
                                        color: svc.isNearRecordingLimit
                                            ? const Color(0xFFEF4444)
                                            : AppColors.accent,
                                      ),
                                    ),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: svc.isRecording
                                          ? const Color(0xFFEF4444)
                                          : isAnalyzing
                                              ? AppColors.surfaceHighlight
                                              : AppColors.accent.withValues(
                                                  alpha: 0.15,
                                                ),
                                      border: Border.all(
                                        color: svc.isRecording
                                            ? const Color(0xFFEF4444)
                                            : isAnalyzing
                                                ? const Color(0x0CFFFFFF)
                                                : AppColors.accent.withValues(
                                                    alpha: 0.4,
                                                  ),
                                      ),
                                    ),
                                    child: Icon(
                                      svc.isRecording
                                          ? Icons.stop_rounded
                                          : Icons.mic_rounded,
                                      size: 20,
                                      color: svc.isRecording
                                          ? Colors.white
                                          : isAnalyzing
                                              ? AppColors.textTertiary
                                              : AppColors.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            svc.isRecording
                                ? '${svc.recordingTimeLabel} / ${svc.recordingLimitLabel}'
                                : svc.recordingLimitLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 10,
                                      color: svc.isRecording &&
                                              svc.isNearRecordingLimit
                                          ? const Color(0xFFEF4444)
                                          : AppColors.textTertiary,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _LiveActionButton(
                      icon: cameraEnabled
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      enabled: !_cameraBusy && !isAnalyzing,
                      active: cameraEnabled,
                      onTap: () => _setCameraEnabled(!cameraEnabled),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: NeuTextField(
                        hint: 'Type a message...',
                        icon: Icons.chat_rounded,
                        controller: _msgCtrl,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        readOnly: liveHardBlocked,
                        onTap: liveHardBlocked
                            ? () {
                                ensureAccess(
                                  context,
                                  limits?.liveTextLimitReached == true
                                      ? FeatureType.liveTextMessage
                                      : FeatureType.liveAudioTurn,
                                  threadId: threadId,
                                  threadType: DiagnosticType.live,
                                  reason: 'Continue Gemini Live',
                                );
                              }
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: isAnalyzing
                          ? null
                          : () {
                              if (liveHardBlocked) {
                                ensureAccess(
                                  context,
                                  limits?.liveTextLimitReached == true
                                      ? FeatureType.liveTextMessage
                                      : FeatureType.liveAudioTurn,
                                  threadId: threadId,
                                  threadType: DiagnosticType.live,
                                  reason: 'Continue Gemini Live',
                                );
                                return;
                              }
                              _sendText();
                            },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isAnalyzing || liveHardBlocked
                              ? AppColors.surfaceHighlight
                              : AppColors.accent,
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          size: 18,
                          color: isAnalyzing || liveHardBlocked
                              ? AppColors.textTertiary
                              : Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(16),
                child: NeuPrimaryButton(
                  label: 'End Session',
                  icon: Icons.check_circle_rounded,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildWelcome(TextTheme tt, {double topPadding = 0}) {
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 32 + topPadding, 32, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.1),
              ),
              child: const Icon(Icons.mic_rounded,
                  size: 40, color: AppColors.accent),
            ),
            const SizedBox(height: 20),
            Text('FixEase Voice', style: tt.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Tap the mic to speak, type a message, or snap a photo. Gemini will diagnose your car issue.',
              style: tt.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveCameraPip extends StatelessWidget {
  const _LiveCameraPip({
    required this.cameraController,
    required this.isRecording,
    required this.liveImageBlocked,
  });

  final CameraController cameraController;
  final bool isRecording;
  final bool liveImageBlocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _LiveDiagnoseScreenState._pipWidth,
      height: _LiveDiagnoseScreenState._pipHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isRecording
              ? const Color(0xFFEF4444)
              : AppColors.accent.withValues(alpha: 0.35),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.5),
        child: Stack(
          children: [
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cameraController.value.previewSize?.height ?? 1,
                  height: cameraController.value.previewSize?.width ?? 1,
                  child: CameraPreview(cameraController),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.18),
                    ],
                    stops: const [0, 0.45, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isRecording
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF4CAF50),
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        liveImageBlocked ? 'Photo limit reached' : 'Snap photo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        softWrap: true,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveObdPromptToggle extends StatelessWidget {
  const _LiveObdPromptToggle({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return NeuPane(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Use latest OBD Pro insight', style: tt.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Append the latest saved idle and drive findings to future live turns for this vehicle.',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NeuToggle(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LiveUsageStrip extends StatelessWidget {
  const _LiveUsageStrip({required this.limits});

  final ThreadLimitStatus? limits;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demo live usage',
            style: tt.labelLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LiveUsageChip(
                label: 'Voice',
                used: limits?.liveAudioCount ?? 0,
                limit: limits?.liveAudioLimit,
              ),
              _LiveUsageChip(
                label: 'Text',
                used: limits?.liveTextCount ?? 0,
                limit: limits?.liveTextLimit,
              ),
              _LiveUsageChip(
                label: 'Photos',
                used: limits?.liveImageCount ?? 0,
                limit: limits?.liveImageLimit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LiveUsageChip extends StatelessWidget {
  const _LiveUsageChip({
    required this.label,
    required this.used,
    required this.limit,
  });

  final String label;
  final int used;
  final int? limit;

  @override
  Widget build(BuildContext context) {
    final ratio =
        limit == null || limit == 0 ? 0.0 : (used / limit!).clamp(0.0, 1.0);
    final isNearCap = limit != null && ratio >= 0.8;
    final accent = isNearCap ? const Color(0xFFFFB366) : AppColors.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            limit == null ? '$used / ∞' : '$used / $limit',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _LiveActionButton extends StatelessWidget {
  const _LiveActionButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? AppColors.accent.withValues(alpha: 0.15)
        : AppColors.surfaceHighlight;
    final border = active
        ? AppColors.accent.withValues(alpha: 0.35)
        : const Color(0x0CFFFFFF);
    final iconColor = active
        ? AppColors.accent
        : enabled
            ? AppColors.textSecondary
            : AppColors.textTertiary;

    return GestureDetector(
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onTap();
            }
          : null,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: background,
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});
  final LiveMessage message;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isUser = message.isUser;
    final maxBubbleWidth = MediaQuery.sizeOf(context).width * 0.72;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.15),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  size: 14, color: AppColors.accent),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxBubbleWidth),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 16 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 16),
                  ),
                  color: isUser
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.surface,
                  border: Border.all(
                    color: isUser
                        ? AppColors.accent.withValues(alpha: 0.3)
                        : const Color(0x0CFFFFFF),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.hasAttachment &&
                        message.source == ConversationMessageSource.image &&
                        message.attachmentPath != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: double.infinity,
                            height: 160,
                            child: Image.file(
                              File(message.attachmentPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surfaceHighlight
                                    .withValues(alpha: 0.35),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.image_not_supported_rounded,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isUser)
                      Text(
                        message.previewText,
                        softWrap: true,
                        style: tt.bodyMedium?.copyWith(
                          color: AppColors.accent,
                        ),
                      )
                    else
                      AppMarkdownText(
                        message.previewText,
                        style: tt.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Typing indicator
// ═══════════════════════════════════════════════════════════════════════════════

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withValues(alpha: 0.15),
            ),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 14, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              color: AppColors.surface,
              border: Border.all(color: const Color(0x0CFFFFFF), width: 0.5),
            ),
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final v = _ctrl.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (i) {
                    final delay = i * 0.25;
                    final opacity =
                        (0.3 + 0.7 * ((v + delay) % 1.0)).clamp(0.3, 1.0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Opacity(
                        opacity: opacity,
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper to gate access to Gemini Live from the Diagnose tab.
Future<void> launchLiveDiagnosis(BuildContext context) async {
  final vehicle = VehicleService.instance.selected;
  if (vehicle == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add a vehicle first')),
    );
    return;
  }

  if (!FeatureFlags.geminiLiveBeta) {
    final optedIn = await _showBetaDialog(context);
    if (!context.mounted || optedIn != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        content: const Text(
          'Beta enabled! Try Gemini Live now.',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  } else if (!context.mounted) {
    return;
  }

  final allowed = await QuotaService.instance.ensureCanStartDiagnosis(context);
  if (!allowed || !context.mounted) {
    return;
  }

  GeminiLiveService.instance.reset();
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => const LiveDiagnoseScreen(),
  ));
}

Future<bool?> _showBetaDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.science_rounded, color: AppColors.accent, size: 22),
          const SizedBox(width: 8),
          Text('Beta Feature', style: Theme.of(ctx).textTheme.titleLarge),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gemini Live video diagnosis is currently in closed beta.',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Would you like to opt in?',
            style: Theme.of(ctx).textTheme.bodyMedium,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child:
              Text('Not Now', style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            FeatureFlags.override('gemini_live_beta', true);
            Navigator.pop(ctx, true);
          },
          child:
              const Text('Opt In', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    ),
  );
}
