import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/conversation.dart';
import '../../models/diagnostic.dart';
import '../../models/vehicle.dart';
import '../../services/ai_service.dart';
import '../../services/conversation_service.dart';
import '../../services/file_validation_service.dart';
import '../../services/subscription_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_markdown_text.dart';
import '../../widgets/neuomorphic.dart';

Future<void> openConversationChat(
  BuildContext context, {
  required DiagnosticSession session,
  String? initialReplyQuestion,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ConversationChatScreen(
        session: session,
        initialReplyQuestion: initialReplyQuestion,
      ),
    ),
  );
}

class ConversationChatScreen extends StatefulWidget {
  const ConversationChatScreen({
    super.key,
    required this.session,
    this.initialReplyQuestion,
  });

  final DiagnosticSession session;
  final String? initialReplyQuestion;

  @override
  State<ConversationChatScreen> createState() => _ConversationChatScreenState();
}

class _ConversationChatScreenState extends State<ConversationChatScreen> {
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isSending = false;
  bool _isRecording = false;
  String? _replyToQuestion;

  ConversationThread? get _thread =>
      ConversationService.instance.threadForSession(widget.session.id);

  ThreadLimitStatus get _limits =>
      SubscriptionService.instance.threadLimitStatus(
        sessionId: widget.session.id,
        sessionType: widget.session.type,
      );

  bool get _isLiveThread => widget.session.type == DiagnosticType.live;

  bool get _textInputBlocked => _isLiveThread
      ? _limits.liveHardBlocked || _limits.liveTextLimitReached
      : _limits.textAudioLimitReached;

  bool get _mediaBlocked => _isLiveThread
      ? _limits.liveHardBlocked || _limits.liveImageLimitReached
      : _limits.standardImageLimitReached;

  String get _composerHint {
    if (_isRecording) return 'Recording voice note...';
    if (_textInputBlocked) {
      return _isLiveThread ? 'Live limit reached' : 'Free chat limit reached';
    }
    if (_replyToQuestion != null) return 'Type your answer...';
    return 'Ask a follow-up question...';
  }

  bool get _shouldShowLimitBanner {
    if (_isLiveThread) {
      return _limits.liveHardBlocked ||
          _limits.liveImageLimitReached ||
          ((_limits.liveAudioRemaining ?? 99) <= 2 &&
              !_limits.liveAudioLimitReached);
    }
    return _limits.textAudioLimitReached || _limits.standardImageLimitReached;
  }

  FeatureType get _bannerFeature {
    if (_isLiveThread) {
      if (_limits.liveImageLimitReached) return FeatureType.liveImageUpload;
      if (_limits.liveTextLimitReached) return FeatureType.liveTextMessage;
      return FeatureType.liveAudioTurn;
    }
    return _limits.standardImageLimitReached
        ? FeatureType.standardFollowUpMedia
        : FeatureType.standardFollowUpMessage;
  }

  String get _limitBannerTitle {
    if (_isLiveThread) {
      if (_limits.liveHardBlocked) return 'Free live thread limit reached';
      if (_limits.liveImageLimitReached) return 'Live image limit reached';
      final remaining = _limits.liveAudioRemaining ?? 0;
      return '$remaining free voice turn${remaining == 1 ? '' : 's'} remaining';
    }
    if (_limits.textAudioLimitReached) return 'Free chat limit reached';
    return 'Attachment limit reached';
  }

  String get _limitBannerSubtitle {
    if (_isLiveThread) {
      if (_limits.liveHardBlocked) {
        return 'Upgrade to keep sending text, voice, or photos in this live thread.';
      }
      if (_limits.liveImageLimitReached) {
        return 'This live thread has used all included photo uploads.';
      }
      return 'You are close to the free voice cap for this live thread.';
    }
    if (_limits.textAudioLimitReached) {
      return 'Free threads include up to 10 text or voice turns. Upgrade to keep going.';
    }
    return 'Free threads include up to 3 uploads. Upgrade to add more.';
  }

  Vehicle? get _vehicle {
    for (final vehicle in VehicleService.instance.vehicles) {
      if (vehicle.id == widget.session.vehicleId) return vehicle;
    }
    final selected = VehicleService.instance.selected;
    if (selected?.id == widget.session.vehicleId) return selected;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _replyToQuestion = widget.initialReplyQuestion?.trim().isNotEmpty == true
        ? widget.initialReplyQuestion!.trim()
        : null;
    _ensureThread();
  }

