import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Palette derived from Tesla Cybertruck dark UI reference:
///   - Near-black base (#111114)
///   - Subtle lifted surfaces (#1B1B1F)
///   - Electric cyan accent on active controls only
///   - Thin/light secondary text, bold primaries
abstract final class AppColors {
  static const background = Color(0xFF111114);
  static const backgroundDeep = Color(0xFF0C0C0E);
  static const backgroundLift = Color(0xFF17171B);
  static const surface = Color(0xFF1B1B1F);
  static const surfaceHighlight = Color(0xFF242428);
  static const accent = Color(0xFF009DFF);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF787880);
  static const textTertiary = Color(0xFF505058);
  static const shadowDark = Color(0xFF050507);
  static const shadowLight = Color(0xFF222228);
}

TextTheme _fixEaseTextTheme() {
  final base = GoogleFonts.interTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  );

  return base.copyWith(
    displayLarge: GoogleFonts.inter(
      fontSize: 52,
      fontWeight: FontWeight.w300,
      letterSpacing: -1.5,
      height: 1.05,
      color: AppColors.textPrimary,
    ),
    headlineLarge: GoogleFonts.inter(
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
      color: AppColors.textPrimary,
    ),
    headlineMedium: GoogleFonts.inter(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.22,
      color: AppColors.textPrimary,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.3,
      color: AppColors.textPrimary,
    ),
    titleMedium: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.15,
      height: 1.35,
      color: AppColors.textPrimary,
    ),
    bodyLarge: GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.08,
      height: 1.5,
      color: AppColors.textSecondary,
    ),
    bodyMedium: GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      height: 1.45,
      color: AppColors.textSecondary,
    ),
    bodySmall: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      letterSpacing: 0.05,
      height: 1.4,
      color: AppColors.textTertiary,
    ),
    labelLarge: GoogleFonts.inter(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
      height: 1.2,
      color: AppColors.textPrimary,
    ),
    labelSmall: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      height: 1.2,
      color: AppColors.textSecondary,
    ),
  );
}

ThemeData buildFixEaseTheme() {
  final textTheme = _fixEaseTextTheme();

  return ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: Colors.transparent,
    textTheme: textTheme,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.textPrimary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      secondary: AppColors.accent,
      onSecondary: AppColors.textPrimary,
    ),
    iconTheme: const IconThemeData(
      color: AppColors.textSecondary,
      size: 20,
    ),
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (BuildContext context) => const Icon(
        Icons.arrow_back_ios_new_rounded,
        size: 18,
        color: AppColors.textPrimary,
      ),
      closeButtonIconBuilder: (BuildContext context) => const Icon(
        Icons.close_rounded,
        size: 20,
        color: AppColors.textPrimary,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        iconSize: 20,
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      centerTitle: true,
      toolbarHeight: 48,
      titleSpacing: 0,
      titleTextStyle: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 20,
      ),
      actionsIconTheme: const IconThemeData(
        color: AppColors.textSecondary,
        size: 20,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: AppColors.backgroundDeep,
      indicatorColor: AppColors.accent.withValues(alpha: 0.15),
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return GoogleFonts.inter(
          fontSize: 10,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          letterSpacing: 0.25,
          height: 1.1,
          color: selected ? AppColors.accent : AppColors.textTertiary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.accent : AppColors.textTertiary,
          size: 22,
        );
      }),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

/// Near-black layered background matching reference automotive UI.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.backgroundLift,
            AppColors.background,
            AppColors.backgroundDeep,
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// Styled back control for wizard steps.
class FixEaseStepBackButton extends StatelessWidget {
  const FixEaseStepBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              'Back',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.1,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
