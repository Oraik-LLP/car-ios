import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';
import 'local_store_service.dart';

enum ReviewPromptTrigger { diagnosisSuccess, purchaseSuccess }

class ReviewPromptService {
  ReviewPromptService._();
  static final ReviewPromptService instance = ReviewPromptService._();

  static const _storageKey = 'review_prompt_state.v1';
  static const _cooldown = Duration(hours: 18);

  Future<void> maybePrompt(
    BuildContext context, {
    required ReviewPromptTrigger trigger,
  }) async {
    final now = DateTime.now();
    final state = LocalStoreService.readJsonMap(_storageKey) ?? <String, dynamic>{};
    final alreadyCompleted = state['completed'] == true;
    if (alreadyCompleted) return;

    if (trigger == ReviewPromptTrigger.diagnosisSuccess) {
      final int currentCount = (state['success_count'] as num?)?.toInt() ?? 0;
      final int newCount = currentCount + 1;
      state['success_count'] = newCount;
      await LocalStoreService.writeJsonMap(_storageKey, state);

      // Don't show the prompt until the second successful diagnosis
      if (newCount < 2) {
        return;
      }
    }

    final lastShown =
        DateTime.tryParse(state['last_shown_at'] as String? ?? '');
    if (lastShown != null && now.difference(lastShown) < _cooldown) {
      return;
    }
    if (!context.mounted) return;

    state['last_shown_at'] = now.toIso8601String();
    state['last_trigger'] = trigger.name;
    await LocalStoreService.writeJsonMap(_storageKey, state);

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final tt = Theme.of(sheetContext).textTheme;
        final bool interestShown = state['interest_shown'] == true;
        
        final String title = interestShown 
            ? 'Would you mind leaving a quick review?' 
            : 'Did FixEase save you money today?';
        final String subtitle = interestShown 
            ? 'A quick rating helps us improve the experience for stressed drivers.' 
            : 'We\'re glad we could help you figure out what\'s wrong.';

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Material(
              color: Theme.of(sheetContext).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tt.titleLarge),
                    const SizedBox(height: 10),
                    Text(subtitle, style: tt.bodyMedium),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _PromptButton(
                            icon: Icons.thumb_up_alt_rounded,
                            label: 'Yes',
                            onTap: () async {
                              if (!interestShown) {
                                state['interest_shown'] = true;
                                await LocalStoreService.writeJsonMap(_storageKey, state);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                              } else {
                                state['completed'] = true;
                                state['completed_at'] = DateTime.now().toIso8601String();
                                await LocalStoreService.writeJsonMap(_storageKey, state);
                                if (!sheetContext.mounted) return;
                                Navigator.of(sheetContext).pop();
                                final review = InAppReview.instance;
                                if (await review.isAvailable()) {
                                  await review.requestReview();
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PromptButton(
                            icon: Icons.thumb_down_alt_rounded,
                            label: 'Needs work',
                            onTap: () async {
                              state['completed'] = true;
                              state['completed_at'] = DateTime.now().toIso8601String();
                              await LocalStoreService.writeJsonMap(_storageKey, state);

                              if (!sheetContext.mounted) return;
                              Navigator.of(sheetContext).pop();
                              final uri = Uri(
                                scheme: 'mailto',
                                path: AppConfig.supportEmail,
                                queryParameters: const {
                                  'subject': 'Bug Report/Feedback',
                                },
                              );
                              await launchUrl(uri);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PromptButton extends StatelessWidget {
  const _PromptButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.45),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
