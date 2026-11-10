import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';
import '../models/conversation.dart';
import '../models/diagnostic.dart';
import '../screens/subscription/paywall_screen.dart';
import 'conversation_service.dart';
import 'diagnostic_service.dart';
import 'local_store_service.dart';
import 'quota_service.dart';
import 'subscription_access_policy.dart';
import 'trusted_time_service.dart';

export 'subscription_access_policy.dart' show SubscriptionTier;

enum DemoSubscriptionState { mockFree, mockPass, mockPro }

enum FeatureType {
  invoiceAudit,
  techPdfAfterTwoReports,
  olderHistoryAccess,
  extendedLiveAudio,
  obdProSuite,
  standardFollowUpMessage,
  standardFollowUpMedia,
  liveTextMessage,
  liveAudioTurn,
  liveImageUpload,
}

enum SubscriptionProductType { emergencyPass, proDriver }

class SubscriptionProduct {
  const SubscriptionProduct({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.priceString,
    required this.billingLabel,
    required this.features,
    this.badge,
    this.recommended = false,
    this.livePackage,
    this.available = true,
  });

  final SubscriptionProductType type;
  final String title;
  final String subtitle;
  final String priceString;
  final String billingLabel;
  final List<String> features;
  final String? badge;
  final bool recommended;
  final Package? livePackage;
  final bool available;

  String get displayPrice =>
      billingLabel.isEmpty ? priceString : '$priceString $billingLabel';
}

enum ThreadUsageEvent {
  standardMessage,
  standardMedia,
  liveText,
  liveAudio,
  liveImage,
}

class ThreadUsage {
  const ThreadUsage({
    required this.sessionId,
    required this.sessionType,
    this.standardMessageCount = 0,
    this.standardMediaCount = 0,
    this.liveAudioTurnCount = 0,
    this.liveTextMessageCount = 0,
    this.liveImageUploadCount = 0,
    this.diagnosisCreditConsumed = false,
  });

  final String sessionId;
  final DiagnosticType sessionType;
  final int standardMessageCount;
  final int standardMediaCount;
  final int liveAudioTurnCount;
  final int liveTextMessageCount;
  final int liveImageUploadCount;
  final bool diagnosisCreditConsumed;

  ThreadUsage copyWith({
    String? sessionId,
    DiagnosticType? sessionType,
    int? standardMessageCount,
    int? standardMediaCount,
    int? liveAudioTurnCount,
    int? liveTextMessageCount,
    int? liveImageUploadCount,
    bool? diagnosisCreditConsumed,
  }) {
    return ThreadUsage(
      sessionId: sessionId ?? this.sessionId,
      sessionType: sessionType ?? this.sessionType,
      standardMessageCount: standardMessageCount ?? this.standardMessageCount,
      standardMediaCount: standardMediaCount ?? this.standardMediaCount,
      liveAudioTurnCount: liveAudioTurnCount ?? this.liveAudioTurnCount,
      liveTextMessageCount: liveTextMessageCount ?? this.liveTextMessageCount,
      liveImageUploadCount: liveImageUploadCount ?? this.liveImageUploadCount,
      diagnosisCreditConsumed:
          diagnosisCreditConsumed ?? this.diagnosisCreditConsumed,
    );
  }

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'session_type': sessionType.name,
        'standard_message_count': standardMessageCount,
        'standard_media_count': standardMediaCount,
        'live_audio_turn_count': liveAudioTurnCount,
        'live_text_message_count': liveTextMessageCount,
        'live_image_upload_count': liveImageUploadCount,
        'diagnosis_credit_consumed': diagnosisCreditConsumed,
      };

  factory ThreadUsage.fromJson(Map<String, dynamic> json) {
    final typeName =
        json['session_type'] as String? ?? DiagnosticType.urgent.name;
    final type = DiagnosticType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => DiagnosticType.urgent,
    );
    return ThreadUsage(
      sessionId: json['session_id'] as String,
      sessionType: type,
      standardMessageCount: json['standard_message_count'] as int? ?? 0,
      standardMediaCount: json['standard_media_count'] as int? ?? 0,
      liveAudioTurnCount: json['live_audio_turn_count'] as int? ?? 0,
      liveTextMessageCount: json['live_text_message_count'] as int? ?? 0,
      liveImageUploadCount: json['live_image_upload_count'] as int? ?? 0,
      diagnosisCreditConsumed:
          json['diagnosis_credit_consumed'] as bool? ?? false,
    );
  }
}

class ThreadLimitStatus {
  const ThreadLimitStatus._({
    required this.sessionId,
    required this.sessionType,
    required this.textAudioCount,
    required this.textAudioLimit,
    required this.imageCount,
    required this.imageLimit,
    required this.liveAudioCount,
    required this.liveAudioLimit,
    required this.liveTextCount,
    required this.liveTextLimit,
    required this.liveImageCount,
    required this.liveImageLimit,
    required this.hasPremiumAccess,
  });

