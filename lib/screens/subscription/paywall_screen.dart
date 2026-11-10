import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../services/review_prompt_service.dart';
import '../../services/subscription_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/neuomorphic.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, this.requiredFeature});

  final String? requiredFeature;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  SubscriptionProductType _selected = SubscriptionProductType.proDriver;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: SubscriptionService.instance,
            builder: (context, _) {
              final service = SubscriptionService.instance;
              final products = service.paywallProducts;
              final emergency = products.firstWhere(
                (product) =>
                    product.type == SubscriptionProductType.emergencyPass,
              );
              final pro = products.firstWhere(
                (product) => product.type == SubscriptionProductType.proDriver,
              );
              final selectedProduct = products.firstWhere(
                (product) => product.type == _selected,
                orElse: () => pro,
              );

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                    child: Row(
                      children: [
                        FixEaseStepBackButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.accent.withValues(alpha: 0.15),
                          ),
                          child: Text(
                            service.statusLabel,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PaywallHero(
                            requiredFeature: widget.requiredFeature,
                          ),
                          if (AppConfig.isDemoMode) ...[
                            const SizedBox(height: 18),
                            _DemoModeCard(
                              state: service.demoState,
                              onChanged: service.setDemoState,
                            ),
                          ],
                          const SizedBox(height: 22),
                          Text('Choose your access', style: tt.titleLarge),
                          if (service.lastSyncErrorMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(service.lastSyncErrorMessage!,
                                style: tt.bodyMedium),
                          ],
                          const SizedBox(height: 10),
                          _PlanCard(
                            product: emergency,
                            selected: _selected == emergency.type,
                            currentTier: service.tier,
                            onTap: () => setState(
                              () => _selected =
                                  SubscriptionProductType.emergencyPass,
                            ),
                          ),
                          const SizedBox(height: 14),
                          _PlanCard(
                            product: pro,
                            selected: _selected == pro.type,
                            currentTier: service.tier,
                            onTap: () => setState(
                              () =>
                                  _selected = SubscriptionProductType.proDriver,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _ComparisonTable(),
                          const SizedBox(height: 24),
                          if (service.isPurchasing || service.isRestoring)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppColors.accent,
                                ),
                              ),
                            )
                          else ...[
                            NeuPrimaryButton(
                              label: _ctaLabel(service, selectedProduct),
                              icon: Icons.lock_open_rounded,
                              onPressed: selectedProduct.available
                                  ? () {
                                      _handlePurchase(selectedProduct.type);
                                    }
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            NeuSecondaryButton(
                              label: 'Restore Purchases',
                              icon: Icons.restore_rounded,
                              onPressed: () {
                                _handleRestore();
                              },
                            ),
                          ],
                          const SizedBox(height: 18),
                          Center(
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                _FooterLink(
                                  label: 'Terms of Use',
                                  onTap: () => _openUrl(AppConfig.termsUrl),
                                ),
                                _FooterDot(),
                                _FooterLink(
                                  label: 'Privacy Policy',
                                  onTap: () => _openUrl(AppConfig.privacyUrl),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _ctaLabel(
    SubscriptionService service,
    SubscriptionProduct product,
  ) {
    final currentTier = service.tier;
    final currentMatches = product.type == SubscriptionProductType.proDriver &&
            currentTier == SubscriptionTier.pro ||
        product.type == SubscriptionProductType.emergencyPass &&
            currentTier == SubscriptionTier.emergencyPass;
    if (currentMatches) return 'This is your current access';
    return product.type == SubscriptionProductType.emergencyPass
        ? 'Unlock Emergency Pass'
        : 'Start Pro Driver';
  }

  Future<void> _handlePurchase(SubscriptionProductType type) async {
    final success = await SubscriptionService.instance.purchaseProduct(type);
    if (!mounted) return;
    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(SubscriptionService.instance.lastSyncErrorMessage ??
              'Purchase could not be completed. No new access was granted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await ReviewPromptService.instance.maybePrompt(
      context,
      trigger: ReviewPromptTrigger.purchaseSuccess,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _handleRestore() async {
    final restored = await SubscriptionService.instance.restorePurchases();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(restored
            ? 'Purchases restored'
            : SubscriptionService.instance.lastSyncErrorMessage ??
                'No active paid purchases were found.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  }
}

class _PaywallHero extends StatelessWidget {
  const _PaywallHero({this.requiredFeature});

  final String? requiredFeature;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accent,
                  AppColors.accent.withValues(alpha: 0.6),
                ],
              ),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              size: 32,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text('Unlock The Financial Shield', style: tt.headlineMedium),
          const SizedBox(height: 8),
          Text(
            requiredFeature != null
                ? '$requiredFeature is part of FixEase premium access.'
                : 'Turn one panic moment into a repair plan you can use with confidence.',
            style: tt.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _DemoModeCard extends StatelessWidget {
  const _DemoModeCard({
    required this.state,
    required this.onChanged,
  });

  final DemoSubscriptionState state;
  final Future<void> Function(DemoSubscriptionState state) onChanged;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Demo Toggle', style: tt.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Switch mock entitlement states instantly to test every gate in the app.',
            style: tt.bodySmall,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in DemoSubscriptionState.values)
                ChoiceChip(
                  label: Text(_label(option)),
                  selected: option == state,
                  onSelected: (_) {
                    onChanged(option);
                  },
                  selectedColor: AppColors.accent.withValues(alpha: 0.16),
                  backgroundColor:
                      AppColors.surfaceHighlight.withValues(alpha: 0.35),
                  labelStyle: tt.bodySmall?.copyWith(
                    color: option == state
                        ? AppColors.accent
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _label(DemoSubscriptionState state) => switch (state) {
        DemoSubscriptionState.mockFree => 'Mock_Free',
        DemoSubscriptionState.mockPass => 'Mock_Pass',
        DemoSubscriptionState.mockPro => 'Mock_Pro',
      };
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.product,
    required this.selected,
    required this.currentTier,
    required this.onTap,
  });

  final SubscriptionProduct product;
  final bool selected;
  final SubscriptionTier currentTier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isCurrent = product.type == SubscriptionProductType.proDriver &&
            currentTier == SubscriptionTier.pro ||
        product.type == SubscriptionProductType.emergencyPass &&
            currentTier == SubscriptionTier.emergencyPass;

    final borderColor = product.recommended
        ? AppColors.accent
        : selected
            ? AppColors.accent.withValues(alpha: 0.5)
            : const Color(0x12FFFFFF);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.08)
              : AppColors.surface,
          border: Border.all(
            color: borderColor,
            width: product.recommended ? 1.8 : (selected ? 1.2 : 0.7),
          ),
          boxShadow: product.recommended
              ? [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    blurRadius: 20,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.title, style: tt.titleLarge),
                      const SizedBox(height: 4),
                      Text(product.subtitle, style: tt.bodySmall),
                    ],
                  ),
                ),
                if (product.badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: product.recommended
                          ? AppColors.accent.withValues(alpha: 0.2)
                          : const Color(0xFFFFC107).withValues(alpha: 0.18),
                    ),
                    child: Text(
                      product.badge!,
                      style: tt.bodySmall?.copyWith(
                        color: product.recommended
                            ? AppColors.accent
                            : const Color(0xFFFFC107),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  product.priceString,
                  style: tt.headlineMedium?.copyWith(color: AppColors.accent),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(product.billingLabel, style: tt.bodySmall),
                ),
                const Spacer(),
                if (isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.16),
                    ),
                    child: Text(
                      'CURRENT',
                      style: tt.bodySmall?.copyWith(
                        color: const Color(0xFF4CAF50),
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Column(
              children: product.features
                  .map(
                    (feature) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _FeaturePill(
                        text: feature,
                        highlight: product.recommended || selected,
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (!product.available) ...[
              const SizedBox(height: 12),
              Text(
                'Store product unavailable in this build.',
                style: tt.bodySmall?.copyWith(color: const Color(0xFFFF9800)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.text,
    this.highlight = false,
  });

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: highlight
            ? AppColors.accent.withValues(alpha: 0.12)
            : AppColors.surfaceHighlight.withValues(alpha: 0.48),
        border: Border.all(
          color: highlight
              ? AppColors.accent.withValues(alpha: 0.24)
              : const Color(0x14FFFFFF),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: highlight ? AppColors.accent : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: tt.bodyMedium?.copyWith(
                fontSize: 12.5,
                height: 1.3,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    const rows = <(String, String, String)>[
      ('Urgent & photo scans', '3 / month', 'Unlimited'),
      ('Invoice auditing', 'Locked', 'Included'),
      ('OBD Pro Diagnostic Suite', 'Locked', 'Included'),
      ('Tech PDF exports', 'First 2 monthly reports', 'Included'),
      ('Older diagnostic history', 'Newest 2 sessions', 'Included'),
      ('Live audio length', '3 minutes', '10 minutes'),
      ('Priority AI processing', 'Standard', 'Included'),
    ];

    return NeuPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Free vs Pro', style: tt.titleMedium),
          const SizedBox(height: 12),
          Column(
            children: [
              const Row(
                children: [
                  Expanded(flex: 6, child: SizedBox.shrink()),
                  Expanded(flex: 3, child: _HeaderCell('Free')),
                  Expanded(flex: 3, child: _HeaderCell('Pro')),
                ],
              ),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ComparisonRow(
                    label: row.$1,
                    freeValue: row.$2,
                    proValue: row.$3,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.freeValue,
    required this.proValue,
  });

  final String label;
  final String freeValue;
  final String proValue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceHighlight.withValues(alpha: 0.34),
        border: Border.all(
          color: const Color(0x14FFFFFF),
          width: 0.6,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 6,
            child: _LabelCell(label),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _ValueCell(freeValue),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _ValueCell(proValue, highlight: true),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

class _LabelCell extends StatelessWidget {
  const _LabelCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell(this.text, {this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: highlight ? AppColors.accent : Colors.white,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600,
              height: 1.2,
            ),
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textTertiary,
              decoration: TextDecoration.underline,
            ),
      ),
    );
  }
}

class _FooterDot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      '•',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textTertiary,
          ),
    );
  }
}
