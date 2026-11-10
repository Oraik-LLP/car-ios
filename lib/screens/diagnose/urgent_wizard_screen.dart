import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/ai_response.dart';
import '../../models/diagnostic.dart';
import '../conversations/conversation_chat_screen.dart';
import '../../services/ai_service.dart';
import '../../services/diagnostic_service.dart';
import '../../services/quota_service.dart';
import '../../services/review_prompt_service.dart';
import '../../services/vehicle_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ai_loading_view.dart';
import '../../widgets/health_score_card.dart';
import '../../widgets/neuomorphic.dart';

class UrgentWizardScreen extends StatefulWidget {
  const UrgentWizardScreen({super.key});

  @override
  State<UrgentWizardScreen> createState() => _UrgentWizardScreenState();
}

class _UrgentWizardScreenState extends State<UrgentWizardScreen> {
  int _step = 0; // 0=symptoms, 1=severity, 2=pre-check, 3=submitting
  final Set<String> _selectedSymptoms = {};
  Severity _severity = Severity.medium;
  final _descCtrl = TextEditingController();
  final Map<String, bool> _checklist = {
    'Engine is off and keys removed': false,
    'Vehicle is parked on a flat surface': false,
    'No visible fluid leaks underneath': false,
    'Battery has charge / lights work': false,
  };
  bool _submitting = false;
  AiDiagnosticResponse? _result;
  DiagnosticSession? _session;
  bool _hasPromptedReview = false;

  bool get _canProceed => switch (_step) {
        0 => _selectedSymptoms.isNotEmpty,
        1 => true,
        2 => true,
        _ => false,
      };

  void _next() {
    if (!_canProceed) return;
    HapticFeedback.selectionClick();
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    HapticFeedback.lightImpact();
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _submit() async {
    final vehicle = VehicleService.instance.selected;
    if (vehicle == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _step = 3;
      _submitting = true;
    });
    HapticFeedback.heavyImpact();

    try {
      final response = await AiService.instance.analyzeSymptoms(
        vehicle: vehicle,
        symptoms: _selectedSymptoms.toList(),
        severity: _severity,
        description:
            _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      );

      final session = DiagnosticSession(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
        vehicleId: vehicle.id,
        type: DiagnosticType.urgent,
        symptoms: _selectedSymptoms.toList(),
        severity: _severity,
        description:
            _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
        aiResponse: response.summary,
        aiResponseJson: response.toJson(),
        healthScore: response.healthScore,
        vehicleName: vehicle.displayName,
      );

      await DiagnosticService.instance.save(session);
      if (!response.isFallback) {
        await QuotaService.instance.refreshStatus();
      }

      if (!mounted) return;
      setState(() {
        _result = response;
        _session = session;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _step = 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Analysis failed: ${e.toString().split(":").last.trim()}'),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_submitting) {
          Navigator.of(context).pop();
          return;
        }
        if (_result != null) {
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
                // ── top bar ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                  child: Row(
                    children: [
                      if (!_submitting && _result == null)
                        FixEaseStepBackButton(onPressed: _back),
                      if (_result != null)
                        FixEaseStepBackButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      const Spacer(),
                      if (!_submitting && _result == null)
                        Text('Step ${_step + 1} of 3', style: tt.bodySmall),
                    ],
                  ),
                ),

                if (!_submitting && _result == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (_step + 1) / 3,
                        minHeight: 4,
                        backgroundColor: AppColors.surfaceHighlight,
                        color: AppColors.accent,
                      ),
                    ),
                  ),

