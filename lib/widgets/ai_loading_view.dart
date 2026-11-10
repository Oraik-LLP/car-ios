import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AiLoadingView extends StatefulWidget {
  const AiLoadingView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.tips,
    required this.stages,
  });

  final String title;
  final String subtitle;
  final List<String> tips;
  final List<String> stages;

  @override
  State<AiLoadingView> createState() => _AiLoadingViewState();
}

class _AiLoadingViewState extends State<AiLoadingView> {
  Timer? _tipTimer;
  Timer? _stageTimer;
  int _tipIndex = 0;
  int _stageIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.tips.length > 1) {
      _tipTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        setState(() {
          _tipIndex = (_tipIndex + 1) % widget.tips.length;
        });
      });
    }
    if (widget.stages.length > 1) {
      _stageTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (!mounted) return;
        setState(() {
          if (_stageIndex < widget.stages.length - 1) {
            _stageIndex += 1;
          } else {
            timer.cancel();
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _stageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final currentTip =
        widget.tips.isEmpty ? '' : widget.tips[_tipIndex % widget.tips.length];
    final currentStage = widget.stages.isEmpty
        ? 'Building your report'
        : widget.stages[_stageIndex % widget.stages.length];
    final stageDotCount = widget.stages.isEmpty
        ? 1
        : widget.stages.length > 4
            ? 4
            : widget.stages.length;
    final activeStage = widget.stages.isEmpty ? 0 : _stageIndex % stageDotCount;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 110,
              height: 110,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.accent,
                      backgroundColor: AppColors.surfaceHighlight,
                    ),
                  ),
                  Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(color: const Color(0x0CFFFFFF)),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.accent,
                      size: 26,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            Text(widget.title, style: tt.headlineMedium),
            const SizedBox(height: 10),
            Text(
              widget.subtitle,
              style: tt.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                currentStage,
                key: ValueKey(currentStage),
                style: tt.titleMedium?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(stageDotCount, (index) {
                final active = index == activeStage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: active ? 24 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: active
                        ? AppColors.accent
                        : AppColors.surfaceHighlight,
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Text(
                currentTip.isEmpty
                    ? 'Cross-checking the result for clear next steps.'
                    : currentTip,
                key: ValueKey(currentTip.isEmpty ? 'default-tip' : currentTip),
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
