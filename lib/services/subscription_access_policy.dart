import 'package:purchases_flutter/purchases_flutter.dart';

import '../config/app_config.dart';

enum SubscriptionTier { free, emergencyPass, pro }

class SubscriptionAccess {
  const SubscriptionAccess(this.tier, {this.validUntil, this.message});

  final SubscriptionTier tier;
  final DateTime? validUntil;
  final String? message;
}

/// Reads only RevenueCat's signature-verified CustomerInfo. No paid flag is
/// restored from the app's editable preferences. The native SDK owns its cache.
abstract final class SubscriptionAccessPolicy {
  static const offlineGrace = Duration(days: 3);
  static const clockTolerance = Duration(minutes: 5);

  static bool isTrusted(CustomerInfo info,
      {bool allowDeviceVerification = false}) {
    final verification = info.entitlements.verification;
    return verification == VerificationResult.verified ||
        (allowDeviceVerification &&
            verification == VerificationResult.verifiedOnDevice);
  }

  static SubscriptionAccess evaluate(
    CustomerInfo info,
    DateTime now, {
    bool allowDeviceVerification = false,
  }) {
    if (!isTrusted(info, allowDeviceVerification: allowDeviceVerification)) {
      return const SubscriptionAccess(SubscriptionTier.free,
          message:
              'Connect to the internet to securely verify your purchases.');
    }
    final requestedAt = DateTime.tryParse(info.requestDate)?.toUtc();
    now = now.toUtc();
    if (requestedAt == null ||
        now.isBefore(requestedAt.subtract(clockTolerance))) {
      return const SubscriptionAccess(SubscriptionTier.free,
          message:
              'Check your device date and connect to verify your purchases.');
    }

    final offlineDeadline = requestedAt.add(offlineGrace);
    final pro = info.entitlements.active[AppConfig.entitlementProId];
    if (pro != null &&
        pro.isActive &&
        pro.verification != VerificationResult.failed) {
      var deadline = offlineDeadline;
      if (pro.expirationDate != null) {
        final expires = DateTime.tryParse(pro.expirationDate!)?.toUtc();
        if (expires == null) {
          return const SubscriptionAccess(SubscriptionTier.free,
              message: 'Connect to refresh your subscription expiry.');
        }
        final renewalGrace = expires.add(offlineGrace);
        if (renewalGrace.isBefore(deadline)) deadline = renewalGrace;
      }
      if (now.isBefore(deadline)) {
        return SubscriptionAccess(SubscriptionTier.pro, validUntil: deadline);
      }
      return const SubscriptionAccess(SubscriptionTier.free,
          message:
              'Connect to refresh your paid access after three days offline.');
    }

    final pass = info.entitlements.active[AppConfig.entitlementEmergencyId];
    if (pass != null &&
        pass.isActive &&
        pass.verification != VerificationResult.failed) {
      final purchasedAt = DateTime.tryParse(pass.latestPurchaseDate)?.toUtc();
      if (purchasedAt == null) {
        return const SubscriptionAccess(SubscriptionTier.free,
            message: 'Connect to verify your Emergency Pass purchase.');
      }
      // A non-expiring store entitlement must never turn a 48-hour pass into
      // lifetime access. A revoked/inactive entitlement never reaches here.
      var deadline = purchasedAt.add(const Duration(hours: 48));
      if (pass.expirationDate != null) {
        final expires = DateTime.tryParse(pass.expirationDate!)?.toUtc();
        if (expires == null) {
          return const SubscriptionAccess(SubscriptionTier.free);
        }
        if (expires.isBefore(deadline)) deadline = expires;
      }
      if (offlineDeadline.isBefore(deadline)) deadline = offlineDeadline;
      if (now.isBefore(deadline)) {
        return SubscriptionAccess(SubscriptionTier.emergencyPass,
            validUntil: deadline);
      }
    }
    return const SubscriptionAccess(SubscriptionTier.free);
  }
}
