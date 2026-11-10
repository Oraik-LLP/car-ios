class ObdErrorInfo {
  const ObdErrorInfo({
    required this.code,
    required this.message,
    required this.nextStep,
  });

  final String code;
  final String message;
  final String nextStep;
}

abstract final class ObdErrorMapper {
  static ObdErrorInfo from(Object error) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('permission') || raw.contains('denied')) {
      return const ObdErrorInfo(
        code: 'OBD_BT_PERMISSION_DENIED',
        message: 'Bluetooth permission is not available.',
        nextStep: 'Allow Nearby devices in Android Settings, then reconnect.',
      );
    }
    if (raw.contains('not paired') ||
        raw.contains('device not found') ||
        raw.contains('no device')) {
      return const ObdErrorInfo(
        code: 'OBD_ADAPTER_NOT_PAIRED',
        message: 'FixEase could not find the selected adapter.',
        nextStep:
            'Pair the OBD-II adapter in Android Bluetooth settings, then refresh.',
      );
    }
    if (raw.contains('timeout') || raw.contains('timed out')) {
      return const ObdErrorInfo(
        code: 'OBD_ADAPTER_TIMEOUT',
        message: 'The OBD-II adapter did not respond in time.',
        nextStep: 'Check vehicle power and adapter pairing, then reconnect.',
      );
    }
    if (raw.contains('socket') ||
        raw.contains('read failed') ||
        raw.contains('closed') ||
        raw.contains('disconnected')) {
      return const ObdErrorInfo(
        code: 'OBD_BLUETOOTH_LINK_LOST',
        message: 'The Bluetooth link to the adapter was interrupted.',
        nextStep:
            'Keep the adapter powered and reconnect. Any captured scan data is saved locally.',
      );
    }
    if (raw.contains('adapter did not accept')) {
      return const ObdErrorInfo(
        code: 'OBD_ADAPTER_REJECTED',
        message: 'The adapter refused the connection.',
        nextStep:
            'Confirm it is an ELM327-compatible adapter and is not connected to another app.',
      );
    }
    return const ObdErrorInfo(
      code: 'OBD_CONNECTION_FAILED',
      message: 'FixEase could not connect to the OBD-II adapter.',
      nextStep:
          'Check Bluetooth, adapter power, and vehicle ignition, then try again.',
    );
  }
}