  factory ThreadLimitStatus({
    required String sessionId,
    required DiagnosticType sessionType,
    required bool hasPremiumAccess,
    required ThreadUsage usage,
  }) {
    final isLive = sessionType == DiagnosticType.live;
    return ThreadLimitStatus._(
      sessionId: sessionId,
      sessionType: sessionType,
      textAudioCount: usage.standardMessageCount,
      textAudioLimit: hasPremiumAccess || isLive ? null : 10,
      imageCount: usage.standardMediaCount,
      imageLimit: isLive ? null : (hasPremiumAccess ? 10 : 3),
      liveAudioCount: usage.liveAudioTurnCount,
      liveAudioLimit: isLive && !hasPremiumAccess ? 20 : null,
      liveTextCount: usage.liveTextMessageCount,
      liveTextLimit: isLive && !hasPremiumAccess ? 50 : null,
      liveImageCount: usage.liveImageUploadCount,
      liveImageLimit: isLive ? (hasPremiumAccess ? 20 : 6) : null,
      hasPremiumAccess: hasPremiumAccess,
    );
  }

  final String sessionId;
  final DiagnosticType sessionType;
  final int textAudioCount;
  final int? textAudioLimit;
  final int imageCount;
  final int? imageLimit;
  final int liveAudioCount;
  final int? liveAudioLimit;
  final int liveTextCount;
  final int? liveTextLimit;
  final int liveImageCount;
  final int? liveImageLimit;
  final bool hasPremiumAccess;

  bool get isLive => sessionType == DiagnosticType.live;

  int? get textAudioRemaining => textAudioLimit == null
      ? null
      : (textAudioLimit! - textAudioCount).clamp(0, textAudioLimit!).toInt();
  int? get imageRemaining => imageLimit == null
      ? null
      : (imageLimit! - imageCount).clamp(0, imageLimit!).toInt();
  int? get liveAudioRemaining => liveAudioLimit == null
      ? null
      : (liveAudioLimit! - liveAudioCount).clamp(0, liveAudioLimit!).toInt();
  int? get liveTextRemaining => liveTextLimit == null
      ? null
      : (liveTextLimit! - liveTextCount).clamp(0, liveTextLimit!).toInt();
  int? get liveImageRemaining => liveImageLimit == null
      ? null
      : (liveImageLimit! - liveImageCount).clamp(0, liveImageLimit!).toInt();

  bool get textAudioLimitReached =>
      textAudioLimit != null && textAudioCount >= textAudioLimit!;
  bool get standardImageLimitReached =>
      imageLimit != null && imageCount >= imageLimit!;
  bool get liveAudioLimitReached =>
      liveAudioLimit != null && liveAudioCount >= liveAudioLimit!;
  bool get liveTextLimitReached =>
      liveTextLimit != null && liveTextCount >= liveTextLimit!;
  bool get liveImageLimitReached =>
      liveImageLimit != null && liveImageCount >= liveImageLimit!;

  bool get liveHardBlocked =>
      isLive &&
      !hasPremiumAccess &&
      (liveAudioLimitReached || liveTextLimitReached || liveImageLimitReached);
}

class SubscriptionService extends ChangeNotifier {
  SubscriptionService._();
  static final SubscriptionService instance = SubscriptionService._();

  static const _storageKey = 'subscription.v2';

  SubscriptionTier _tier = SubscriptionTier.free;
  DemoSubscriptionState _demoState = DemoSubscriptionState.mockFree;
  DateTime? _emergencyExpiresAt;
  int _diagnosticsThisMonth = 0;
  DateTime _monthStart =
      DateTime.utc(DateTime.now().year, DateTime.now().month);
  DateTime? _lastTrustedUtc;
  final Map<String, ThreadUsage> _threadUsage = {};

  Offerings? _offerings;
  CustomerInfo? _customerInfo;
  bool _configuredPurchases = false;
  bool _isPurchasing = false;
  bool _isRestoring = false;
  String? _lastSyncErrorMessage;
  Future<void>? _configurationFuture;
  Future<void>? _refreshFuture;
  Timer? _accessExpiryTimer;
  final Stopwatch _elapsed = Stopwatch()..start();
  final DateTime _clockAnchor = DateTime.now().toUtc();
  DateTime? _accessClockHighWater;
  DateTime? _accessValidUntil;
  static const _storeTimeout = Duration(seconds: 8);
  static const _restoreTimeout = Duration(seconds: 25);

  SubscriptionTier get tier {
    _refreshEntitlementAccess();
    return _tier;
  }

  DemoSubscriptionState get demoState => _demoState;
  DateTime? get emergencyExpiresAt => _emergencyExpiresAt;
  Offerings? get offerings => _offerings;
  CustomerInfo? get customerInfo => _customerInfo;
  bool get isPurchasing => _isPurchasing;
  bool get isRestoring => _isRestoring;
  String? get lastSyncErrorMessage => _lastSyncErrorMessage;
  bool get isDemoMode => AppConfig.isDemoMode;

