import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppMarkdownText extends StatelessWidget {
  const AppMarkdownText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.color,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final baseStyle = (style ?? Theme.of(context).textTheme.bodyMedium)?.copyWith(
          color: color ?? style?.color,
          height: 1.45,
        );
    final trimmed = data.trim();
    if (trimmed.isEmpty || baseStyle == null) {
      return const SizedBox.shrink();
    }

    final blocks = <Widget>[];
    final lines = trimmed.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      final bulletMatch = RegExp(r'^[-*]\s+').firstMatch(line.trimLeft());
      final orderedMatch = RegExp(r'^(\d+)\.\s+').firstMatch(line.trimLeft());
      if (bulletMatch != null) {
        final content = line.trimLeft().substring(bulletMatch.end);
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: baseStyle,
                      children: _parseInline(content, baseStyle),
                    ),
                    softWrap: true,
                    textAlign: textAlign,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      if (orderedMatch != null) {
        final content = line.trimLeft().substring(orderedMatch.end);
        blocks.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${orderedMatch.group(1)}.',
                  style: baseStyle.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: baseStyle,
                      children: _parseInline(content, baseStyle),
                    ),
                    softWrap: true,
                    textAlign: textAlign,
                  ),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      final isHeading = line.trimLeft().startsWith('#');
      final headingText = isHeading
          ? line.trimLeft().replaceFirst(RegExp(r'^#+\s*'), '')
          : line;
      final lineStyle = isHeading
          ? baseStyle.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: (baseStyle.fontSize ?? 14) + 1,
            )
          : baseStyle;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(
              style: lineStyle,
              children: _parseInline(headingText, lineStyle),
            ),
            softWrap: true,
            textAlign: textAlign,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  List<InlineSpan> _parseInline(String source, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|__[^_]+__|`[^`]+`|\*[^*]+\*|_[^_]+_)');
    int cursor = 0;

    for (final match in pattern.allMatches(source)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, match.start)));
      }

      final token = match.group(0)!;
      if ((token.startsWith('**') && token.endsWith('**')) ||
          (token.startsWith('__') && token.endsWith('__'))) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: baseStyle.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      } else if ((token.startsWith('*') && token.endsWith('*')) ||
          (token.startsWith('_') && token.endsWith('_'))) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: baseStyle.copyWith(fontStyle: FontStyle.italic),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: baseStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: AppColors.surfaceHighlight.withValues(alpha: 0.5),
            ),
          ),
        );
      }

      cursor = match.end;
    }

    if (cursor < source.length) {
      spans.add(TextSpan(text: source.substring(cursor)));
    }

    return spans;
  }
}
