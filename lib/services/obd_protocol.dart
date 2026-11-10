class ObdCommandResult {
  const ObdCommandResult({
    required this.command,
    required this.raw,
    this.numericValue,
    this.integerValue,
    this.textValue,
    this.codes = const [],
    this.isNoData = false,
    this.isStopped = false,
    this.isTimedOut = false,
    this.isAcknowledged = false,
  });

  final String command;
  final String raw;
  final double? numericValue;
  final int? integerValue;
  final String? textValue;
  final List<String> codes;
  final bool isNoData;
  final bool isStopped;
  final bool isTimedOut;
  final bool isAcknowledged;

  bool get hasValue =>
      numericValue != null ||
      integerValue != null ||
      (textValue?.isNotEmpty ?? false) ||
      codes.isNotEmpty;
}

abstract final class ObdProtocol {
  static const initCommands = <String>[
    'ATZ',
    'ATE0',
    'ATL0',
    'ATS0',
    'ATH0',
    'ATSP0',
  ];

  static const liveCommands = <String>['010C', '010D', '0105'];
  static const initSnapshotCommands = <String>[
    '0902',
    '03',
    '07',
    '0142',
    '0131',
    '0146',
  ];
  static const idleCommands = <String>['010C', '0111', '010B', '0106', '0107'];
  static const driveCommands = <String>['010C', '010D', '0104', '0110', '010E'];

  static String normalizeCommand(String command) =>
      command.trim().toUpperCase();

  static String normalizeFrameText(String frame) {
    final cleaned = frame.replaceAll('\r', '\n');
    final lines = cleaned
        .split('\n')
        .map((line) => line.trim().toUpperCase())
        .where((line) => line.isNotEmpty && line != '>')
        .toList();
    return lines.join(' | ');
  }

  static final _noisePattern = RegExp(
    r'^(SEARCHING|NO DATA|STOPPED|UNABLE TO CONNECT|BUS INIT|CAN ERROR|\?|AT)',
    caseSensitive: false,
  );

  static List<String> extractHexTokens(String frame) {
    final cleaned = frame.replaceAll('\r', '\n');
    final tokens = <String>[];

    for (final rawLine in cleaned.split('\n')) {
      var line = rawLine.trim().toUpperCase();
      if (line.isEmpty || line == '>') {
        continue;
      }
      if (_noisePattern.hasMatch(line)) {
        continue;
      }
      line = line.replaceFirst(RegExp(r'^[0-9A-F]+:'), '');
      line = line.replaceFirst(RegExp(r'^\s*01[0-9A-F]{2}\s*'), '');
      final compact = line.replaceAll(RegExp(r'[^0-9A-F]'), '');
      if (compact.length < 2 || compact.length.isOdd) {
        continue;
      }
      for (var index = 0; index < compact.length; index += 2) {
        tokens.add(compact.substring(index, index + 2));
      }
    }

    return tokens;
  }

