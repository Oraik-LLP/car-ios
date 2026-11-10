import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../models/ai_response.dart';
import '../../models/diagnostic.dart';
import '../conversations/conversation_chat_screen.dart';
import '../../services/ai_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/file_validation_service.dart';
import '../../services/review_prompt_service.dart';
import '../../services/storage_service.dart';
import '../../services/subscription_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_loading_view.dart';
import '../../widgets/health_score_card.dart';
import '../../widgets/neuomorphic.dart';

class InvoiceAuditScreen extends StatefulWidget {
  const InvoiceAuditScreen({super.key});

  @override
  State<InvoiceAuditScreen> createState() => _InvoiceAuditScreenState();
}

class _InvoiceAuditScreenState extends State<InvoiceAuditScreen> {
  final _picker = ImagePicker();
  final _purposeCtrl = TextEditingController();

  File? _document;
  int _step = 0; // 0=pick, 1=review, 2=analyzing, 3=result
  AiDiagnosticResponse? _result;
  DiagnosticSession? _session;
  bool _hasPromptedReview = false;

  bool get _hasDocument => _document != null;
  bool get _isPdf =>
      _document != null && _document!.path.toLowerCase().endsWith('.pdf');

  bool get _canProceed => switch (_step) {
        0 => _hasDocument,
        1 => true,
        _ => false,
      };

  void _next() {
    if (!_canProceed) return;
    HapticFeedback.selectionClick();
    if (_step == 0) {
      setState(() => _step = 1);
    } else if (_step == 1) {
      _analyze();
    }
  }

