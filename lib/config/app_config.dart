/// Global app configuration for monetization, legal links, and support.
abstract final class AppConfig {
  static const bool isDemoMode = bool.fromEnvironment(
    'FIXEASE_DEMO_MODE',
    defaultValue: true,
  );

  static const supportEmail = 'support@oraik.co';
  static const termsUrl = 'https://oraik.co/terms';
  static const privacyUrl = 'https://oraik.co/privacy';
  static const aboutUrl = 'https://oraik.co';

  static const revenueCatAndroidApiKey = String.fromEnvironment(
    'REVENUECAT_ANDROID_API_KEY',
    defaultValue: 'demo_android_rc_key',
  );
  static const revenueCatIosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_API_KEY',
    defaultValue: 'demo_ios_rc_key',
  );

  static const offeringId = 'default';
  static const emergencyProductId = 'fixease_emergency_pass';
  static const proProductId = 'fixease_pro_driver_monthly';
  static const entitlementEmergencyId = 'ENTITLEMENT_EMERGENCY';
  static const entitlementProId = 'ENTITLEMENT_PRO';

  static const emergencyDemoPrice = '\$2.99';
  static const proDemoPrice = '\$4.99';

  static const freeDiagnosticsPerMonth = 3;
  static const freePdfReportsPerMonth = 2;
}
