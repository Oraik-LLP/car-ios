import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/ai_config.dart';
import '../models/ai_response.dart';
import '../models/conversation.dart';
import '../models/diagnostic.dart';
import '../models/obd.dart';
import '../models/vehicle.dart';
import 'device_identity_service.dart';
import 'subscription_service.dart';

/// Orchestrates AI diagnostic calls through the backend quota and AI proxy.
class AiService {
  AiService._();
  static final instance = AiService._();
  static const _retryDelay = Duration(seconds: 5);

  Future<AiDiagnosticResponse> analyzeSymptoms({
    required Vehicle vehicle,
    required List<String> symptoms,
    required Severity severity,
    String? description,
  }) async {
    if (!AiConfig.isConfigured) {
      throw Exception(
        'FixEase could not verify scan access because the backend is unavailable.',
      );
    }

    try {
      final payload = await _postJsonWithRetry(
        '/api/diagnose/symptoms',
        {
          'vehicle': _vehiclePayload(vehicle),
          'symptoms': symptoms,
          'severity': severity.name,
          'description': description,
        },
      );
      return AiDiagnosticResponse.fromJson(payload);
    } catch (_) {
      rethrow;
    }
  }

  Future<AiDiagnosticResponse> analyzePhotos({
    required Vehicle vehicle,
    required List<File> images,
    String? description,
    Map<String, dynamic>? obdContext,
  }) async {
    if (!AiConfig.isConfigured || images.isEmpty) {
      throw Exception(
        !AiConfig.isConfigured
            ? 'FixEase could not verify scan access because the backend is unavailable.'
            : 'At least one photo is required for diagnosis.',
      );
    }

    try {
      final payload = await _postJsonWithRetry(
        '/api/diagnose/photos',
        {
          'vehicle': _vehiclePayload(vehicle),
          'images': await _encodeFiles(images.take(8).toList()),
          'description': description,
          if (obdContext != null) 'obd_context': obdContext,
        },
      );
      return AiDiagnosticResponse.fromJson(payload);
    } catch (_) {
      rethrow;
    }
  }

  Future<AiDiagnosticResponse> analyzeInvoiceAudit({
    required Vehicle vehicle,
    required File document,
    String? purpose,
  }) async {
    if (!AiConfig.isConfigured) {
      throw Exception(
        'FixEase could not verify scan access because the backend is unavailable.',
      );
    }

    try {
      final payload = await _postJsonWithRetry(
        '/api/diagnose/invoice-audit',
        {
          'vehicle': _vehiclePayload(vehicle),
          'documents': await _encodeFiles([document]),
          'purpose': purpose,
        },
      );
      return AiDiagnosticResponse.fromJson(payload);
    } catch (_) {
      rethrow;
    }
  }

  Future<AiDiagnosticResponse> analyzeObdPro({
    required Vehicle vehicle,
    required ObdScanRecord record,
  }) async {
    if (!AiConfig.isConfigured) {
      throw Exception(
        'FixEase could not verify scan access because the backend is unavailable.',
      );
    }

    try {
      final staticSnapshot = Map<String, dynamic>.from(
        record.staticSnapshot.toJson(),
      )..remove('vin');
      final payload = await _postJsonWithRetry(
        '/api/diagnose/obd-pro',
        {
          'vehicle': _vehiclePayload(vehicle),
          'mode': record.kind.name,
          'is_partial': record.isPartial,
          'completion_reason': record.completionReason.name,
          'target_duration_seconds': record.targetDurationSeconds,
          'captured_duration_seconds': record.capturedDurationSeconds,
          'static_snapshot': staticSnapshot,
          'processed_scan': record.processedScan.toJson(),
        },
      );
      return AiDiagnosticResponse.fromJson(payload);
    } catch (_) {
      rethrow;
    }
  }