  void _back() {
    HapticFeedback.lightImpact();
    if (_step == 1) {
      setState(() => _step = 0);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickCamera() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2200,
      );
      if (xfile != null) {
        await _setDocument(File(xfile.path));
      }
    } on PlatformException catch (_) {
      _showMessage(
        'Camera access is required to capture a bill or estimate. Please '
        'enable camera permission in system settings and try again.',
      );
    } catch (error) {
      _showMessage('Could not capture the selected document: $error');
    }
  }

  Future<void> _pickGallery() async {
    try {
      final xfile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2200,
      );
      if (xfile != null) {
        await _setDocument(File(xfile.path));
      }
    } on PlatformException catch (_) {
      _showMessage(
        'Photo library access is required to choose an image bill. Please '
        'enable media permission in system settings and try again.',
      );
    } catch (error) {
      _showMessage('Could not open your photo library: $error');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
      );
      final path = result?.files.single.path;
      if (path != null && path.isNotEmpty) {
        await _setDocument(File(path));
        return;
      }
      _showMessage('Could not read the selected file on this device.');
    } on PlatformException catch (_) {
      _showMessage(
        'Storage access is required to choose a bill file. Please grant file '
        'access permission and try again.',
      );
    } catch (error) {
      _showMessage('Could not open the selected document: $error');
    }
  }

  Future<void> _setDocument(File file) async {
    final validation =
        await FileValidationService.validateInvoiceDocument(file);
    if (!validation.isValid) {
      _showMessage(validation.message!);
      return;
    }
    if (!mounted) return;
    setState(() => _document = file);
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

  Future<void> _analyze() async {
    final vehicle = VehicleService.instance.selected;
    final document = _document;
    if (vehicle == null || document == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final unlocked = await ensureAccess(
      context,
      FeatureType.invoiceAudit,
      reason: 'Invoice Audit',
    );
    if (!unlocked || !mounted) return;

    setState(() => _step = 2);
    HapticFeedback.heavyImpact();

    try {
      final validation =
          await FileValidationService.validateInvoiceDocument(document);
      if (!validation.isValid) {
        throw Exception(validation.message);
      }

      final storedPath =
          await StorageService.uploadImage(document, folder: vehicle.id);
      final response = await AiService.instance.analyzeInvoiceAudit(
        vehicle: vehicle,
        document: document,
        purpose:
            _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
      );

      final session = DiagnosticSession(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        vehicleId: vehicle.id,
        type: DiagnosticType.invoiceAudit,
        severity: _severityFromVerdict(response.verdict),
        description:
            _purposeCtrl.text.trim().isEmpty ? null : _purposeCtrl.text.trim(),
        imageUrls: [storedPath],
        aiResponse: response.summary,
        aiResponseJson: response.toJson(),
        healthScore: response.healthScore,
        vehicleName: vehicle.displayName,
      );
      await DiagnosticService.instance.save(session);

      if (!mounted) return;
      setState(() {
        _result = response;
        _session = session;
        _step = 3;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = 1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audit failed: ${e.toString().split(':').last.trim()}'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Severity _severityFromVerdict(String? verdict) {
    switch (verdict) {
      case 'Likely Overpriced':
        return Severity.critical;
      case 'Suspicious':
        return Severity.high;
      case 'Mixed':
        return Severity.medium;
      default:
        return Severity.low;
    }
  }

  @override
  void dispose() {
    _purposeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step == 2) {
          Navigator.of(context).pop();
          return;
        }
        _back();
      },
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      if (_step < 2) FixEaseStepBackButton(onPressed: _back),
                      if (_step == 3)
                        FixEaseStepBackButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      const Spacer(),
                      if (_step < 2)
                        Text('Step ${_step + 1} of 2', style: tt.bodySmall),
                    ],
                  ),
                ),
                if (_step < 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / 2,
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceHighlight,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                Expanded(
                  child: switch (_step) {
                    0 => _buildPickStep(tt),
                    1 => _buildReviewStep(tt),
                    2 => _buildAnalyzing(tt),
                    _ => _buildResult(tt),
                  },
                ),
                if (_step < 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: NeuPrimaryButton(
                      label: _step == 1 ? 'Audit Bill' : 'Continue',
                      icon: _step == 1 ? Icons.receipt_long_rounded : null,
                      onPressed: _canProceed ? _next : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPickStep(TextTheme tt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  color: AppColors.accent, size: 24),
              const SizedBox(width: 8),
              Text('Invoice Audit', style: tt.headlineMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Upload a repair bill, estimate, or quote as an image or PDF.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _CaptureButton(
                  icon: Icons.camera_rounded,
                  label: 'Camera',
                  onTap: _pickCamera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CaptureButton(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: _pickGallery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _WideActionButton(
            icon: Icons.attach_file_rounded,
            label: 'Upload PDF or Image',
            onTap: _pickFile,
          ),
          const SizedBox(height: 20),
          if (_document != null) ...[
            Text('Selected document', style: tt.titleMedium),
            const SizedBox(height: 10),
            _DocumentPreview(file: _document!, isPdf: _isPdf),
            const SizedBox(height: 16),
          ] else
            NeuPane(
              child: Column(
                children: [
                  const Icon(Icons.upload_file_rounded,
                      size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: 10),
                  Text('No bill selected yet', style: tt.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Use camera, gallery, or file upload to add a repair bill.',
                    style: tt.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          NeuPane(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Important', style: tt.titleMedium),
                const SizedBox(height: 8),
                Text(kInvoiceAuditWarningText, style: tt.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStep(TextTheme tt) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review & Context', style: tt.headlineMedium),
          const SizedBox(height: 6),
          Text(
            'Check the uploaded bill and optionally tell FixEase what the visit was for.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_document != null) ...[
            _DocumentPreview(file: _document!, isPdf: _isPdf, large: true),
            const SizedBox(height: 20),
          ],
          Text('What was the vehicle in for? (optional)',
              style: tt.titleMedium),
          const SizedBox(height: 8),
          NeuTextField(
            hint: 'e.g. "Brake pads and rotor quote" or "AC not cooling"',
            icon: Icons.edit_note_rounded,
            controller: _purposeCtrl,
          ),
          const SizedBox(height: 20),
          NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What happens next', style: tt.titleMedium),
                const SizedBox(height: 8),
                Text(
                  'FixEase will classify the document, inspect billed labor and fees, flag likely overcharges, and give you questions to ask the shop.',
                  style: tt.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NeuPane(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Important', style: tt.titleMedium),
                const SizedBox(height: 8),
                Text(kInvoiceAuditWarningText, style: tt.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzing(TextTheme tt) {
    return const AiLoadingView(
      title: 'Auditing Your Bill',
      subtitle:
          'FixEase is classifying the document, checking labor overlap, and looking for vague fees, upsells, and pricing signals.',
      stages: [
        'Reading the uploaded bill',
        'Checking labor and parts line items',
        'Flagging likely padding patterns',
        'Preparing your audit summary and questions',
      ],
      tips: [
        'Bills with vague labels like misc or service package deserve extra scrutiny.',
        'Shops sometimes stack diagnostic time twice: once directly and again inside labor.',
        'Related jobs can share labor steps, so duplicated labor hours are worth challenging.',
        'If the uploaded text is incomplete, the audit may be partial rather than wrong.',
      ],
    );
  }

  Widget _buildResult(TextTheme tt) {
    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (!_hasPromptedReview && scrollInfo.metrics.pixels > 150) {
          _hasPromptedReview = true;
          ReviewPromptService.instance.maybePrompt(
            context,
            trigger: ReviewPromptTrigger.diagnosisSuccess,
          );
        }
        return false;
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.accent, size: 28),
              const SizedBox(width: 10),
              Text('Invoice Audit Complete', style: tt.headlineMedium),
            ],
          ),
          const SizedBox(height: 16),
          if (_document != null) ...[
            _DocumentPreview(file: _document!, isPdf: _isPdf),
            const SizedBox(height: 16),
          ],
          if (_result != null)
            DiagnosticResultCard(
              response: _result!,
              session: _session,
            ),
          if (_session != null) ...[
            const SizedBox(height: 12),
            DiagnosticClarifyingQuestionPrompt(
              response: _result!,
              session: _session!,
            ),
            const SizedBox(height: 12),
            NeuSecondaryButton(
              label: 'Continue Conversation',
              icon: Icons.forum_rounded,
              onPressed: () => openConversationChat(
                context,
                session: _session!,
              ),
            ),
          ],
          const SizedBox(height: 20),
          NeuPrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ));
  }
}

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: NeuPane(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.accent),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _WideActionButton extends StatelessWidget {
  const _WideActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: NeuPane(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.accent),
            const SizedBox(width: 12),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({
    required this.file,
    required this.isPdf,
    this.large = false,
  });

  final File file;
  final bool isPdf;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final height = large ? 220.0 : 96.0;

    return NeuPane(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: large ? 120 : 72,
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: AppColors.surfaceHighlight.withValues(alpha: 0.4),
            ),
            clipBehavior: Clip.antiAlias,
            child: isPdf
                ? const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFFFF5252),
                    size: 42,
                  )
                : Image.file(
                    file,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_rounded,
                      color: AppColors.textTertiary,
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPdf ? 'PDF document' : 'Image document',
                  style: tt.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  p.basename(file.path),
                  style: tt.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  isPdf
                      ? 'Gemini will audit the uploaded quote/invoice PDF.'
                      : 'Gemini will audit the uploaded bill image.',
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
