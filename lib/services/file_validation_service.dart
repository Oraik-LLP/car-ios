import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

class FileValidationResult {
  const FileValidationResult._({
    required this.isValid,
    this.mimeType,
    this.message,
    this.fileSizeBytes = 0,
  });

  const FileValidationResult.valid({
    required String mimeType,
    required int fileSizeBytes,
  }) : this._(
          isValid: true,
          mimeType: mimeType,
          fileSizeBytes: fileSizeBytes,
        );

  const FileValidationResult.invalid(String message)
      : this._(
          isValid: false,
          message: message,
        );

  final bool isValid;
  final String? mimeType;
  final String? message;
  final int fileSizeBytes;
}

abstract final class FileValidationService {
  static const int maxUploadBytes = 10 * 1024 * 1024;

  static const Set<String> _photoMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
  };

  static const Set<String> _invoiceMimeTypes = {
    ..._photoMimeTypes,
    'application/pdf',
  };

  static Future<FileValidationResult> validatePhoto(File file) {
    return _validate(
      file,
      allowedMimeTypes: _photoMimeTypes,
      allowedLabel: 'JPG, PNG, WebP, or HEIC images',
    );
  }

  static Future<FileValidationResult> validateInvoiceDocument(File file) {
    return _validate(
      file,
      allowedMimeTypes: _invoiceMimeTypes,
      allowedLabel: 'PDF, JPG, PNG, WebP, or HEIC files',
    );
  }

  static Future<FileValidationResult> _validate(
    File file, {
    required Set<String> allowedMimeTypes,
    required String allowedLabel,
  }) async {
    if (!await file.exists()) {
      return const FileValidationResult.invalid(
        'The selected file is no longer available on this device.',
      );
    }

    final fileSizeBytes = await file.length();
    if (fileSizeBytes <= 0) {
      return const FileValidationResult.invalid(
        'The selected file is empty or corrupted.',
      );
    }

    if (fileSizeBytes > maxUploadBytes) {
      return const FileValidationResult.invalid(
        'Files larger than 10 MB are not supported.',
      );
    }

    final mimeType = await detectMimeType(file.path);
    if (mimeType == null || !allowedMimeTypes.contains(mimeType)) {
      return FileValidationResult.invalid(
        'Unsupported file type. Please upload $allowedLabel only.',
      );
    }

    return FileValidationResult.valid(
      mimeType: mimeType,
      fileSizeBytes: fileSizeBytes,
    );
  }

  static Future<String?> detectMimeType(String path) async {
    return Isolate.run(() {
      final file = File(path);
      if (!file.existsSync()) return null;

      final raf = file.openSync(mode: FileMode.read);
      try {
        final header = Uint8List.fromList(raf.readSync(32));
        return _mimeTypeFromHeader(header);
      } finally {
        raf.closeSync();
      }
    });
  }

  static String? _mimeTypeFromHeader(Uint8List header) {
    if (_matches(header, [0x25, 0x50, 0x44, 0x46, 0x2D])) {
      return 'application/pdf';
    }
    if (_matches(header, [0xFF, 0xD8, 0xFF])) {
      return 'image/jpeg';
    }
    if (_matches(header, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (header.length >= 12 &&
        _ascii(header, 0, 4) == 'RIFF' &&
        _ascii(header, 8, 4) == 'WEBP') {
      return 'image/webp';
    }
    if (header.length >= 12 && _ascii(header, 4, 4) == 'ftyp') {
      final brand = _ascii(header, 8, 4).toLowerCase();
      const heicBrands = {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
      };
      if (heicBrands.contains(brand)) {
        return 'image/heic';
      }
    }
    return null;
  }

  static bool _matches(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  static String _ascii(Uint8List bytes, int start, int length) {
    if (bytes.length < start + length) return '';
    return String.fromCharCodes(bytes.sublist(start, start + length));
  }
}
