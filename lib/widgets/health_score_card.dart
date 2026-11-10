import 'package:flutter/material.dart';

import '../models/ai_response.dart';
import '../models/diagnostic.dart';
import '../services/conversation_service.dart';
import '../screens/conversations/conversation_chat_screen.dart';
import '../theme/app_theme.dart';
import 'app_markdown_text.dart';
import 'neuomorphic.dart';
import 'report_export_button.dart';

const kInvoiceAuditWarningText =
    'This audit highlights possible overcharges and upsells. It is not a legal or mechanical diagnosis. Always confirm major repairs with a qualified mechanic or a second opinion.';

/// Full diagnostic result card - health ring + sub-scores + recommendations.
class DiagnosticResultCard extends StatelessWidget {
  const DiagnosticResultCard({
    super.key,
    required this.response,
    this.session,
  });

  final AiDiagnosticResponse response;
  final DiagnosticSession? session;

  bool get _isInvoiceAudit => session?.type == DiagnosticType.invoiceAudit;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NeuPane(
          child: Column(
            children: [
              Row(
                children: [
                  NeuProgressRing(
                    progress: response.displayProgress,
                    size: 96,
                    label: response.displayScoreLabel,
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _isInvoiceAudit
                                    ? 'Bill Fairness'
                                    : 'Vehicle Health',
                                style: tt.titleLarge,
                              ),
                            ),
                            if (session != null)
                              ReportExportButton(
                                session: session!,
                                response: response,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _HealthBadge(
                          label: response.healthLabel,
                          color: response.statusColor,
                        ),
                        const SizedBox(height: 8),
                        if (_isInvoiceAudit &&
                            response.documentType != null &&
                            response.documentType!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Document: ${response.documentType}',
                              style: tt.bodySmall,
                            ),
                          ),
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_rounded,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Confidence: ${response.confidenceLabel}',
                              style: tt.bodySmall,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (response.urgencyNote != null) ...[
                const SizedBox(height: 14),
                _AlertBanner(
                  icon: Icons.priority_high_rounded,
                  backgroundColor: const Color(0x22FF5252),
                  borderColor: const Color(0x44FF5252),
                  iconColor: const Color(0xFFFF5252),
                  textColor: const Color(0xFFFF8A80),
                  text: response.urgencyNote!,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_isInvoiceAudit) ...[
          NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Audit Warning', style: tt.titleMedium),
                const SizedBox(height: 8),
                Text(kInvoiceAuditWarningText, style: tt.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        NeuPane(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isInvoiceAudit ? 'Audit Summary' : 'AI Summary',
                  style: tt.titleMedium),
              const SizedBox(height: 8),
              AppMarkdownText(response.summary, style: tt.bodyMedium),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (response.subScores.isNotEmpty) ...[
          NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isInvoiceAudit ? 'Fairness Breakdown' : 'Component Scores',
                  style: tt.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final entry in response.normalizedSubScores.entries) ...[
                  _SubScoreRow(
                    label: entry.key,
                    score: entry.value,
                    usesHundredPointScale: response.usesHundredPointScale,
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_isInvoiceAudit && response.topFlags.isNotEmpty) ...[
          _BulletSection(title: 'Top Flags', items: response.topFlags),
          const SizedBox(height: 14),
        ],
        if (_isInvoiceAudit && response.lineItemAudit.isNotEmpty) ...[
          NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Line Item Audit', style: tt.titleMedium),
                const SizedBox(height: 12),
                for (final item in response.lineItemAudit) ...[
                  _InvoiceLineItemRow(item: item),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_isInvoiceAudit && response.paddingPatternsDetected.isNotEmpty) ...[
          _BulletSection(
            title: 'Padding Patterns Detected',
            items: response.paddingPatternsDetected,
          ),
          const SizedBox(height: 14),
        ],
        if (!_isInvoiceAudit && response.possibleCauses.isNotEmpty) ...[
          _BulletSection(
            title: 'Possible Causes',
            items: response.possibleCauses,
            bulletColor: AppColors.accent,
          ),
          const SizedBox(height: 14),
        ],
        if (response.recommendations.isNotEmpty) ...[
          _NumberedSection(
            title: _isInvoiceAudit ? 'Next Steps' : 'Recommendations',
            items: response.recommendations,
          ),
          const SizedBox(height: 14),
        ],
        if (_isInvoiceAudit && response.questionsToAsk.isNotEmpty) ...[
          _BulletSection(
            title: 'Questions To Ask The Shop',
            items: response.questionsToAsk,
          ),
          const SizedBox(height: 14),
        ],
        if (_isInvoiceAudit &&
            response.negotiationScript != null &&
            response.negotiationScript!.trim().isNotEmpty) ...[
          NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Negotiation Script', style: tt.titleMedium),
                const SizedBox(height: 8),
                AppMarkdownText(
                  response.negotiationScript!,
                  style: tt.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (_isInvoiceAudit &&
            (response.partialAudit ||
                (response.limitations?.trim().isNotEmpty ?? false))) ...[
          _AlertBanner(
            icon: Icons.info_outline_rounded,
            backgroundColor: AppColors.accent.withValues(alpha: 0.08),
            borderColor: AppColors.accent.withValues(alpha: 0.2),
            iconColor: AppColors.accent,
            textColor: AppColors.textPrimary,
            text: response.limitations?.trim().isNotEmpty == true
                ? response.limitations!
                : 'This audit may be partial because the uploaded bill could not be read completely.',
          ),
          const SizedBox(height: 14),
        ],
        if (response.mechanicScript != null &&
            response.mechanicScript!.trim().isNotEmpty) ...[
          NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isInvoiceAudit
                      ? 'Show This To The Shop'
                      : 'Show This To The Mechanic',
                  style: tt.titleMedium,
                ),
                const SizedBox(height: 8),
                AppMarkdownText(
                  response.mechanicScript!,
                  style: tt.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class DiagnosticClarifyingQuestionPrompt extends StatelessWidget {
  const DiagnosticClarifyingQuestionPrompt({
    super.key,
    required this.response,
    required this.session,
  });

  final AiDiagnosticResponse response;
  final DiagnosticSession session;

  @override
  Widget build(BuildContext context) {
    final question = response.suggestedQuestion?.trim();
    if (question == null ||
        question.isEmpty ||
        question.toLowerCase() == 'none' ||
        question.toLowerCase() == 'null') {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: ConversationService.instance,
      builder: (context, _) {
        final thread =
            ConversationService.instance.threadForSession(session.id);
        final hasConversation = (thread?.messages.isNotEmpty ?? false);
        if (hasConversation) {
          return const SizedBox.shrink();
        }

        final tt = Theme.of(context).textTheme;
        return GestureDetector(
          onTap: () => openConversationChat(
            context,
            session: session,
            initialReplyQuestion: question,
          ),
          child: NeuPane(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Clarifying Question',
                        style: tt.titleMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(question, style: tt.bodyMedium),
                const SizedBox(height: 8),
                Text(
                  'Tap to answer in chat',
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.iconColor,
    required this.textColor,
    required this.text,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color iconColor;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: backgroundColor,
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: tt.bodySmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BulletSection extends StatelessWidget {
  const _BulletSection({
    required this.title,
    required this.items,
    this.bulletColor = AppColors.accent,
  });

  final String title;
  final List<String> items;
  final Color bulletColor;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleMedium),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: bulletColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppMarkdownText(item, style: tt.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberedSection extends StatelessWidget {
  const _NumberedSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleMedium),
          const SizedBox(height: 8),
          for (var index = 0; index < items.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.15),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppMarkdownText(items[index], style: tt.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InvoiceLineItemRow extends StatelessWidget {
  const _InvoiceLineItemRow({required this.item});

  final InvoiceAuditLineItem item;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.35),
        border: Border.all(
          color: const Color(0x12FFFFFF),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.item,
                  style: tt.titleSmall?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (item.charge.isNotEmpty)
                Text(item.charge, style: tt.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item.assessment,
            style: tt.bodySmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          AppMarkdownText(item.reason, style: tt.bodyMedium),
          const SizedBox(height: 6),
          Text('Confidence: ${item.confidence}', style: tt.bodySmall),
        ],
      ),
    );
  }
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.18),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SubScoreRow extends StatelessWidget {
  const _SubScoreRow({
    required this.label,
    required this.score,
    required this.usesHundredPointScale,
  });

  final String label;
  final double score;
  final bool usesHundredPointScale;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pct = usesHundredPointScale
        ? (score / 100).clamp(0.0, 1.0)
        : (score / 10).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: tt.bodySmall),
        ),
        Expanded(child: NeuSlider(value: pct)),
        const SizedBox(width: 8),
        SizedBox(
          width: usesHundredPointScale ? 38 : 30,
          child: Text(
            usesHundredPointScale
                ? score.round().toString()
                : score.toStringAsFixed(1),
            style: tt.bodySmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
