import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'config/app_config.dart';
import 'models/ai_response.dart';
import 'models/diagnostic.dart';
import 'models/vehicle.dart';
import 'screens/conversations/conversation_chat_screen.dart';
import 'screens/diagnose/live_diagnose_screen.dart';
import 'screens/diagnose/obd_pro_dashboard_screen.dart';
import 'screens/diagnose/photo_diagnose_screen.dart';
import 'screens/diagnose/urgent_wizard_screen.dart';
import 'screens/garage/garage_tab_body.dart';
import 'screens/reports/diagnostic_history_screen.dart';
import 'screens/reports/report_detail_screen.dart';
import 'screens/subscription/paywall_screen.dart';
import 'screens/vehicle/add_vehicle_screen.dart';
import 'screens/vehicle/my_vehicles_screen.dart';
import 'services/car_image_service.dart';
import 'services/conversation_service.dart';
import 'services/diagnostic_service.dart';
import 'services/garage_service.dart';
import 'services/local_store_service.dart';
import 'services/obd_pro_service.dart';
import 'services/quota_service.dart';
import 'services/reminder_scheduler_service.dart';
import 'services/subscription_service.dart';
import 'services/vehicle_service.dart';
import 'theme/app_theme.dart';
import 'widgets/neuomorphic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStoreService.init();
  try {
    await VehicleService.instance.load();
  } catch (_) {}
  try {
    await DiagnosticService.instance.load();
  } catch (_) {}
  try {
    await ConversationService.instance.load();
  } catch (_) {}
  try {
    await GarageService.instance.load();
  } catch (_) {}
  try {
    await SubscriptionService.instance.restore();
  } catch (_) {}
  try {
    await ObdProService.instance.load();
  } catch (_) {}
  try {
    unawaited(QuotaService.instance.refreshStatus());
  } catch (_) {}
  try {
    await ReminderSchedulerService.instance.initialize(
      requestPermissions: false,
    );
    await ReminderSchedulerService.instance.syncAllProfiles();
  } catch (_) {}
  runApp(const FixEaseApp());
}

