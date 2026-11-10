import 'package:ntp/ntp.dart';

class TrustedTimeService {
  TrustedTimeService._();
  static final TrustedTimeService instance = TrustedTimeService._();
  static const _timeout = Duration(seconds: 4);

  Future<DateTime?> fetchUtcNow() async {
    try {
      final now = await NTP.now(timeout: _timeout);
      return now.toUtc();
    } catch (_) {
      return null;
    }
  }
}
