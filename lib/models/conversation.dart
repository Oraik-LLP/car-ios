enum ConversationMessageRole { user, assistant }

enum ConversationMessageSource { text, audio, image, file }

class ConversationMessage {
  const ConversationMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentMimeType,
    this.source = ConversationMessageSource.text,
  });

  final String id;
  final ConversationMessageRole role;
  final String text;
  final DateTime createdAt;
  final String? attachmentPath;
  final String? attachmentName;
  final String? attachmentMimeType;
  final ConversationMessageSource source;

  bool get hasAttachment =>
      attachmentPath != null ||
      attachmentName != null ||
      source != ConversationMessageSource.text;

  String get previewText {
    if (text.trim().isNotEmpty) return text.trim();
    return switch (source) {
      ConversationMessageSource.audio => 'Voice note',
      ConversationMessageSource.image =>
        attachmentName?.trim().isNotEmpty == true
            ? 'Photo: $attachmentName'
            : 'Photo attached',
      ConversationMessageSource.file =>
        attachmentName?.trim().isNotEmpty == true
            ? 'File: $attachmentName'
            : 'File attached',
      ConversationMessageSource.text => 'Message',
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'created_at': createdAt.toIso8601String(),
        'attachment_path': attachmentPath,
        'attachment_name': attachmentName,
        'attachment_mime_type': attachmentMimeType,
        'source': source.name,
      };

  factory ConversationMessage.fromJson(Map<String, dynamic> json) {
    return ConversationMessage(
      id: json['id'] as String,
      role: ConversationMessageRole.values.byName(
        json['role'] as String? ?? ConversationMessageRole.user.name,
      ),
      text: json['text'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      attachmentPath: json['attachment_path'] as String?,
      attachmentName: json['attachment_name'] as String?,
      attachmentMimeType: json['attachment_mime_type'] as String?,
      source: ConversationMessageSource.values.byName(
        json['source'] as String? ?? ConversationMessageSource.text.name,
      ),
    );
  }
}

class ConversationThread {
  const ConversationThread({
    required this.sessionId,
    required this.vehicleId,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  final String sessionId;
  final String vehicleId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ConversationMessage> messages;

  ConversationThread copyWith({
    String? sessionId,
    String? vehicleId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ConversationMessage>? messages,
  }) {
    return ConversationThread(
      sessionId: sessionId ?? this.sessionId,
      vehicleId: vehicleId ?? this.vehicleId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  ConversationMessage? get latestMessage =>
      messages.isNotEmpty ? messages.last : null;

  String get previewText => latestMessage?.previewText ?? 'No messages yet';

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'vehicle_id': vehicleId,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ConversationThread.fromJson(Map<String, dynamic> json) {
    return ConversationThread(
      sessionId: json['session_id'] as String,
      vehicleId: json['vehicle_id'] as String,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
      messages: (json['messages'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => ConversationMessage.fromJson(
                  Map<String, dynamic>.from(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                ),
              )
              .toList() ??
          const [],
    );
  }
}

class ConversationAiResponse {
  const ConversationAiResponse({
    required this.text,
    required this.provider,
    required this.isFallback,
    this.requestSucceeded = false,
    this.errorCode,
  });

  final String text;
  final String provider;
  final bool isFallback;
  final bool requestSucceeded;
  final String? errorCode;

  ConversationAiResponse copyWith({
    String? text,
    String? provider,
    bool? isFallback,
    bool? requestSucceeded,
    String? errorCode,
  }) {
    return ConversationAiResponse(
      text: text ?? this.text,
      provider: provider ?? this.provider,
      isFallback: isFallback ?? this.isFallback,
      requestSucceeded: requestSucceeded ?? this.requestSucceeded,
      errorCode: errorCode ?? this.errorCode,
    );
  }

  factory ConversationAiResponse.fromJson(Map<String, dynamic> json) {
    return ConversationAiResponse(
      text: json['text'] as String? ?? '',
      provider: json['provider'] as String? ?? 'local',
      isFallback: json['is_fallback'] as bool? ?? false,
      requestSucceeded: false,
      errorCode: json['error_code'] as String?,
    );
  }
}