                Expanded(
                  child: _submitting
                      ? _buildSubmitting(tt)
                      : _result != null
                          ? _buildResultView(tt)
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: switch (_step) {
                                  0 => _buildSymptomStep(tt),
                                  1 => _buildSeverityStep(tt),
                                  _ => _buildChecklistStep(tt),
                                },
                              ),
                            ),
                ),

                if (!_submitting && _result == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: NeuPrimaryButton(
                      label: _step == 2 ? 'Submit Diagnosis' : 'Continue',
                      icon: _step == 2 ? Icons.send_rounded : null,
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

  // ── Step 0: Symptom selection ─────────────────────────────────────────────

  Widget _buildSymptomStep(TextTheme tt) {
    return Column(
      key: const ValueKey('symptoms'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.accent, size: 24),
            const SizedBox(width: 8),
            Text('Urgent Diagnosis', style: tt.headlineMedium),
          ],
        ),
        const SizedBox(height: 6),
        Text('Select all symptoms you\'re experiencing', style: tt.bodyMedium),
        const SizedBox(height: 8),
        NeuTextField(
          hint: 'Describe anything else…',
          icon: Icons.edit_note_rounded,
          controller: _descCtrl,
        ),
        const SizedBox(height: 18),
        for (final cat in kSymptomCategories) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              '${cat.icon}  ${cat.label}',
              style: tt.titleMedium,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: cat.symptoms.map((s) {
              final sel = _selectedSymptoms.contains(s);
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    sel
                        ? _selectedSymptoms.remove(s)
                        : _selectedSymptoms.add(s);
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: sel
                        ? AppColors.accent.withValues(alpha: 0.18)
                        : AppColors.surface,
                    border: Border.all(
                      color: sel
                          ? AppColors.accent.withValues(alpha: 0.5)
                          : const Color(0x0CFFFFFF),
                      width: sel ? 1 : 0.5,
                    ),
                  ),
                  child: Text(
                    s,
                    style: tt.bodySmall?.copyWith(
                      color: sel ? AppColors.accent : AppColors.textPrimary,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  // ── Step 1: Severity ──────────────────────────────────────────────────────

  Widget _buildSeverityStep(TextTheme tt) {
    return Column(
      key: const ValueKey('severity'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How urgent is it?', style: tt.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'This helps us prioritize the diagnosis',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: 24),
        for (final s in Severity.values) ...[
          _SeverityTile(
            severity: s,
            selected: _severity == s,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _severity = s);
            },
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── Step 2: Pre-check ─────────────────────────────────────────────────────

  Widget _buildChecklistStep(TextTheme tt) {
    return Column(
      key: const ValueKey('checklist'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Pre-Diagnosis Check', style: tt.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'Ensure these conditions before we proceed',
          style: tt.bodyMedium,
        ),
        const SizedBox(height: 20),
        for (final entry in _checklist.entries) ...[
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _checklist[entry.key] = !entry.value);
            },
            child: NeuPane(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      color: entry.value
                          ? AppColors.accent
                          : AppColors.surfaceHighlight,
                      border: Border.all(
                        color: entry.value
                            ? AppColors.accent
                            : const Color(0x22FFFFFF),
                      ),
                    ),
                    child: entry.value
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(entry.key,
                        style: tt.bodyMedium?.copyWith(
                          color: entry.value
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        )),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),

        // summary
        NeuPane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Summary', style: tt.titleMedium),
              const SizedBox(height: 8),
              Text(
                '${_selectedSymptoms.length} symptom(s) selected · '
                '${_severity.name.toUpperCase()} severity',
                style: tt.bodyMedium,
              ),
              if (_descCtrl.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '"${_descCtrl.text.trim()}"',
                  style: tt.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Submitting spinner ──────────────────────────────────────────────────

  Widget _buildSubmitting(TextTheme tt) {
    return const AiLoadingView(
      title: 'Building Your Diagnosis',
      subtitle:
          'FixEase is reviewing the symptom pattern, urgency, and likely system overlap before it finalizes the report.',
      stages: [
        'Reviewing symptom combinations',
        'Checking the most likely affected systems',
        'Writing your plain-English summary',
        'Preparing the full report and next steps',
      ],
      tips: [
        'Specific symptoms together usually narrow the problem faster than one symptom alone.',
        'A flashing warning light is usually more urgent than a steady one.',
        'Tell the mechanic when the issue happens most: cold start, idle, turning, braking, or highway speed.',
        'Strange noises plus drivability issues often point to the same root system.',
      ],
    );
  }

  // ── Result view ───────────────────────────────────────────────────────

  Widget _buildResultView(TextTheme tt) {
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
              Text('Diagnosis Complete', style: tt.headlineMedium),
            ],
          ),
          const SizedBox(height: 8),

          // symptom chips
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedSymptoms.map((s) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: AppColors.accent.withValues(alpha: 0.12),
                ),
                child: Text(s,
                    style: tt.bodySmall?.copyWith(color: AppColors.accent)),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

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

// ── Severity tile ───────────────────────────────────────────────────────────

class _SeverityTile extends StatelessWidget {
  const _SeverityTile({
    required this.severity,
    required this.selected,
    required this.onTap,
  });
  final Severity severity;
  final bool selected;
  final VoidCallback onTap;

  static const _icons = {
    Severity.low: Icons.sentiment_satisfied_alt_rounded,
    Severity.medium: Icons.sentiment_neutral_rounded,
    Severity.high: Icons.sentiment_dissatisfied_rounded,
    Severity.critical: Icons.emergency_rounded,
  };

  static const _descriptions = {
    Severity.low: 'Car runs fine but something feels off',
    Severity.medium: 'Noticeable issue — driveable but needs attention',
    Severity.high: 'Serious problem — unsafe to drive far',
    Severity.critical: 'Car won\'t start or is dangerous to operate',
  };

  static const _colors = {
    Severity.low: Color(0xFF4CAF50),
    Severity.medium: Color(0xFFFFC107),
    Severity.high: Color(0xFFFF9800),
    Severity.critical: Color(0xFFFF5252),
  };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final c = _colors[severity]!;

    return GestureDetector(
      onTap: onTap,
      child: NeuPane(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? c.withValues(alpha: 0.2)
                    : AppColors.surfaceHighlight,
              ),
              child: Icon(_icons[severity], color: c, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    severity.name[0].toUpperCase() + severity.name.substring(1),
                    style: tt.titleMedium?.copyWith(
                      color: selected ? c : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(_descriptions[severity]!, style: tt.bodySmall),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle_rounded, color: c, size: 22),
          ],
        ),
      ),
    );
  }
}