  Future<void> _ensureThread() async {
    await ConversationService.instance.createOrGetThread(
      sessionId: widget.session.id,
      vehicleId: widget.session.vehicleId,
    );
    if (!mounted) return;
    setState(() {});
    _scrollToBottom();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
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

  Future<void> _sendText() async {
    final raw = _messageCtrl.text.trim();
    if (raw.isEmpty || _isSending) return;
    if (!await _ensureActionAccess(
      _isLiveThread
          ? FeatureType.liveTextMessage
          : FeatureType.standardFollowUpMessage,
    )) {
      return;
    }
    _messageCtrl.clear();
    final visibleText = _buildVisibleReplyText(raw);
    await _sendTurn(
      text: _buildAiReplyText(raw),
      userVisibleText: visibleText,
      source: ConversationMessageSource.text,
    );
  }

  Future<void> _pickCamera() async {
    if (_isSending || _isRecording) return;
    if (!await _ensureActionAccess(
      _isLiveThread
          ? FeatureType.liveImageUpload
          : FeatureType.standardFollowUpMedia,
    )) {
      return;
    }
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 2200,
      );
      if (xfile == null) return;
      final file = File(xfile.path);
      final validation = await FileValidationService.validatePhoto(file);
      if (!validation.isValid) {
        _showMessage(validation.message!);
        return;
      }
      await _sendAttachment(
        file,
        source: ConversationMessageSource.image,
        attachmentMimeType: validation.mimeType,
      );
    } on PlatformException catch (_) {
      _showMessage(
        'Camera access is required to attach photos. Please enable camera '
        'permission in system settings and try again.',
      );
    } catch (error) {
      _showMessage('Could not attach the selected photo: $error');
    }
  }

  Future<void> _pickAttachment() async {
    if (_isSending || _isRecording) return;
    if (!await _ensureActionAccess(
      _isLiveThread
          ? FeatureType.liveImageUpload
          : FeatureType.standardFollowUpMedia,
    )) {
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      final file = File(path);
      final validation =
          await FileValidationService.validateInvoiceDocument(file);
      if (!validation.isValid) {
        _showMessage(validation.message!);
        return;
      }
      final mimeType = validation.mimeType!;
      final source = mimeType.startsWith('image/')
          ? ConversationMessageSource.image
          : ConversationMessageSource.file;
      await _sendAttachment(
        file,
        source: source,
        attachmentMimeType: mimeType,
      );
    } on PlatformException catch (_) {
      _showMessage(
        'Storage access is required to attach files. Please grant file access '
        'permission and try again.',
      );
    } catch (error) {
      _showMessage('Could not attach the selected file: $error');
    }
  }

  Future<void> _sendAttachment(
    File file, {
    required ConversationMessageSource source,
    String? attachmentMimeType,
  }) async {
    final note = _messageCtrl.text.trim();
    _messageCtrl.clear();
    final visibleText = note.isNotEmpty
        ? note
        : source == ConversationMessageSource.image
            ? 'Photo attached'
            : 'File attached';
    await _sendTurn(
      text: note.isNotEmpty ? note : null,
      userVisibleText: visibleText,
      source: source,
      attachment: file,
      attachmentName: p.basename(file.path),
      attachmentMimeType: attachmentMimeType,
    );
  }

  Future<void> _toggleRecording() async {
    if (_isSending) return;
    if (!await _ensureActionAccess(
      _isLiveThread
          ? FeatureType.liveAudioTurn
          : FeatureType.standardFollowUpMessage,
    )) {
      return;
    }
    if (_isRecording) {
      await _stopAndSendAudio();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      _showMessage(
        'Microphone access is required to send voice notes. Please enable '
        'microphone permission in system settings and try again.',
      );
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/fixease_conversation_${DateTime.now().millisecondsSinceEpoch}.wav';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
        ),
        path: path,
      );
    } catch (error) {
      _showMessage('Could not start voice recording: $error');
      return;
    }

    if (!mounted) return;
    setState(() => _isRecording = true);
  }

  Future<void> _stopAndSendAudio() async {
    final path = await _recorder.stop();
    if (!mounted) return;
    setState(() => _isRecording = false);
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    try {
      final bytes = await file.length();
      if (bytes < 1000) {
        await file.delete();
        return;
      }

      await _sendTurn(
        text: null,
        userVisibleText: 'Voice note',
        source: ConversationMessageSource.audio,
        audioFile: file,
      );
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _sendTurn({
    required String? text,
    required String userVisibleText,
    required ConversationMessageSource source,
    File? attachment,
    File? audioFile,
    String? attachmentName,
    String? attachmentMimeType,
  }) async {
    HapticFeedback.selectionClick();
    final replyQuestion = _replyToQuestion;

    final timestamp = DateTime.now();
    final userMessage = ConversationMessage(
      id: _messageId(),
      role: ConversationMessageRole.user,
      text: userVisibleText,
      createdAt: timestamp,
      source: source,
      attachmentPath: attachment?.path,
      attachmentName: attachmentName,
      attachmentMimeType: attachmentMimeType,
    );

    await ConversationService.instance.appendMessage(
      sessionId: widget.session.id,
      vehicleId: widget.session.vehicleId,
      message: userMessage,
    );

    if (!mounted) return;
    setState(() {
      _isSending = true;
      if (replyQuestion != null) {
        _replyToQuestion = null;
      }
    });
    _scrollToBottom();

    final history = _thread?.messages ?? [userMessage];
    final reply = await AiService.instance.continueConversation(
      vehicle: _vehicle,
      session: widget.session,
      history: history,
      message: text,
      audioFile: audioFile,
      attachment: attachment,
    );

    if (reply.requestSucceeded) {
      await SubscriptionService.instance.recordThreadEvent(
        sessionId: widget.session.id,
        sessionType: widget.session.type,
        event: _eventForSource(source),
      );
    }

    await ConversationService.instance.appendMessage(
      sessionId: widget.session.id,
      vehicleId: widget.session.vehicleId,
      message: ConversationMessage(
        id: _messageId(),
        role: ConversationMessageRole.assistant,
        text: reply.text.trim().isNotEmpty
            ? reply.text.trim()
            : 'I could not generate a response just now.',
        createdAt: DateTime.now(),
        source: ConversationMessageSource.text,
      ),
    );

    if (!mounted) return;
    setState(() => _isSending = false);
    _scrollToBottom();
  }

  String _buildAiReplyText(String raw) {
    final replyQuestion = _replyToQuestion;
    if (replyQuestion == null || replyQuestion.isEmpty) {
      return raw;
    }
    return 'Replying to your clarifying question "$replyQuestion": $raw\nIf you need anything else clarified, ask one short follow-up question.';
  }

  String _buildVisibleReplyText(String raw) {
    final replyQuestion = _replyToQuestion;
    if (replyQuestion == null || replyQuestion.isEmpty) {
      return raw;
    }
    return 'Replying to: "$replyQuestion"\n$raw';
  }

  String _messageId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  ThreadUsageEvent _eventForSource(ConversationMessageSource source) {
    if (_isLiveThread) {
      return switch (source) {
        ConversationMessageSource.audio => ThreadUsageEvent.liveAudio,
        ConversationMessageSource.text => ThreadUsageEvent.liveText,
        ConversationMessageSource.image => ThreadUsageEvent.liveImage,
        ConversationMessageSource.file => ThreadUsageEvent.liveImage,
      };
    }
    return switch (source) {
      ConversationMessageSource.text => ThreadUsageEvent.standardMessage,
      ConversationMessageSource.audio => ThreadUsageEvent.standardMessage,
      ConversationMessageSource.image => ThreadUsageEvent.standardMedia,
      ConversationMessageSource.file => ThreadUsageEvent.standardMedia,
    };
  }

  Future<bool> _ensureActionAccess(FeatureType feature) async {
    if (checkAccess(feature, session: widget.session)) return true;
    if (!mounted) return false;
    return ensureAccess(
      context,
      feature,
      session: widget.session,
      reason: _upgradeReason(feature),
    );
  }

  String _upgradeReason(FeatureType feature) => switch (feature) {
        FeatureType.standardFollowUpMessage => 'Continue Conversation',
        FeatureType.standardFollowUpMedia => 'Conversation Attachments',
        FeatureType.liveTextMessage => 'Continue Gemini Live',
        FeatureType.liveAudioTurn => 'More Live Voice Turns',
        FeatureType.liveImageUpload => 'More Live Photo Uploads',
        _ => 'Unlock Premium',
      };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: SubscriptionService.instance,
            builder: (context, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                  child: Row(
                    children: [
                      FixEaseStepBackButton(
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Continue Conversation', style: tt.titleLarge),
                            const SizedBox(height: 2),
                            Text(
                              widget.session.typeTitle,
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (SubscriptionService.instance.isDemoMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: _ThreadUsageStrip(
                      isLiveThread: _isLiveThread,
                      limits: _limits,
                    ),
                  ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: ConversationService.instance,
                    builder: (context, _) {
                      final thread = _thread;
                      final messages =
                          thread?.messages ?? const <ConversationMessage>[];
                      _scrollToBottom();

                      if (messages.isEmpty) {
                        return _EmptyConversationState(session: widget.session);
                      }

                      return ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        itemCount: messages.length + (_isSending ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messages.length) {
                            return const _ConversationTypingIndicator();
                          }
                          return _ConversationBubble(message: messages[index]);
                        },
                      );
                    },
                  ),
                ),
                if (_replyToQuestion != null && _replyToQuestion!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: _ReplyingBanner(
                      question: _replyToQuestion!,
                      onCancel: () {
                        HapticFeedback.lightImpact();
                        setState(() => _replyToQuestion = null);
                      },
                    ),
                  ),
                if (_shouldShowLimitBanner)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _ConversationLimitBanner(
                      title: _limitBannerTitle,
                      subtitle: _limitBannerSubtitle,
                      actionLabel: 'Upgrade to Pro',
                      onAction: () {
                        ensureAccess(
                          context,
                          _bannerFeature,
                          session: widget.session,
                          reason: _upgradeReason(_bannerFeature),
                        );
                      },
                    ),
                  ),
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.5),
                      border: const Border(
                        top: BorderSide(color: Color(0x0CFFFFFF)),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _ComposerButton(
                          icon: Icons.camera_alt_rounded,
                          enabled:
                              !_isSending && !_isRecording && !_mediaBlocked,
                          onTap: _pickCamera,
                        ),
                        const SizedBox(width: 8),
                        _ComposerButton(
                          icon: Icons.attach_file_rounded,
                          enabled:
                              !_isSending && !_isRecording && !_mediaBlocked,
                          onTap: _pickAttachment,
                        ),
                        const SizedBox(width: 8),
                        _ComposerButton(
                          icon: _isRecording
                              ? Icons.stop_rounded
                              : Icons.mic_rounded,
                          enabled: !_isSending && !_textInputBlocked,
                          active: _isRecording,
                          onTap: _toggleRecording,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: NeuTextField(
                            hint: _composerHint,
                            icon: Icons.chat_rounded,
                            controller: _messageCtrl,
                            keyboardType: TextInputType.multiline,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.newline,
                            readOnly: _textInputBlocked || _isRecording,
                            onTap: _textInputBlocked
                                ? () {
                                    ensureAccess(
                                      context,
                                      _bannerFeature,
                                      session: widget.session,
                                      reason: _upgradeReason(_bannerFeature),
                                    );
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_textInputBlocked)
                          SizedBox(
                            width: 132,
                            child: NeuPrimaryButton(
                              expanded: false,
                              label: 'Upgrade',
                              onPressed: () {
                                ensureAccess(
                                  context,
                                  _bannerFeature,
                                  session: widget.session,
                                  reason: _upgradeReason(_bannerFeature),
                                );
                              },
                            ),
                          )
                        else
                          _ComposerButton(
                            icon: Icons.send_rounded,
                            enabled: !_isSending && !_isRecording,
                            filled: true,
                            onTap: _sendText,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConversationLimitBanner extends StatelessWidget {
  const _ConversationLimitBanner({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 118,
            child: NeuPrimaryButton(
              expanded: false,
              label: actionLabel,
              onPressed: onAction,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadUsageStrip extends StatelessWidget {
  const _ThreadUsageStrip({
    required this.isLiveThread,
    required this.limits,
  });

  final bool isLiveThread;
  final ThreadLimitStatus limits;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final items = isLiveThread
        ? [
            _UsageChipData(
              label: 'Voice',
              used: limits.liveAudioCount,
              limit: limits.liveAudioLimit,
            ),
            _UsageChipData(
              label: 'Text',
              used: limits.liveTextCount,
              limit: limits.liveTextLimit,
            ),
            _UsageChipData(
              label: 'Photos',
              used: limits.liveImageCount,
              limit: limits.liveImageLimit,
            ),
          ]
        : [
            _UsageChipData(
              label: 'Text + voice',
              used: limits.textAudioCount,
              limit: limits.textAudioLimit,
            ),
            _UsageChipData(
              label: 'Uploads',
              used: limits.imageCount,
              limit: limits.imageLimit,
            ),
          ];

    return NeuPane(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Demo thread usage',
            style: tt.labelLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map(_UsageStatChip.new).toList(),
          ),
        ],
      ),
    );
  }
}

class _UsageChipData {
  const _UsageChipData({
    required this.label,
    required this.used,
    required this.limit,
  });

  final String label;
  final int used;
  final int? limit;
}

class _UsageStatChip extends StatelessWidget {
  const _UsageStatChip(this.data);

  final _UsageChipData data;

  @override
  Widget build(BuildContext context) {
    final limit = data.limit;
    final ratio =
        limit == null || limit == 0 ? 0.0 : (data.used / limit).clamp(0.0, 1.0);
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
            data.label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            limit == null ? '${data.used} / ∞' : '${data.used} / $limit',
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

class _ComposerButton extends StatelessWidget {
  const _ComposerButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.active = false,
    this.filled = false,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool active;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? const Color(0xFFEF4444)
        : filled
            ? AppColors.accent
            : AppColors.accent.withValues(alpha: 0.15);
    final border = active
        ? const Color(0xFFEF4444)
        : filled
            ? AppColors.accent
            : AppColors.accent.withValues(alpha: 0.35);
    final iconColor = active || filled
        ? Colors.white
        : enabled
            ? AppColors.accent
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
          shape: BoxShape.circle,
          color: enabled ? background : AppColors.surfaceHighlight,
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}

class _ReplyingBanner extends StatelessWidget {
  const _ReplyingBanner({
    required this.question,
    required this.onCancel,
  });

  final String question;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Replying to the clarifying question',
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(question, style: tt.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onCancel,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceHighlight.withValues(alpha: 0.45),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversationState extends StatelessWidget {
  const _EmptyConversationState({required this.session});

  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: NeuPane(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.12),
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  size: 30,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 18),
              Text('No messages yet', style: tt.titleLarge),
              const SizedBox(height: 8),
              Text(
                session.type == DiagnosticType.invoiceAudit
                    ? 'Ask about the bill, challenge line items, or attach another quote or invoice for more context.'
                    : session.type == DiagnosticType.live
                        ? 'Continue the saved Gemini Live conversation here with text, voice, or attachments.'
                        : 'Ask a follow-up question about the diagnosis, next steps, urgency, or attach a new image for more help.',
                style: tt.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationBubble extends StatelessWidget {
  const _ConversationBubble({required this.message});

  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isUser = message.role == ConversationMessageRole.user;
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
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppColors.accent,
              ),
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
                    if (message.hasAttachment &&
                        (message.attachmentName?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: AppColors.surfaceHighlight
                              .withValues(alpha: 0.35),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              message.source == ConversationMessageSource.image
                                  ? Icons.image_rounded
                                  : Icons.attach_file_rounded,
                              size: 14,
                              color: isUser
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                message.attachmentName!,
                                style: tt.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTypingIndicator extends StatefulWidget {
  const _ConversationTypingIndicator();

  @override
  State<_ConversationTypingIndicator> createState() =>
      _ConversationTypingIndicatorState();
}

class _ConversationTypingIndicatorState
    extends State<_ConversationTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
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
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 14,
              color: AppColors.accent,
            ),
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
              border: Border.all(
                color: const Color(0x0CFFFFFF),
                width: 0.5,
              ),
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                final value = _controller.value;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final delay = index * 0.25;
                    final opacity =
                        (0.3 + 0.7 * ((value + delay) % 1.0)).clamp(0.3, 1.0);
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
