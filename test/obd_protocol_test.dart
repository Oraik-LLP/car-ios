import 'package:fixease/services/obd_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ObdProtocol', () {
    test('extractHexTokens skips noise and normalizes lines correctly', () {
      const frame = '''
SEARCHING...
UNABLE TO CONNECT
?
>
010C
  41 0C 1A F8 
>
''';
      final tokens = ObdProtocol.extractHexTokens(frame);
      expect(tokens, ['41', '0C', '1A', 'F8']);
    });

    test('extractHexTokens skips ISO 15765 frame counters', () {
      const frame = '''
0: 41 0C 1A F8
1: 41 0C 1A F8
''';
      final tokens = ObdProtocol.extractHexTokens(frame);
      // The single-frame response shouldn't have counters, 
      // but if an ELM adds them, ensuring the '0:' or '1:' prefix is stripped out.
      expect(tokens, [
        '41', '0C', '1A', 'F8', 
        '41', '0C', '1A', 'F8',
      ]);
    });

    test('parseResponse handles clean 010C RPM data', () {
      const frame = '41 0C 1A F8 \r\r>';
      final result = ObdProtocol.parseResponse('010C', frame);

      expect(result.command, '010C');
      expect(result.numericValue, ((0x1A * 256) + 0xF8) / 4.0); // 1726.0 rpm
      expect(result.isNoData, false);
      expect(result.isStopped, false);
    });

    test('parseResponse handles clean 010D Speed data', () {
      const frame = '41 0D 32 \r\r>';
      final result = ObdProtocol.parseResponse('010D', frame);

      expect(result.command, '010D');
      expect(result.integerValue, 0x32); // 50 km/h
      expect(result.isNoData, false);
      expect(result.isStopped, false);
    });

    test('parseResponse safely rejects echoed command fragments', () {
      const frame = '01 0C \r 41 \r >';
      final result = ObdProtocol.parseResponse('010C', frame);

      expect(result.numericValue, isNull);
    });

    test('parseResponse parses Mode 0902 VIN cleanly across multiple lines', () {
      const frame = '''
014 
0: 49 02 01 31 48 47 
1: 43 4D 38 32 36 33 33 
2: 41 30 34 36 39 36 35 
>''';
      final result = ObdProtocol.parseResponse('0902', frame);

      expect(result.command, '0902');
      // 31 48 47 43 4D 38 32 36 33 33 41 30 34 36 39 36 35
      // 1  H  G  C  M  8  2  6  3  3  A  0  4  6  9  6  5
      expect(result.textValue, '1HGCM82633A046965');
    });

    test('parseResponse rejects malformed or truncated VINs', () {
      const frame = '''
014 
0: 49 02 01 31 48 47 
1: 43 4D
>''';
      // Less than 17 chars, validation should fail and return null.
      final result = ObdProtocol.parseResponse('0902', frame);
      expect(result.textValue, isNull);
    });

    test('parseResponse correctly extracts STOPPED and NO DATA flags', () {
      expect(
        ObdProtocol.parseResponse('010C', 'STOPPED\r\r>').isStopped,
        isTrue,
      );

      expect(
        ObdProtocol.parseResponse('010D', 'NO DATA\r\r>').isNoData,
        isTrue,
      );
    });

    test('parseResponse bounds checks ensure payload is not read from unexpected hex', () {
      const frame = '''
88 99 41 0C AA BB
''';
      // The "41 0C" shouldn't be read because it's preceded by non-standard data bytes ("88 99")
      // that don't look like a standard CAN-TP length or response index.
      final result = ObdProtocol.parseResponse('010C', frame);
      expect(result.numericValue, isNull);
    });
  });
}