  static ObdCommandResult parseResponse(
    String command,
    String frame,
  ) {
    final normalizedCommand = normalizeCommand(command);
    final raw = normalizeFrameText(frame);
    final upperFrame = frame.toUpperCase();
    final tokens = extractHexTokens(frame);

    if (upperFrame.contains('NO DATA')) {
      return ObdCommandResult(
        command: normalizedCommand,
        raw: raw.isEmpty ? 'NO DATA' : raw,
        isNoData: true,
      );
    }

    if (upperFrame.contains('STOPPED')) {
      return ObdCommandResult(
        command: normalizedCommand,
        raw: raw.isEmpty ? 'STOPPED' : raw,
        isStopped: true,
      );
    }

    if (upperFrame.contains('OK')) {
      return ObdCommandResult(
        command: normalizedCommand,
        raw: raw.isEmpty ? 'OK' : raw,
        isAcknowledged: true,
      );
    }

    if (normalizedCommand.startsWith('AT')) {
      return ObdCommandResult(
        command: normalizedCommand,
        raw: raw,
        isAcknowledged: raw.isNotEmpty,
      );
    }

    switch (normalizedCommand) {
      case '010C':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '0C', count: 2),
          numeric: (bytes) => ((bytes[0] * 256) + bytes[1]) / 4.0,
        );
      case '010D':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '0D', count: 1),
          integer: (bytes) => bytes[0],
        );
      case '0105':
      case '0146':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: normalizedCommand.substring(2), count: 1),
          numeric: (bytes) => bytes[0] - 40.0,
        );
      case '0104':
      case '0111':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: normalizedCommand.substring(2), count: 1),
          numeric: (bytes) => (bytes[0] * 100) / 255,
        );
      case '0106':
      case '0107':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: normalizedCommand.substring(2), count: 1),
          numeric: (bytes) => ((bytes[0] - 128) * 100) / 128,
        );
      case '010B':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '0B', count: 1),
          numeric: (bytes) => bytes[0].toDouble(),
        );
      case '010E':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '0E', count: 1),
          numeric: (bytes) => (bytes[0] / 2) - 64,
        );
      case '0110':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '10', count: 2),
          numeric: (bytes) => ((bytes[0] * 256) + bytes[1]) / 100,
        );
      case '0131':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '31', count: 2),
          integer: (bytes) => (bytes[0] * 256) + bytes[1],
        );
      case '0142':
        return _singleMetric(
          normalizedCommand,
          raw,
          _extractPidBytes(tokens, pid: '42', count: 2),
          numeric: (bytes) => ((bytes[0] * 256) + bytes[1]) / 1000,
        );
      case '03':
        return ObdCommandResult(
          command: normalizedCommand,
          raw: raw,
          codes: _extractDtcs(tokens, responseMode: '43'),
        );
      case '07':
        return ObdCommandResult(
          command: normalizedCommand,
          raw: raw,
          codes: _extractDtcs(tokens, responseMode: '47'),
        );
      case '0902':
        return ObdCommandResult(
          command: normalizedCommand,
          raw: raw,
          textValue: _extractVin(tokens),
        );
      default:
        return ObdCommandResult(
          command: normalizedCommand,
          raw: raw,
        );
    }
  }

  static ObdCommandResult _singleMetric(
    String command,
    String raw,
    List<int>? bytes, {
    double Function(List<int> bytes)? numeric,
    int Function(List<int> bytes)? integer,
  }) {
    if (bytes == null) {
      return ObdCommandResult(
        command: command,
        raw: raw,
      );
    }

    return ObdCommandResult(
      command: command,
      raw: raw,
      numericValue: numeric?.call(bytes),
      integerValue: integer?.call(bytes),
    );
  }

  static List<int>? _extractPidBytes(
    List<String> tokens, {
    required String pid,
    required int count,
  }) {
    final expectedFrameLen = 2 + count;

    for (var index = 0; index <= tokens.length - (count + 2); index++) {
      if (tokens[index] != '41' || tokens[index + 1] != pid) {
        continue;
      }

      if (index > 0) {
        final preceding = tokens[index - 1];
        final precedingValue = int.tryParse(preceding, radix: 16);
        if (precedingValue != null &&
            precedingValue > 0x1F &&
            preceding != '49' &&
            preceding != '43' &&
            preceding != '47') {
          continue;
        }
      }

      if (index + expectedFrameLen > tokens.length) {
        continue;
      }

      final values = <int>[];
      var valid = true;
      for (var offset = 0; offset < count; offset++) {
        final parsed = int.tryParse(tokens[index + 2 + offset], radix: 16);
        if (parsed == null) {
          valid = false;
          break;
        }
        values.add(parsed);
      }
      if (!valid) {
        continue;
      }
      return values;
    }
    return null;
  }

  static List<String> _extractDtcs(
    List<String> tokens, {
    required String responseMode,
  }) {
    final start = tokens.indexOf(responseMode);
    if (start == -1 || start + 2 >= tokens.length) {
      return const [];
    }

    final codes = <String>[];
    for (var index = start + 1; index + 1 < tokens.length; index += 2) {
      final first = int.tryParse(tokens[index], radix: 16);
      final second = int.tryParse(tokens[index + 1], radix: 16);
      if (first == null || second == null) {
        continue;
      }
      if (first == 0 && second == 0) {
        continue;
      }
      codes.add(_decodeDtc(first, second));
    }
    return codes;
  }

  static final _vinPattern = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');

  static String? _extractVin(List<String> tokens) {
    final vinBytes = <int>[];
    for (var index = 0; index <= tokens.length - 3; index++) {
      if (tokens[index] == '49' && tokens[index + 1] == '02') {
        var cursor = index + 3;
        while (cursor < tokens.length) {
          final isNextFrame = cursor <= tokens.length - 3 &&
              tokens[cursor] == '49' &&
              tokens[cursor + 1] == '02';
          if (isNextFrame) {
            break;
          }
          final value = int.tryParse(tokens[cursor], radix: 16);
          if (value != null && value >= 0x20) {
            vinBytes.add(value);
          }
          cursor += 1;
        }
      }
    }

    if (vinBytes.isEmpty) {
      return null;
    }

    final vin = String.fromCharCodes(vinBytes).trim();
    if (vin.isEmpty) {
      return null;
    }

    if (!_vinPattern.hasMatch(vin)) {
      return null;
    }

    return vin;
  }

  static String _decodeDtc(int firstByte, int secondByte) {
    const prefixes = ['P', 'C', 'B', 'U'];
    final prefix = prefixes[(firstByte & 0xC0) >> 6];
    final firstDigit = (firstByte & 0x30) >> 4;
    final secondDigit = firstByte & 0x0F;
    final thirdDigit = (secondByte & 0xF0) >> 4;
    final fourthDigit = secondByte & 0x0F;
    return '$prefix$firstDigit$secondDigit$thirdDigit$fourthDigit';
  }
}