  Future<ConversationAiResponse> continueConversation({
    Vehicle? vehicle,
    required DiagnosticSession session,
    required List<ConversationMessage> history,
    String? message,
    File? audioFile,
    File? attachment,
  }) async {
    if (!AiConfig.isConfigured) {
      return const ConversationAiResponse(
        text:
            'The AI backend is not configured right now, so I cannot continue this conversation yet.',
        provider: 'local',
        isFallback: true,
        errorCode: 'backend_not_configured',
      );
    }

    try {
      final body = <String, dynamic>{
        'vehicle': _conversationVehiclePayload(vehicle, session),
        'session_context': _conversationSessionContext(session),
        'history': history
            .map(
              (item) => {
                'role': item.role.name,
                'text': item.previewText,
                'source': item.source.name,
              },
            )
            .toList(),
      };

      if (message != null && message.trim().isNotEmpty) {
        body['message'] = message.trim();
      }

      if (audioFile != null) {
        body['audio'] = await _encodeAudioFile(
          audioFile.path,
          mimeType: 'audio/wav',
        );
      }

      if (attachment != null) {
        final encoded = await _encodeFiles([attachment]);
        if (encoded.isNotEmpty) {
          body['attachment'] = encoded.first;
        }
      }

      final payload =
          await _postJsonWithRetry('/api/conversations/respond', body);
      return ConversationAiResponse.fromJson(payload).copyWith(
        requestSucceeded: true,
      );
    } catch (e) {
      return ConversationAiResponse(
        text:
            'I could not continue the conversation right now. Please try again.',
        provider: 'local',
        isFallback: true,
        errorCode: _extractErrorCode(e),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _encodeFiles(List<File> files) async {
    final encoded = <Map<String, dynamic>>[];
    for (final file in files) {
      final bytes = await _readPayloadBytes(file);
      final encodedAsJpeg = _isCompressibleImage(file.path);
      encoded.add({
        'name': encodedAsJpeg
            ? p.setExtension(p.basename(file.path), '.jpg')
            : p.basename(file.path),
        'mime_type': encodedAsJpeg ? 'image/jpeg' : _mimeTypeForPath(file.path),
        'data': await _encodeBase64(bytes),
      });
    }
    return encoded;
  }

  Future<Uint8List> _readPayloadBytes(File file) async {
    if (_isCompressibleImage(file.path)) {
      final compressed = await FlutterImageCompress.compressWithFile(
        file.absolute.path,
        minWidth: 1920,
        minHeight: 1080,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      if (compressed != null && compressed.isNotEmpty) {
        return compressed;
      }
    }
    return _readFileBytes(file.path);
  }

  bool _isCompressibleImage(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic');
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final deviceId = await DeviceIdentityService.getDeviceId();
    if (deviceId == null || deviceId.isEmpty) {
      throw Exception(
        'FixEase could not verify this device for scan access. Please restart the app and try again.',
      );
    }
    final encodedBody = await Isolate.run(() => jsonEncode(body));
    final resp = await http
        .post(
          AiConfig.endpoint(path),
          headers: {
            'Content-Type': 'application/json',
            ...await SubscriptionService.instance.backendEntitlementHeaders(),
            'x-fixease-device-id': deviceId,
          },
          body: encodedBody,
        )
        .timeout(const Duration(seconds: 90));

    final payload = await _parseJsonMap(resp.body);

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return payload;
    }

    final message = payload['message'] as String? ?? 'AI request failed';
    final code = payload['error_code'] as String? ?? 'request_failed';
    throw AiRequestException(code, message);
  }

  Future<Map<String, dynamic>> _postJsonWithRetry(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      return await _postJson(path, body);
    } catch (_) {
      await Future<void>.delayed(_retryDelay);
      return _postJson(path, body);
    }
  }

  Future<Map<String, dynamic>> _encodeAudioFile(
    String path, {
    required String mimeType,
  }) async {
    final data = await Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      return base64Encode(bytes);
    });
    return {
      'data': data,
      'mimeType': mimeType,
    };
  }

  Future<Uint8List> _readFileBytes(String path) async {
    return Isolate.run(() => File(path).readAsBytesSync());
  }

  Future<String> _encodeBase64(Uint8List bytes) async {
    return Isolate.run(() => base64Encode(bytes));
  }

  Future<Map<String, dynamic>> _parseJsonMap(String raw) async {
    if (raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = await Isolate.run(
      () => jsonDecode(raw) as Map<String, dynamic>,
    );
    return Map<String, dynamic>.from(decoded);
  }


  Map<String, dynamic> _vehiclePayload(Vehicle vehicle) => {
        'display_name': vehicle.displayName,
        'fuel_label': vehicle.fuelLabel,
        'mileage_km': vehicle.mileageKm,
        'last_service_date': vehicle.lastServiceDate?.toIso8601String(),
      };

  Map<String, dynamic> _conversationVehiclePayload(
    Vehicle? vehicle,
    DiagnosticSession session,
  ) =>
      {
        'display_name':
            vehicle?.displayName ?? session.vehicleName ?? 'Unknown vehicle',
        'fuel_label': vehicle?.fuelLabel ?? 'Unknown',
        'mileage_km': vehicle?.mileageKm ?? 0,
        'last_service_date': vehicle?.lastServiceDate?.toIso8601String(),
      };

  Map<String, dynamic> _conversationSessionContext(DiagnosticSession session) =>
      {
        'session_id': session.id,
        'session_type': session.type.name,
        'session_title': session.typeTitle,
        'vehicle_name': session.vehicleName,
        'created_at': session.createdAt.toIso8601String(),
        'severity': session.severity.name,
        'description': session.description,
        'symptoms': session.symptoms,
        'image_urls': session.imageUrls,
        'diagnosis_summary': session.aiResponse,
        'diagnosis_json': session.aiResponseJson,
      };

  String? _extractErrorCode(Object error) {
    if (error is AiRequestException) return error.code;
    return null;
  }
}

class AiRequestException implements Exception {
  const AiRequestException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}