  int get diagnosticsThisMonth => _diagnosticsThisMonth;
  int get diagnosticsRemaining => isUnlimited
      ? 9999
      : (AppConfig.freeDiagnosticsPerMonth - _diagnosticsThisMonth)
          .clamp(0, AppConfig.freeDiagnosticsPerMonth)
          .toInt();
  bool get isUnlimited => tier != SubscriptionTier.free;
  bool get canDiagnose =>
      isUnlimited || _diagnosticsThisMonth < AppConfig.freeDiagnosticsPerMonth;
  bool get hasPremiumAccess => tier != SubscriptionTier.free;
  Duration get liveAudioLimit => hasPremiumAccess
      ? const Duration(minutes: 10)
      : const Duration(minutes: 3);

  Future<Map<String, String>> backendEntitlementHeaders() async {
    if (!AppConfig.isDemoMode && _customerInfo == null) {
      await _refreshStoreState(
          includeOfferings: false, source: 'backendRequest');
    }
    final paid = !AppConfig.isDemoMode && hasPremiumAccess;
    return {
      'x-fixease-plan': paid ? 'pro' : 'free',
      if (paid)
        'x-fixease-customer-id':
            await Purchases.appUserID.timeout(_storeTimeout),
    };
  }

  ThreadLimitStatus threadLimitStatus({
    required String sessionId,
    required DiagnosticType sessionType,
  }) {
    final usage = _usageFor(sessionId, sessionType);
    return ThreadLimitStatus(
      sessionId: sessionId,
      sessionType: sessionType,
      hasPremiumAccess: hasPremiumAccess,
      usage: usage,
    );
  }

  String get tierLabel => switch (tier) {
        SubscriptionTier.free => 'Free',
        SubscriptionTier.emergencyPass => 'Emergency Pass',
        SubscriptionTier.pro => 'Pro Driver',
      };

  String get statusLabel =>
      AppConfig.isDemoMode ? 'Demo - $tierLabel' : tierLabel;

  String get tierBadge => switch (_tier) {
        SubscriptionTier.free => '',
        SubscriptionTier.emergencyPass => '48H ACCESS',
        SubscriptionTier.pro => 'RECOMMENDED',
      };

  Future<void> restore() async {
    await _loadPersisted();
    _syncThreadUsageFromLocalData();
    unawaited(refreshMonthlyCreditsForDisplay());

    if (AppConfig.isDemoMode) {
      _applyDemoState(_demoState);
      notifyListeners();
      return;
    }

    // Startup must render even if Play or the network is unavailable. The SDK
    // returns its persisted CustomerInfo cache independently of product loading.
    unawaited(_refreshStoreState(includeOfferings: true, source: 'restore'));
  }

  Future<void> refresh() async {
    _syncThreadUsageFromLocalData();
    unawaited(refreshMonthlyCreditsForDisplay());

    if (AppConfig.isDemoMode) {
      _applyDemoState(_demoState);
      notifyListeners();
      return;
    }

    await _refreshStoreState(includeOfferings: true, source: 'refresh');
  }