class FixEaseApp extends StatelessWidget {
  const FixEaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FixEase',
      theme: buildFixEaseTheme(),
      home: const SplashScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Splash
// ═══════════════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _logoAsset = AssetImage('assets/logo/fixease_logo.png');
  late final AnimationController _anim;
  late final Animation<double> _fadeIn;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeIn = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmUpAssets();
      _anim.forward();
    });
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, __, ___) => const AppShell(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    });
  }

  Future<void> _warmUpAssets() async {
    if (!mounted) return;
    try {
      await precacheImage(_logoAsset, context);
    } catch (_) {}
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: Center(
          child: FadeTransition(
            opacity: _fadeIn,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // logo — no circle container, blends into bg
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Image(
                      image: _logoAsset,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.build_rounded,
                        size: 64,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('FixEase',
                      style: Theme.of(context).textTheme.displayLarge),
                  const SizedBox(height: 10),
                  Text('AI Car Diagnostics',
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Auth gate — decides whether to show auth or main shell
// ═══════════════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════════════
// App Shell — bottom nav + drawer
// ═══════════════════════════════════════════════════════════════════════════

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  int _index = 0;

  void switchTab(int index) {
    setState(() => _index = index);
    _refreshFreeCredits();
  }

  static const List<String> _titles = [
    'FixEase',
    'Diagnose',
    'Garage',
    'Profile',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _refreshFreeCredits();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  late final WidgetsBindingObserver _lifecycleObserver =
      _AppShellLifecycleObserver(onResume: _refreshFreeCredits);

  Future<void> _refreshFreeCredits() async {
    try {
      await SubscriptionService.instance.refreshMonthlyCreditsForDisplay();
    } catch (_) {}
    try {
      await QuotaService.instance.refreshStatus();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _index == 0) return;
        switchTab(0);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(_titles[_index]),
          actions: [
            if (_index != 3)
              IconButton(
                icon: const Icon(Icons.person_outline_rounded),
                tooltip: 'Profile',
                onPressed: () {
                  HapticFeedback.selectionClick();
                  switchTab(3);
                },
              ),
          ],
        ),
        body: AppBackground(
          child: IndexedStack(
            index: _index,
            children: const [
              HomeTabBody(),
              DiagnoseTabBody(),
              GarageTabBody(),
              ProfileTabBody(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) {
              HapticFeedback.selectionClick();
              switchTab(value);
            },
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(
                  icon: Icon(Icons.support_rounded), label: 'Diagnose'),
              NavigationDestination(
                  icon: Icon(Icons.garage_rounded), label: 'Garage'),
              NavigationDestination(
                  icon: Icon(Icons.person_rounded), label: 'Profile'),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Home Tab
// ═══════════════════════════════════════════════════════════════════════════

class _AppShellLifecycleObserver with WidgetsBindingObserver {
  _AppShellLifecycleObserver({required this.onResume});

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

class HomeTabBody extends StatefulWidget {
  const HomeTabBody({super.key});

  @override
  State<HomeTabBody> createState() => _HomeTabBodyState();
}

class _HomeTabBodyState extends State<HomeTabBody> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: VehicleService.instance,
      builder: (context, _) {
        final vehicle = VehicleService.instance.selected;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── vehicle hero card ──
              GestureDetector(
                onTap: () => vehicle != null
                    ? _openMyVehicles(context)
                    : _openAddVehicle(context),
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: AppColors.surface,
                    border: Border.all(
                      color: const Color(0x0CFFFFFF),
                      width: 0.5,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.surface,
                        AppColors.surfaceHighlight.withValues(alpha: 0.6),
                        AppColors.surface,
                      ],
                    ),
                  ),
                  child: vehicle != null
                      ? _VehicleHero(vehicle: vehicle)
                      : _EmptyHero(onAdd: () => _openAddVehicle(context)),
                ),
              ),
              const SizedBox(height: 22),

              // quick actions
              Row(
                children: [
                  NeuIconButton(
                    icon: Icons.directions_car_rounded,
                    selected: true,
                    onPressed: () => _openMyVehicles(context),
                  ),
                  const SizedBox(width: 12),
                  NeuIconButton(
                    icon: Icons.history_rounded,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DiagnosticHistoryScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  NeuIconButton(
                    icon: Icons.notifications_rounded,
                    onPressed: () {
                      final shell =
                          context.findAncestorStateOfType<AppShellState>();
                      shell?.switchTab(2);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // diagnosis buttons
              Row(
                children: [
                  Text('Start Diagnostic', style: tt.headlineMedium),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: Listenable.merge([
                      SubscriptionService.instance,
                      QuotaService.instance,
                    ]),
                    builder: (_, __) {
                      final sub = SubscriptionService.instance;
                      final badgeLabel =
                          QuotaService.instance.diagnosticsBadgeLabel;
                      if (sub.isUnlimited || badgeLabel == null) {
                        return const SizedBox.shrink();
                      }
                      return GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => const PaywallScreen()),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: AppColors.accent.withValues(alpha: 0.12),
                          ),
                          child: Text(
                            badgeLabel,
                            style: tt.bodySmall?.copyWith(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const _FreeQuotaHelperText(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: NeuPrimaryButton(
                      expanded: true,
                      label: 'Urgent',
                      icon: Icons.warning_amber_rounded,
                      onPressed: () => _startDiagnosis(
                        context,
                        vehicle,
                        const UrgentWizardScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NeuSecondaryButton(
                      expanded: true,
                      label: 'Photo',
                      icon: Icons.camera_alt_outlined,
                      onPressed: () => _startDiagnosis(
                        context,
                        vehicle,
                        const PhotoDiagnoseScreen(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  final shell =
                      context.findAncestorStateOfType<AppShellState>();
                  shell?.switchTab(2);
                },
                child: NeuPane(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.garage_rounded,
                          size: 20,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Garage', style: tt.titleMedium),
                            const SizedBox(height: 2),
                            Text(
                              'Track upcoming oil, tire, and registration reminders offline.',
                              style: tt.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // vehicle health — live from latest diagnostic
              ListenableBuilder(
                listenable: DiagnosticService.instance,
                builder: (context, _) {
                  final sessions = vehicle != null
                      ? DiagnosticService.instance
                          .sessionsForVehicle(vehicle.id)
                          .where((session) =>
                              session.type != DiagnosticType.invoiceAudit &&
                              session.type != DiagnosticType.live)
                          .toList()
                      : <DiagnosticSession>[];
                  final latest = sessions.isNotEmpty ? sessions.first : null;
                  final hasAi = latest?.aiResponseJson != null;
                  final resp = hasAi
                      ? AiDiagnosticResponse.fromJson(latest!.aiResponseJson!)
                      : null;
                  final hasRespScore = resp?.hasDisplayableScore ?? false;
                  final scoreLabel = hasRespScore
                      ? resp!.displayScoreLabel
                      : resp == null
                          ? (latest?.healthScore?.toStringAsFixed(1) ?? '—')
                          : '—';
                  final scorePct = hasRespScore
                      ? resp!.displayProgress
                      : (((latest?.healthScore ?? 0.0) / 10).clamp(0.0, 1.0));
                  final subScores =
                      resp?.normalizedSubScores ?? const <String, double>{};

                  return NeuPane(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vehicle Health', style: tt.titleLarge),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NeuProgressRing(
                              progress: scorePct,
                              size: 90,
                              label: scoreLabel,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: subScores.isNotEmpty
                                    ? subScores.entries
                                        .take(3)
                                        .map((e) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    e.key,
                                                    style: tt.bodySmall,
                                                  ),
                                                  const SizedBox(height: 3),
                                                  SizedBox(
                                                    width: double.infinity,
                                                    child: NeuSlider(
                                                      value:
                                                          resp?.usesHundredPointScale ==
                                                                  true
                                                              ? (e.value / 100)
                                                                  .clamp(
                                                                      0.0, 1.0)
                                                              : (e.value / 10)
                                                                  .clamp(
                                                                      0.0, 1.0),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList()
                                    : [
                                        Text('Engine', style: tt.bodyMedium),
                                        const SizedBox(height: 4),
                                        const SizedBox(
                                          width: double.infinity,
                                          child: NeuSlider(value: 0.0),
                                        ),
                                        const SizedBox(height: 10),
                                        Text('Brakes', style: tt.bodyMedium),
                                        const SizedBox(height: 4),
                                        const SizedBox(
                                          width: double.infinity,
                                          child: NeuSlider(value: 0.0),
                                        ),
                                      ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          latest != null
                              ? 'Last checked: ${latest.dateLabel}'
                              : vehicle != null
                                  ? 'Run a diagnostic to get your health score.'
                                  : 'Add a vehicle first to start tracking health.',
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // recent diagnostics
              ListenableBuilder(
                listenable: Listenable.merge([
                  DiagnosticService.instance,
                  ConversationService.instance,
                  SubscriptionService.instance,
                ]),
                builder: (context, _) {
                  final sessions = vehicle != null
                      ? DiagnosticService.instance
                          .sessionsForVehicle(vehicle.id)
                      : <DiagnosticSession>[];
                  return NeuPane(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recent Diagnostics', style: tt.titleLarge),
                        const SizedBox(height: 8),
                        if (sessions.isEmpty)
                          Text('No diagnostics yet.', style: tt.bodySmall)
                        else
                          ...sessions.take(3).map((s) {
                            final response = s.aiResponseJson != null
                                ? AiDiagnosticResponse.fromJson(
                                    s.aiResponseJson!,
                                  )
                                : null;
                            final rawScore = s.healthScore;
                            final hasDisplayableScore =
                                response?.hasDisplayableScore ?? false;
                            final scoreLabel = hasDisplayableScore
                                ? response!.displayScoreLabel
                                : response == null
                                    ? (rawScore != null
                                        ? (rawScore > 10
                                            ? rawScore.round().toString()
                                            : rawScore.toStringAsFixed(1))
                                        : null)
                                    : null;
                            final scoreSuffix = hasDisplayableScore
                                ? (response!.usesHundredPointScale ? '' : '/10')
                                : (rawScore != null && rawScore > 10
                                    ? ''
                                    : '/10');
                            final isLocked = DiagnosticService.instance
                                    .isOlderThanMostRecentSessions(
                                  s,
                                  allowedCount: 2,
                                ) &&
                                !checkAccess(
                                  FeatureType.olderHistoryAccess,
                                  session: s,
                                );
                            return Opacity(
                              opacity: isLocked ? 0.68 : 1,
                              child: GestureDetector(
                                onTap: () async {
                                  HapticFeedback.selectionClick();
                                  if (isLocked) {
                                    await ensureAccess(
                                      context,
                                      FeatureType.olderHistoryAccess,
                                      session: s,
                                      reason: 'Older Diagnostic History',
                                    );
                                    return;
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => s.type ==
                                              DiagnosticType.live
                                          ? ConversationChatScreen(session: s)
                                          : ReportDetailScreen(session: s),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        switch (s.type) {
                                          DiagnosticType.urgent =>
                                            Icons.warning_amber_rounded,
                                          DiagnosticType.photo =>
                                            Icons.camera_alt_outlined,
                                          DiagnosticType.invoiceAudit =>
                                            Icons.receipt_long_rounded,
                                          DiagnosticType.live =>
                                            Icons.videocam_rounded,
                                          DiagnosticType.obdIdle =>
                                            Icons.air_rounded,
                                          DiagnosticType.obdDrive =>
                                            Icons.route_rounded,
                                        },
                                        size: 16,
                                        color: AppColors.accent,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${switch (s.type) {
                                            DiagnosticType.urgent => "Urgent",
                                            DiagnosticType.photo => "Photo",
                                            DiagnosticType.invoiceAudit =>
                                              "Invoice Audit",
                                            DiagnosticType.live =>
                                              "Gemini Live",
                                            DiagnosticType.obdIdle =>
                                              "OBD Idle",
                                            DiagnosticType.obdDrive =>
                                              "OBD Drive",
                                          }} · ${s.dateLabel}',
                                          style: tt.bodyMedium,
                                        ),
                                      ),
                                      if (s.healthScore != null)
                                        Text(
                                          '$scoreLabel$scoreSuffix',
                                          style: tt.bodySmall?.copyWith(
                                            color: AppColors.accent,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        isLocked
                                            ? Icons.lock_rounded
                                            : Icons.chevron_right_rounded,
                                        size: 16,
                                        color: isLocked
                                            ? AppColors.accent
                                            : AppColors.textTertiary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startDiagnosis(
    BuildContext context,
    Vehicle? vehicle,
    Widget screen,
  ) async {
    if (vehicle == null) {
      _showAddFirst(context);
      return;
    }
    final allowed = await QuotaService.instance.ensureCanStartDiagnosis(
      context,
    );
    if (!allowed || !context.mounted) {
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => screen,
    ));
  }

  void _openAddVehicle(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<Vehicle>(builder: (_) => const AddVehicleScreen()),
    );
  }

  void _openMyVehicles(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MyVehiclesScreen()),
    );
  }

  void _showAddFirst(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: const Text('Please add a vehicle first'),
        action: SnackBarAction(
          label: 'Add',
          textColor: AppColors.accent,
          onPressed: () => _openAddVehicle(context),
        ),
      ),
    );
  }
}

class _VehicleHero extends StatelessWidget {
  const _VehicleHero({required this.vehicle});
  final Vehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final brandColor = Color(CarImageService.brandTint(vehicle.make));

    return Stack(
      children: [
        // car image background
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.network(
              CarImageService.imageUrl(
                make: vehicle.make,
                model: vehicle.model,
                year: vehicle.year,
              ),
              fit: BoxFit.cover,
              alignment: const Alignment(0.0, 0.1),
              errorBuilder: (_, __, ___) => Image.asset(
                CarImageService.defaultAsset,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.surface,
                ),
              ),
            ),
          ),
        ),
        // gradient overlay for text readability
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.background.withValues(alpha: 0.92),
                  AppColors.background.withValues(alpha: 0.45),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.45, 0.85],
              ),
            ),
          ),
        ),
        // bottom gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.background.withValues(alpha: 0.7),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ),
        // text content
        Positioned(
          left: 20,
          bottom: 16,
          right: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                vehicle.make.toUpperCase(),
                style: tt.bodySmall?.copyWith(
                  color: brandColor,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vehicle.model,
                style: tt.headlineLarge?.copyWith(fontSize: 24),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${vehicle.year} · ${vehicle.fuelLabel} · ${vehicle.mileageKm} km',
                style: tt.bodySmall,
              ),
            ],
          ),
        ),
        // swap button
        Positioned(
          right: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.surface.withValues(alpha: 0.85),
              border: Border.all(
                color: const Color(0x15FFFFFF),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 4),
                Text('Switch',
                    style: tt.bodySmall?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Stack(
      children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              CarImageService.defaultAsset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppColors.surface,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  AppColors.background.withValues(alpha: 0.95),
                  AppColors.background.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Welcome to FixEase', style: tt.headlineMedium),
              const SizedBox(height: 6),
              Text(
                'Add your vehicle to start\nAI-powered diagnostics.',
                style: tt.bodyMedium,
              ),
              const SizedBox(height: 16),
              NeuPrimaryButton(
                expanded: false,
                label: 'Add Vehicle',
                icon: Icons.add_rounded,
                onPressed: onAdd,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diagnose Tab
// ═══════════════════════════════════════════════════════════════════════════

class DiagnoseTabBody extends StatelessWidget {
  const DiagnoseTabBody({super.key});

  Future<void> _guardedLaunch(BuildContext context, Widget screen) async {
    final v = VehicleService.instance.selected;
    if (v == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a vehicle first')),
      );
      return;
    }
    final allowed = await QuotaService.instance.ensureCanStartDiagnosis(
      context,
    );
    if (!allowed || !context.mounted) {
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => screen,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Choose Diagnostic Mode', style: tt.headlineMedium),
              const Spacer(),
              ListenableBuilder(
                listenable: Listenable.merge([
                  SubscriptionService.instance,
                  QuotaService.instance,
                ]),
                builder: (_, __) {
                  final sub = SubscriptionService.instance;
                  final badgeLabel =
                      QuotaService.instance.diagnosticsBadgeLabel;
                  if (sub.isUnlimited || badgeLabel == null) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: AppColors.accent.withValues(alpha: 0.12),
                    ),
                    child: Text(
                      badgeLabel,
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select how you\'d like to diagnose your vehicle.',
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 6),
          const _FreeQuotaHelperText(),
          const SizedBox(height: 24),

          _DiagnoseOptionCard(
            icon: Icons.warning_amber_rounded,
            title: 'Urgent On-the-Spot',
            description:
                'Answer quick questions about symptoms you\'re experiencing '
                'right now for an immediate AI analysis.',
            accentColor: const Color(0xFFFF9800),
            onTap: () => _guardedLaunch(context, const UrgentWizardScreen()),
          ),
          const SizedBox(height: 14),

          _DiagnoseOptionCard(
            icon: Icons.camera_alt_rounded,
            title: 'Photo-Based',
            description:
                'Upload or take photos of the issue — our AI analyzes visible '
                'damage, fluid leaks, tire wear, and more.',
            accentColor: AppColors.accent,
            onTap: () => _guardedLaunch(context, const PhotoDiagnoseScreen()),
          ),
          const SizedBox(height: 14),

          // Gemini Live
          _DiagnoseOptionCard(
            icon: Icons.videocam_rounded,
            title: 'Gemini Live',
            description: 'Real-time AI diagnosis via your camera. '
                'Point, capture, and chat with Gemini about what it sees.',
            accentColor: const Color(0xFF4CAF50),
            badge: 'BETA',
            onTap: () => launchLiveDiagnosis(context),
          ),
          const SizedBox(height: 14),
          _DiagnoseOptionCard(
            icon: Icons.sensors_rounded,
            title: 'OBD Pro Diagnostic Suite',
            description:
                'Connect a Bluetooth ELM327 adapter for live vitals, a one-time '
                'ECU snapshot, and premium idle and drive scans.',
            accentColor: const Color(0xFF7EE787),
            badge: 'PRO',
            onTap: () => launchObdProSuite(context),
          ),
        ],
      ),
    );
  }
}

class _DiagnoseOptionCard extends StatelessWidget {
  const _DiagnoseOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: NeuPane(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.15),
              ),
              child: Icon(icon, color: accentColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: tt.titleLarge),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            color: accentColor.withValues(alpha: 0.2),
                          ),
                          child: Text(
                            badge!,
                            style: tt.bodySmall?.copyWith(
                              color: accentColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 8,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(description, style: tt.bodyMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Start',
                          style: tt.labelLarge?.copyWith(color: accentColor)),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: accentColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FreeQuotaHelperText extends StatelessWidget {
  const _FreeQuotaHelperText();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        SubscriptionService.instance,
        QuotaService.instance,
      ]),
      builder: (_, __) {
        final sub = SubscriptionService.instance;
        final subtitle = QuotaService.instance.diagnosticsSubtitleLabel;
        if (sub.isUnlimited || subtitle == null) {
          return const SizedBox.shrink();
        }

        return Text(
          subtitle,
          style: tt.bodySmall?.copyWith(
            color: AppColors.textTertiary,
            fontSize: 11,
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Reports Tab
// ═══════════════════════════════════════════════════════════════════════════

class ReportsTabBody extends StatelessWidget {
  const ReportsTabBody({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: Listenable.merge([
        DiagnosticService.instance,
        ConversationService.instance,
        SubscriptionService.instance,
      ]),
      builder: (context, _) {
        final all = DiagnosticService.instance.sessions;

        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insights_rounded,
                    size: 56, color: AppColors.textTertiary),
                const SizedBox(height: 16),
                Text('No reports yet', style: tt.bodyLarge),
                const SizedBox(height: 6),
                Text('Run a diagnostic to see results here.',
                    style: tt.bodySmall),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          itemCount: all.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final s = all[i];
            return _ReportListCard(session: s);
          },
        );
      },
    );
  }
}

class _ReportListCard extends StatelessWidget {
  const _ReportListCard({required this.session});
  final DiagnosticSession session;

  Color get _scoreColor {
    final response = session.aiResponseJson != null
        ? AiDiagnosticResponse.fromJson(session.aiResponseJson!)
        : null;
    if (session.type == DiagnosticType.live) {
      return const Color(0xFF4CAF50);
    }
    if (response != null && response.hasDisplayableScore) {
      return response.statusColor;
    }
    final sc = session.healthScore ?? 0;
    if (sc >= 8) return const Color(0xFF4CAF50);
    if (sc >= 6) return const Color(0xFFFFC107);
    if (sc >= 4) return const Color(0xFFFF9800);
    return const Color(0xFFFF5252);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isUrgent = session.type == DiagnosticType.urgent;
    final isInvoiceAudit = session.type == DiagnosticType.invoiceAudit;
    final isLive = session.type == DiagnosticType.live;
    final isObdIdle = session.type == DiagnosticType.obdIdle;
    final isObdDrive = session.type == DiagnosticType.obdDrive;
    final response = session.aiResponseJson != null
        ? AiDiagnosticResponse.fromJson(session.aiResponseJson!)
        : null;
    final thread = ConversationService.instance.threadForSession(session.id);
    final icon = isUrgent
        ? Icons.warning_amber_rounded
        : isInvoiceAudit
            ? Icons.receipt_long_rounded
            : isLive
                ? Icons.videocam_rounded
                : isObdIdle
                    ? Icons.air_rounded
                    : isObdDrive
                        ? Icons.route_rounded
                : Icons.camera_alt_outlined;
    final iconColor = isUrgent
        ? const Color(0xFFFF9800)
        : isInvoiceAudit
            ? const Color(0xFFFF7043)
            : isLive
                ? const Color(0xFF4CAF50)
                : isObdIdle
                    ? const Color(0xFF5DD6B2)
                    : isObdDrive
                        ? const Color(0xFF7EE787)
                : AppColors.accent;
    final title = isUrgent
        ? 'Urgent Diagnosis'
        : isInvoiceAudit
            ? 'Invoice Audit'
            : isLive
                ? 'Gemini Live'
                : isObdIdle
                    ? 'OBD Idle Scan'
                    : isObdDrive
                        ? 'OBD Drive Scan'
                : 'Photo Diagnosis';
    final isLocked = DiagnosticService.instance.isOlderThanMostRecentSessions(
          session,
          allowedCount: 2,
        ) &&
        !checkAccess(
          FeatureType.olderHistoryAccess,
          session: session,
        );

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: const Color(0x33FF5252),
        ),
        child:
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252)),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text('Delete Report', style: tt.titleLarge),
            content: Text('This report will be permanently deleted.',
                style: tt.bodyMedium),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete',
                    style: TextStyle(color: Color(0xFFFF5252))),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => DiagnosticService.instance.delete(session.id),
      child: Opacity(
        opacity: isLocked ? 0.68 : 1,
        child: GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
            if (isLocked) {
              await ensureAccess(
                context,
                FeatureType.olderHistoryAccess,
                session: session,
                reason: 'Older Diagnostic History',
              );
              return;
            }
            if (!context.mounted) return;
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => isLive
                  ? ConversationChatScreen(session: session)
                  : ReportDetailScreen(session: session),
            ));
          },
          child: NeuPane(
            child: Row(
              children: [
                // health score ring (mini)
                SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: CircularProgressIndicator(
                          value: (response?.displayProgress ??
                                  ((session.healthScore ?? 0) / 10))
                              .clamp(0, 1)
                              .toDouble(),
                          strokeWidth: 3,
                          backgroundColor: AppColors.surfaceHighlight,
                          color: _scoreColor,
                        ),
                      ),
                      Text(
                        response?.displayScoreLabel ??
                            (session.healthScore != null
                                ? session.healthScore!.toStringAsFixed(1)
                                : '—'),
                        style: tt.bodySmall?.copyWith(
                          color: _scoreColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            icon,
                            size: 15,
                            color: iconColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              style: tt.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (session.vehicleName != null)
                        Text(
                          session.vehicleName!,
                          style:
                              tt.bodySmall?.copyWith(color: AppColors.accent),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(session.dateLabel, style: tt.bodySmall),
                          const SizedBox(width: 8),
                          Text(session.timeLabel,
                              style: tt.bodySmall
                                  ?.copyWith(color: AppColors.textTertiary)),
                          const Spacer(),
                          if (isLive)
                            Flexible(
                              child: Text(
                                thread?.previewText ?? 'Saved conversation',
                                style: tt.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            )
                          else if (session.type == DiagnosticType.invoiceAudit)
                            Text(
                              session.aiResponseJson?['document_type']
                                      as String? ??
                                  'Bill review',
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            )
                          else if (session.isObd)
                            Text(
                              session.contextJson?['obd_record']
                                          ?['is_partial'] ==
                                      true
                                  ? 'Partial OBD scan'
                                  : 'OBD telemetry',
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            )
                          else if (session.symptoms.isNotEmpty)
                            Text(
                              '${session.symptoms.length} symptom(s)',
                              style: tt.bodySmall?.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isLocked ? Icons.lock_rounded : Icons.chevron_right_rounded,
                  size: 18,
                  color: isLocked ? AppColors.accent : AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Profile Tab
// ═══════════════════════════════════════════════════════════════════════════

class ProfileTabBody extends StatelessWidget {
  const ProfileTabBody({super.key});

  Future<void> _openSupport() async {
    final uri = Uri.parse(
      'mailto:${AppConfig.supportEmail}?subject=FixEase%20Support%20Request',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openAbout() async {
    final launched = await launchUrl(
      Uri.parse(AppConfig.aboutUrl),
      mode: LaunchMode.inAppBrowserView,
    );
    if (!launched) {
      await launchUrl(
        Uri.parse(AppConfig.aboutUrl),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          NeuPane(
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.15),
                  ),
                  child: Center(
                    child: Text(
                      'F',
                      style: tt.headlineMedium?.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('FixEase Driver', style: tt.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        'Guest mode · all core data stays on this device',
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _ProfileMenuItem(
            icon: Icons.directions_car_rounded,
            label: 'My Vehicles',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyVehiclesScreen()),
            ),
          ),
          _ProfileMenuItem(
            icon: Icons.add_circle_outline_rounded,
            label: 'Add Vehicle',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AddVehicleScreen(),
              ),
            ),
          ),
          _ProfileMenuItem(
            icon: Icons.history_rounded,
            label: 'Diagnostic History',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DiagnosticHistoryScreen(),
                ),
              );
            },
          ),
          ListenableBuilder(
            listenable: SubscriptionService.instance,
            builder: (_, __) => _ProfileMenuItem(
              icon: Icons.workspace_premium_rounded,
              label: 'Subscription',
              subtitle: SubscriptionService.instance.tierLabel,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const PaywallScreen()),
              ),
            ),
          ),
          if (AppConfig.isDemoMode)
            _ProfileMenuItem(
              icon: Icons.restart_alt_rounded,
              label: 'Reset Free Credits',
              subtitle: 'Restore the free 3-diagnosis allowance',
              onTap: () async {
                try {
                  await SubscriptionService.instance.resetFreeCreditsForTesting();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Free credits reset for testing'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                }
              },
            ),
          _ProfileMenuItem(
            icon: Icons.help_outline_rounded,
            label: 'Help & Support',
            subtitle: AppConfig.supportEmail,
            onTap: () {
              _openSupport();
            },
          ),
          _ProfileMenuItem(
            icon: Icons.info_outline_rounded,
            label: 'About FixEase',
            subtitle: 'v1.0.0',
            onTap: () {
              _openAbout();
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: NeuPane(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: tt.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 1),
                      Text(subtitle!, style: tt.bodySmall),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
