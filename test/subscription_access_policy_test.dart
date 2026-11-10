import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:fixease/config/app_config.dart';
import 'package:fixease/services/subscription_access_policy.dart';

void main() {
  final verifiedAt = DateTime.utc(2026, 11, 5, 12);

  EntitlementInfo entitlement({
    bool pass = false,
    bool active = true,
    DateTime? purchasedAt,
    String? expiry,
  }) =>
      EntitlementInfo(
        pass ? AppConfig.entitlementEmergencyId : AppConfig.entitlementProId,
        active,
        !pass,
        (purchasedAt ?? verifiedAt).toIso8601String(),
        (purchasedAt ?? verifiedAt).toIso8601String(),
        pass ? AppConfig.emergencyProductId : AppConfig.proProductId,
        false,
        expirationDate: expiry,
        verification: VerificationResult.verified,
      );

  CustomerInfo snapshot({
    EntitlementInfo? item,
    VerificationResult verification = VerificationResult.verified,
    DateTime? requestedAt,
  }) {
    final e = item ?? entitlement();
    return CustomerInfo(
      EntitlementInfos({e.identifier: e}, e.isActive ? {e.identifier: e} : {},
          verification: verification),
      const {},
      const [],
      const [],
      const [],
      verifiedAt.toIso8601String(),
      'test-customer',
      const {},
      (requestedAt ?? verifiedAt).toIso8601String(),
    );
  }

  SubscriptionAccess evaluate(CustomerInfo info, Duration offline) =>
      SubscriptionAccessPolicy.evaluate(info, verifiedAt.add(offline));

  test('verified cached Pro survives an offline refresh failure', () {
    final cached = snapshot(
        item: entitlement(
            expiry:
                verifiedAt.add(const Duration(days: 30)).toIso8601String()));
    expect(
        evaluate(cached, const Duration(days: 2)).tier, SubscriptionTier.pro);
    // A failed network call supplies no new CustomerInfo. Reusing the same
    // signed cache cannot lengthen its offline deadline.
    expect(
        evaluate(cached, const Duration(days: 3)).tier, SubscriptionTier.free);
  });

  test('a newly verified renewal starts a fresh bounded offline window', () {
    final renewed =
        snapshot(requestedAt: verifiedAt.add(const Duration(days: 2)));
    expect(
        evaluate(renewed, const Duration(days: 4)).tier, SubscriptionTier.pro);
    expect(
        evaluate(renewed, const Duration(days: 5)).tier, SubscriptionTier.free);
  });

  for (final verification in [
    VerificationResult.notRequested,
    VerificationResult.failed
  ]) {
    test('$verification cannot grant offline premium', () {
      expect(evaluate(snapshot(verification: verification), Duration.zero).tier,
          SubscriptionTier.free);
    });
  }

  test('Android cannot accept StoreKit on-device verification', () {
    final info = snapshot(verification: VerificationResult.verifiedOnDevice);
    expect(evaluate(info, Duration.zero).tier, SubscriptionTier.free);
    expect(
        SubscriptionAccessPolicy.evaluate(info, verifiedAt,
                allowDeviceVerification: true)
            .tier,
        SubscriptionTier.pro);
  });

  test('clock earlier than the signed server timestamp requires verification',
      () {
    expect(evaluate(snapshot(), const Duration(hours: -1)).tier,
        SubscriptionTier.free);
  });

  test('a verified revocation removes access despite future expiry', () {
    final revoked = snapshot(
        item: entitlement(
            active: false,
            expiry:
                verifiedAt.add(const Duration(days: 30)).toIso8601String()));
    expect(evaluate(revoked, Duration.zero).tier, SubscriptionTier.free);
  });

  test('revoked Emergency Pass cannot be revived from its purchase date', () {
    expect(
        evaluate(snapshot(item: entitlement(pass: true, active: false)),
                Duration.zero)
            .tier,
        SubscriptionTier.free);
  });

  test('non-expiring Emergency Pass remains limited to 48 hours', () {
    final pass = snapshot(item: entitlement(pass: true));
    expect(evaluate(pass, const Duration(hours: 47)).tier,
        SubscriptionTier.emergencyPass);
    expect(
        evaluate(pass, const Duration(hours: 48)).tier, SubscriptionTier.free);
  });

  test('Emergency Pass respects a shorter server expiry', () {
    final pass = snapshot(
        item: entitlement(
            pass: true,
            expiry:
                verifiedAt.add(const Duration(hours: 12)).toIso8601String()));
    expect(
        evaluate(pass, const Duration(hours: 12)).tier, SubscriptionTier.free);
  });

  test('reopening the app does not restart a 48-hour pass', () {
    final pass = snapshot(
        item: entitlement(
            pass: true,
            purchasedAt: verifiedAt.subtract(const Duration(hours: 49))));
    expect(evaluate(pass, Duration.zero).tier, SubscriptionTier.free);
  });

  test('malformed subscription expiry fails closed', () {
    expect(
        evaluate(snapshot(item: entitlement(expiry: 'invalid')), Duration.zero)
            .tier,
        SubscriptionTier.free);
  });
}