  Future<bool> purchaseProduct(SubscriptionProductType type) async {
    if (_isPurchasing) return false;
    _isPurchasing = true;
    notifyListeners();

    try {
      if (AppConfig.isDemoMode) {
        await setDemoState(
          switch (type) {
            SubscriptionProductType.emergencyPass =>
              DemoSubscriptionState.mockPass,
            SubscriptionProductType.proDriver => DemoSubscriptionState.mockPro,
          },
        );
        return true;
      }

      await _configurePurchasesIfNeeded();
      if (!_configuredPurchases) return false;
      if (productForType(type)?.livePackage == null) await _loadOfferings();
      final livePackage = productForType(type)?.livePackage;
      if (livePackage == null) return false;

      final result =
          await Purchases.purchase(PurchaseParams.package(livePackage));
      _lastSyncErrorMessage = null;
      _applyCustomerInfo(result.customerInfo);
      notifyListeners();
      return SubscriptionAccessPolicy.isTrusted(result.customerInfo,
              allowDeviceVerification: Platform.isIOS) &&
          hasPremiumAccess;
    } catch (error, stackTrace) {
      _recordSyncFailure(
        source: 'purchaseProduct',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _isPurchasing = false;
      notifyListeners();
    }
  }

  Future<bool> purchase(SubscriptionTier tier) {
    return purchaseProduct(
      tier == SubscriptionTier.pro
          ? SubscriptionProductType.proDriver
          : SubscriptionProductType.emergencyPass,
    );
  }

  Future<bool> restorePurchases() async {
    if (_isRestoring) return false;
    _isRestoring = true;
    notifyListeners();

    try {
      if (AppConfig.isDemoMode) {
        _applyDemoState(_demoState);
        return hasPremiumAccess;
      }

      await _configurePurchasesIfNeeded();
      if (!_configuredPurchases) {
        _lastSyncErrorMessage =
            'Subscription status could not be verified because RevenueCat is not configured.';
        return false;
      }
      final info = await Purchases.restorePurchases().timeout(_restoreTimeout);
      _lastSyncErrorMessage = null;
      _applyCustomerInfo(info);
      return SubscriptionAccessPolicy.isTrusted(info,
              allowDeviceVerification: Platform.isIOS) &&
          hasPremiumAccess;
    } catch (error, stackTrace) {
      _recordSyncFailure(
        source: 'restorePurchases',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> setDemoState(DemoSubscriptionState state) async {
    if (!AppConfig.isDemoMode) return;
    _demoState = state;
    _applyDemoState(state);
    await _persist();
    notifyListeners();
  }

  Future<void> resetFreeCreditsForTesting() async {
    _diagnosticsThisMonth = 0;
    if (AppConfig.isDemoMode && _tier != SubscriptionTier.free) {
      _tier = SubscriptionTier.free;
      _demoState = DemoSubscriptionState.mockFree;
      _emergencyExpiresAt = null;
    }
    await QuotaService.instance.resetForTesting();
    await _persist();
    notifyListeners();
  }

  Future<void> recordDiagnosis() async {
    notifyListeners();
  }

  Future<void> recordLiveDiagnosisIfNeeded({
    required String sessionId,
  }) async {
    final usage = _threadUsage[sessionId];
    if (usage == null || usage.diagnosisCreditConsumed) return;

    _threadUsage[sessionId] = usage.copyWith(diagnosisCreditConsumed: true);
    notifyListeners();
    await _persist();
  }

  Future<void> refreshMonthlyCreditsForDisplay() async {
    final trustedUtc = await TrustedTimeService.instance.fetchUtcNow();
    if (trustedUtc != null) {
      await _applyMonthReference(trustedUtc, rememberTrusted: true);
      return;
    }
    debugPrint(
      'SubscriptionService: trusted time unavailable, monthly free-credit '
      'reset remains locked to the last verified period.',
    );
  }

  bool checkAccess(
    FeatureType feature, {
    DiagnosticSession? session,
    String? threadId,
    DiagnosticType? threadType,
  }) {
    _expireEmergencyIfNeeded();
    final resolvedSessionId = session?.id ?? threadId;
    final resolvedThreadType = session?.type ?? threadType;

    switch (feature) {
      case FeatureType.invoiceAudit:
        return hasPremiumAccess;
      case FeatureType.techPdfAfterTwoReports:
        return hasPremiumAccess;
      case FeatureType.olderHistoryAccess:
        if (hasPremiumAccess) return true;
        if (session == null) return false;
        return DiagnosticService.instance.isWithinMostRecentSessions(
          session,
          allowedCount: 2,
        );
      case FeatureType.extendedLiveAudio:
        return hasPremiumAccess;
      case FeatureType.obdProSuite:
        return hasPremiumAccess;
      case FeatureType.standardFollowUpMessage:
        if (resolvedSessionId == null || resolvedThreadType == null) {
          return false;
        }
        return !threadLimitStatus(
          sessionId: resolvedSessionId,
          sessionType: resolvedThreadType,
        ).textAudioLimitReached;
      case FeatureType.standardFollowUpMedia:
        if (resolvedSessionId == null || resolvedThreadType == null) {
          return false;
        }
        return !threadLimitStatus(
          sessionId: resolvedSessionId,
          sessionType: resolvedThreadType,
        ).standardImageLimitReached;
      case FeatureType.liveTextMessage:
        if (resolvedSessionId == null || resolvedThreadType == null) {
          return false;
        }
        final status = threadLimitStatus(
          sessionId: resolvedSessionId,
          sessionType: resolvedThreadType,
        );
        return !status.liveHardBlocked && !status.liveTextLimitReached;
      case FeatureType.liveAudioTurn:
        if (resolvedSessionId == null || resolvedThreadType == null) {
          return false;
        }
        final status = threadLimitStatus(
          sessionId: resolvedSessionId,
          sessionType: resolvedThreadType,
        );
        return !status.liveHardBlocked && !status.liveAudioLimitReached;
      case FeatureType.liveImageUpload:
        if (resolvedSessionId == null || resolvedThreadType == null) {
          return false;
        }
        final status = threadLimitStatus(
          sessionId: resolvedSessionId,
          sessionType: resolvedThreadType,
        );
        return !status.liveHardBlocked && !status.liveImageLimitReached;
    }
  }

  Future<void> recordThreadEvent({
    required String sessionId,
    required DiagnosticType sessionType,
    required ThreadUsageEvent event,
  }) async {
    final current = _usageFor(sessionId, sessionType);
    late final ThreadUsage next;
    switch (event) {
      case ThreadUsageEvent.standardMessage:
        next = current.copyWith(
          sessionType: sessionType,
          standardMessageCount: current.standardMessageCount + 1,
        );
      case ThreadUsageEvent.standardMedia:
        next = current.copyWith(
          sessionType: sessionType,
          standardMediaCount: current.standardMediaCount + 1,
        );
      case ThreadUsageEvent.liveText:
        next = current.copyWith(
          sessionType: sessionType,
          liveTextMessageCount: current.liveTextMessageCount + 1,
        );
      case ThreadUsageEvent.liveAudio:
        next = current.copyWith(
          sessionType: sessionType,
          liveAudioTurnCount: current.liveAudioTurnCount + 1,
        );
      case ThreadUsageEvent.liveImage:
        next = current.copyWith(
          sessionType: sessionType,
          liveImageUploadCount: current.liveImageUploadCount + 1,
        );
    }
    _threadUsage[sessionId] = next;
    notifyListeners();
    await _persist();
  }

  Future<void> clearThreadUsage(String sessionId) async {
    if (_threadUsage.remove(sessionId) == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> clearThreadUsageForAll(Iterable<String> sessionIds) async {
    var changed = false;
    for (final sessionId in sessionIds) {
      changed = _threadUsage.remove(sessionId) != null || changed;
    }
    if (!changed) return;
    notifyListeners();
    await _persist();
  }

  Future<bool> ensureAccess(
    BuildContext context,
    FeatureType feature, {
    String? reason,
    DiagnosticSession? session,
    String? threadId,
    DiagnosticType? threadType,
  }) async {
    if (checkAccess(
      feature,
      session: session,
      threadId: threadId,
      threadType: threadType,
    )) {
      return true;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PaywallScreen(
          requiredFeature: reason ?? _featureReason(feature),
        ),
      ),
    );
    return checkAccess(
      feature,
      session: session,
      threadId: threadId,
      threadType: threadType,
    );
  }

  List<SubscriptionProduct> get paywallProducts {
    if (AppConfig.isDemoMode) {
      return const [
        SubscriptionProduct(
          type: SubscriptionProductType.emergencyPass,
          title: 'Emergency Pass',
          subtitle: '48 hours of premium access for a single repair situation.',
          priceString: AppConfig.emergencyDemoPrice,
          billingLabel: 'one-time',
          badge: 'ONE-TIME',
          features: [
            'Invoice audit access',
            'Unlimited report exports for 48 hours',
            'Extended live audio for 48 hours',
            'Unlock older diagnostic history',
            'OBD Pro Diagnostic Suite',
          ],
        ),
        SubscriptionProduct(
          type: SubscriptionProductType.proDriver,
          title: 'Pro Driver',
          subtitle:
              'Ongoing premium access for drivers who want certainty year-round.',
          priceString: AppConfig.proDemoPrice,
          billingLabel: '/month',
          badge: 'BEST VALUE',
          recommended: true,
          features: [
            'Unlimited premium access',
            'Invoice auditing',
            'Unlimited tech PDF access',
            'Older history unlocked',
            '10-minute live audio',
            'OBD Pro Diagnostic Suite',
            'Priority AI processing',
          ],
        ),
      ];
    }

    final offering = _currentOffering;
    return [
      _buildLiveProduct(
        type: SubscriptionProductType.emergencyPass,
        title: 'Emergency Pass',
        subtitle: '48 hours of premium access for one urgent situation.',
        badge: 'ONE-TIME',
        fallbackPrice: AppConfig.emergencyDemoPrice,
        fallbackBilling: 'one-time',
        features: const [
          'Invoice audit access',
          'Unlimited report exports for 48 hours',
          'Extended live audio for 48 hours',
          'Unlock older diagnostic history',
          'OBD Pro Diagnostic Suite',
        ],
        package: _findPackage(
          offering,
          [AppConfig.emergencyProductId, r'$rc_lifetime', 'emergency_pass'],
        ),
      ),
      _buildLiveProduct(
        type: SubscriptionProductType.proDriver,
        title: 'Pro Driver',
        subtitle: 'Our recommended monthly plan for the full FixEase toolkit.',
        badge: 'BEST VALUE',
        recommended: true,
        fallbackPrice: AppConfig.proDemoPrice,
        fallbackBilling: '/month',
        features: const [
          'Unlimited premium access',
          'Invoice auditing',
          'Unlimited tech PDF access',
          'Older history unlocked',
          '10-minute live audio',
          'OBD Pro Diagnostic Suite',
          'Priority AI processing',
        ],
        package: _findPackage(
          offering,
          [AppConfig.proProductId, r'$rc_monthly', 'pro_driver_monthly'],
        ),
      ),
    ];
  }

  SubscriptionProduct? productForType(SubscriptionProductType type) {
    for (final product in paywallProducts) {
      if (product.type == type) return product;
    }
    return null;
  }

  Offering? get _currentOffering {
    final offerings = _offerings;
    if (offerings == null) return null;
    return offerings.all[AppConfig.offeringId] ?? offerings.current;
  }

  SubscriptionProduct _buildLiveProduct({
    required SubscriptionProductType type,
    required String title,
    required String subtitle,
    required List<String> features,
    required String fallbackPrice,
    required String fallbackBilling,
    String? badge,
    bool recommended = false,
    Package? package,
  }) {
    final storeProduct = package?.storeProduct;
    return SubscriptionProduct(
      type: type,
      title: title,
      subtitle: subtitle,
      priceString: storeProduct?.priceString ?? fallbackPrice,
      billingLabel:
          storeProduct != null ? _billingLabel(type) : fallbackBilling,
      badge: badge,
      recommended: recommended,
      livePackage: package,
      available: package != null,
      features: features,
    );
  }

  String _billingLabel(SubscriptionProductType type) => switch (type) {
        SubscriptionProductType.emergencyPass => 'one-time',
        SubscriptionProductType.proDriver => '/month',
      };

  Package? _findPackage(Offering? offering, List<String> ids) {
    if (offering == null) return null;
    for (final package in offering.availablePackages) {
      final packageId = package.identifier.toLowerCase();
      final productId = package.storeProduct.identifier.toLowerCase();
      if (ids.any((id) =>
          packageId == id.toLowerCase() || productId == id.toLowerCase())) {
        return package;
      }
    }
    return null;
  }

  Future<void> _configurePurchasesIfNeeded() async {
    if (_configuredPurchases || AppConfig.isDemoMode) return;
    await (_configurationFuture ??= _configurePurchases().whenComplete(() {
      _configurationFuture = null;
    }));
  }

  Future<void> _configurePurchases() async {
    final apiKey = Platform.isIOS
        ? AppConfig.revenueCatIosApiKey
        : AppConfig.revenueCatAndroidApiKey;
    final prefix = Platform.isIOS ? 'appl_' : 'goog_';
    if (!apiKey.startsWith(prefix)) return;

    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.debug : LogLevel.warn,
    ).timeout(_storeTimeout);
    final configuration = PurchasesConfiguration(apiKey)
      ..entitlementVerificationMode = EntitlementVerificationMode.informational;
    await Purchases.configure(configuration).timeout(_storeTimeout);
    Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
    _configuredPurchases = true;
  }

  void _applyDemoState(DemoSubscriptionState state) {
    switch (state) {
      case DemoSubscriptionState.mockFree:
        _tier = SubscriptionTier.free;
        _emergencyExpiresAt = null;
      case DemoSubscriptionState.mockPass:
        _tier = SubscriptionTier.emergencyPass;
        _emergencyExpiresAt = DateTime.now().add(const Duration(hours: 48));
      case DemoSubscriptionState.mockPro:
        _tier = SubscriptionTier.pro;
        _emergencyExpiresAt = null;
    }
  }

  void _applyCustomerInfo(CustomerInfo info) {
    if (!SubscriptionAccessPolicy.isTrusted(info,
        allowDeviceVerification: Platform.isIOS)) {
      _refreshEntitlementAccess();
      _lastSyncErrorMessage = hasPremiumAccess
          ? 'Store verification is unavailable. Your previously verified paid access remains available temporarily.'
          : 'Connect to securely verify your purchases before using paid access.';
      notifyListeners();
      return;
    }
    final previousDate = DateTime.tryParse(_customerInfo?.requestDate ?? '');
    final incomingDate = DateTime.tryParse(info.requestDate);
    if (previousDate != null &&
        incomingDate != null &&
        incomingDate.isBefore(previousDate)) {
      // A late background refresh must not overwrite a newer purchase/revocation.
      return;
    }
    _customerInfo = info;
    _lastSyncErrorMessage = null;
    _refreshEntitlementAccess();
    notifyListeners();
  }

  Future<void> _refreshStoreState({
    required bool includeOfferings,
    required String source,
  }) {
    return _refreshFuture ??= _syncStoreState(
      includeOfferings: includeOfferings,
      source: source,
    ).whenComplete(() => _refreshFuture = null);
  }

  Future<void> _syncStoreState({
    required bool includeOfferings,
    required String source,
  }) async {
    _lastSyncErrorMessage = null;
    try {
      await _configurePurchasesIfNeeded();
      if (!_configuredPurchases) {
        throw StateError(
            'RevenueCat is not configured with a platform SDK key.');
      }
      // Fetch cached entitlements before products: Play's product lookup can
      // fail offline even while this customer's paid cache remains valid.
      var info = await Purchases.getCustomerInfo().timeout(_storeTimeout);
      if (info.entitlements.verification == VerificationResult.notRequested) {
        // One online refresh migrates older unsigned SDK caches. Never turn
        // an editable local paid flag into a trusted offline entitlement.
        await Purchases.invalidateCustomerInfoCache().timeout(_storeTimeout);
        info = await Purchases.getCustomerInfo().timeout(_storeTimeout);
      }
      _applyCustomerInfo(info);
    } catch (error, stackTrace) {
      _recordSyncFailure(
        source: '$source:getCustomerInfo',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (includeOfferings && _configuredPurchases) unawaited(_loadOfferings());
    notifyListeners();
  }

  Future<void> _loadOfferings() async {
    try {
      _offerings = await Purchases.getOfferings().timeout(_storeTimeout);
    } catch (_) {
      // Product availability affects new purchases, never existing paid access.
    }
    notifyListeners();
  }

  DateTime _entitlementNow() {
    var now = DateTime.now().toUtc();
    final monotonic = _clockAnchor.add(_elapsed.elapsed);
    if (monotonic.isAfter(now)) now = monotonic;
    if (_accessClockHighWater?.isAfter(now) == true) {
      now = _accessClockHighWater!;
    }
    _accessClockHighWater = now;
    return now;
  }

  void _refreshEntitlementAccess() {
    if (AppConfig.isDemoMode) return;
    final info = _customerInfo;
    final access = info == null
        ? const SubscriptionAccess(SubscriptionTier.free)
        : SubscriptionAccessPolicy.evaluate(info, _entitlementNow(),
            allowDeviceVerification: Platform.isIOS);
    _tier = access.tier;
    _emergencyExpiresAt = access.tier == SubscriptionTier.emergencyPass
        ? access.validUntil
        : null;
    if (access.message != null) _lastSyncErrorMessage = access.message;
    if (_accessValidUntil != access.validUntil) {
      _accessExpiryTimer?.cancel();
      _accessValidUntil = access.validUntil;
      if (access.validUntil != null) {
        final remaining = access.validUntil!.difference(_entitlementNow());
        if (remaining > Duration.zero) {
          _accessExpiryTimer = Timer(remaining, () {
            _refreshEntitlementAccess();
            notifyListeners();
          });
        }
      }
    }
  }

  void _recordSyncFailure({
    required String source,
    required Object error,
    required StackTrace stackTrace,
  }) {
    final message =
        'Subscription verification failed during $source: ${error.toString()}';
    _refreshEntitlementAccess();
    if (error is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(error);
      if (code == PurchasesErrorCode.paymentPendingError) {
        _lastSyncErrorMessage =
            'Your payment is pending store confirmation. New paid access starts after confirmation; any previously verified access remains available.';
        return;
      }
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        _lastSyncErrorMessage =
            'Purchase cancelled. Your existing access is unchanged.';
        return;
      }
    }
    _lastSyncErrorMessage = hasPremiumAccess
        ? 'The store could not refresh your purchases. Previously verified paid access is still available temporarily; reconnect to refresh it.'
        : 'Connect to the internet to verify or refresh your paid access.';
    debugPrint(message);
    debugPrintStack(
      stackTrace: stackTrace,
      label: 'SubscriptionService sync failure',
    );
  }

  Future<void> _loadPersisted() async {
    final row = LocalStoreService.readJsonMap(_storageKey);
    if (row == null) return;

    final monthStartRaw = row['month_start'] as String?;
    final parsedMonth =
        monthStartRaw != null ? DateTime.tryParse(monthStartRaw) : null;
    if (parsedMonth != null) {
      _monthStart = DateTime(parsedMonth.year, parsedMonth.month);
    }

    _diagnosticsThisMonth = row['diagnostics_used'] as int? ?? 0;
    _demoState = DemoSubscriptionState.values.byName(
      row['demo_state'] as String? ?? DemoSubscriptionState.mockFree.name,
    );

    final trustedRaw = row['last_trusted_utc'] as String?;
    _lastTrustedUtc = trustedRaw != null ? DateTime.tryParse(trustedRaw) : null;
    final threadUsageRows = row['thread_usage'] as Map?;
    _threadUsage
      ..clear()
      ..addEntries(
        threadUsageRows?.entries.map((entry) {
              final value = entry.value;
              final usage = ThreadUsage.fromJson(
                Map<String, dynamic>.from(value as Map),
              );
              return MapEntry(entry.key.toString(), usage);
            }) ??
            const Iterable<MapEntry<String, ThreadUsage>>.empty(),
      );
    if (_lastTrustedUtc != null) {
      _resetMonthIfNeeded(_lastTrustedUtc!);
    }
  }

  void _resetMonthIfNeeded(DateTime referenceUtc) {
    final thisMonth = DateTime.utc(referenceUtc.year, referenceUtc.month);
    if (thisMonth.isAfter(_monthStart)) {
      _monthStart = thisMonth;
      _diagnosticsThisMonth = 0;
    }
  }

  Future<void> _applyMonthReference(
    DateTime referenceUtc, {
    bool rememberTrusted = false,
  }) async {
    if (rememberTrusted) {
      _lastTrustedUtc = referenceUtc;
    }
    final beforeMonth = _monthStart;
    _resetMonthIfNeeded(referenceUtc);
    if (beforeMonth != _monthStart) {
      notifyListeners();
    }
    await _persist();
  }

  Future<void> _persist() {
    return LocalStoreService.writeJsonMap(
      _storageKey,
      {
        'demo_state': _demoState.name,
        'diagnostics_used': _diagnosticsThisMonth,
        'month_start': _monthStart.toIso8601String(),
        'last_trusted_utc': _lastTrustedUtc?.toIso8601String(),
        'thread_usage': _threadUsage.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      },
    );
  }

  void _expireEmergencyIfNeeded() {
    if (!AppConfig.isDemoMode) {
      _refreshEntitlementAccess();
      return;
    }
    final expiry = _emergencyExpiresAt;
    if (_tier == SubscriptionTier.emergencyPass &&
        expiry != null &&
        expiry.isBefore(DateTime.now())) {
      _tier = SubscriptionTier.free;
      _emergencyExpiresAt = null;
    }
  }

  @override
  void dispose() {
    _accessExpiryTimer?.cancel();
    if (_configuredPurchases) {
      Purchases.removeCustomerInfoUpdateListener(_applyCustomerInfo);
    }
    super.dispose();
  }

  String _featureReason(FeatureType feature) => switch (feature) {
        FeatureType.invoiceAudit => 'Invoice Audit',
        FeatureType.techPdfAfterTwoReports => 'Download Tech PDF',
        FeatureType.olderHistoryAccess => 'Older Diagnostic History',
        FeatureType.extendedLiveAudio => '10-minute Live Audio',
        FeatureType.obdProSuite => 'OBD Pro Diagnostic Suite',
        FeatureType.standardFollowUpMessage => 'Continue Conversation',
        FeatureType.standardFollowUpMedia => 'Conversation Attachments',
        FeatureType.liveTextMessage => 'Continue Gemini Live',
        FeatureType.liveAudioTurn => 'Free Live Voice Limit',
        FeatureType.liveImageUpload => 'Live Photo Uploads',
      };

  ThreadUsage _usageFor(String sessionId, DiagnosticType sessionType) {
    return _threadUsage[sessionId] ??
        ThreadUsage(sessionId: sessionId, sessionType: sessionType);
  }

  void _syncThreadUsageFromLocalData() {
    var changed = false;
    for (final session in DiagnosticService.instance.sessions) {
      final thread = ConversationService.instance.threadForSession(session.id);
      final rebuilt = _deriveUsage(session, thread);
      final existing = _threadUsage[session.id];
      if (existing == null ||
          existing.toJson().toString() != rebuilt.toJson().toString()) {
        _threadUsage[session.id] = rebuilt;
        changed = true;
      }
    }
    final liveSessionIds = DiagnosticService.instance.sessions
        .map((session) => session.id)
        .toSet();
    final orphanedKeys = _threadUsage.keys
        .where((key) => !liveSessionIds.contains(key))
        .toList();
    if (orphanedKeys.isNotEmpty) {
      for (final key in orphanedKeys) {
        _threadUsage.remove(key);
      }
      changed = true;
    }
    if (changed) {
      notifyListeners();
      _persist();
    }
  }

  ThreadUsage _deriveUsage(
    DiagnosticSession session,
    ConversationThread? thread,
  ) {
    final messages = thread?.messages ?? const <ConversationMessage>[];
    if (session.type == DiagnosticType.live) {
      var audio = 0;
      var text = 0;
      var images = 0;
      for (final message in messages) {
        if (message.role != ConversationMessageRole.user) continue;
        switch (message.source) {
          case ConversationMessageSource.audio:
            audio++;
          case ConversationMessageSource.text:
            text++;
          case ConversationMessageSource.image:
          case ConversationMessageSource.file:
            images++;
        }
      }
      return ThreadUsage(
        sessionId: session.id,
        sessionType: session.type,
        liveAudioTurnCount: audio,
        liveTextMessageCount: text,
        liveImageUploadCount: images,
      );
    }

    var standardMessages = 0;
    var standardMedia = 0;
    for (final message in messages) {
      if (message.role != ConversationMessageRole.user) continue;
      switch (message.source) {
        case ConversationMessageSource.text:
        case ConversationMessageSource.audio:
          standardMessages++;
        case ConversationMessageSource.image:
        case ConversationMessageSource.file:
          standardMedia++;
      }
    }
    return ThreadUsage(
      sessionId: session.id,
      sessionType: session.type,
      standardMessageCount: standardMessages,
      standardMediaCount: standardMedia,
    );
  }
}

bool checkAccess(
  FeatureType feature, {
  DiagnosticSession? session,
  String? threadId,
  DiagnosticType? threadType,
}) =>
    SubscriptionService.instance.checkAccess(
      feature,
      session: session,
      threadId: threadId,
      threadType: threadType,
    );

Future<bool> ensureAccess(
  BuildContext context,
  FeatureType feature, {
  String? reason,
  DiagnosticSession? session,
  String? threadId,
  DiagnosticType? threadType,
}) {
  return SubscriptionService.instance.ensureAccess(
    context,
    feature,
    reason: reason,
    session: session,
    threadId: threadId,
    threadType: threadType,
  );
}
