enum AttachmentKind { note, image, file }

AttachmentKind attachmentKindFromValue(String value) {
  return AttachmentKind.values.firstWhere(
    (AttachmentKind kind) => kind.name == value,
    orElse: () => AttachmentKind.note,
  );
}

class ChatAttachment {
  const ChatAttachment({
    required this.id,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.sizeBytes,
    required this.previewText,
    required this.createdAt,
    this.localPath,
    this.base64Data,
    this.thumbnailBase64,
  });

  factory ChatAttachment.fromJson(Map<String, dynamic> json) {
    return ChatAttachment(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Attachment',
      kind: attachmentKindFromValue(json['kind'] as String? ?? 'note'),
      mimeType: json['mimeType'] as String? ?? 'text/plain',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      previewText: json['previewText'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      localPath: _readOptionalString(json['localPath']),
      base64Data: _readOptionalString(json['base64Data']) ??
          _readOptionalString(json['data']),
      thumbnailBase64: _readOptionalString(json['thumbnailBase64']),
    );
  }

  final String id;
  final String name;
  final AttachmentKind kind;
  final String mimeType;
  final int sizeBytes;
  final String previewText;
  final DateTime createdAt;
  final String? localPath;
  final String? base64Data;
  final String? thumbnailBase64;

  bool get isImage => kind == AttachmentKind.image;

  bool get isFile => kind == AttachmentKind.file;

  bool get hasLocalPath => localPath != null && localPath!.trim().isNotEmpty;

  bool get hasBase64Data => base64Data != null && base64Data!.trim().isNotEmpty;

  bool get isWebStored => hasBase64Data && !hasLocalPath;

  bool get hasThumbnail =>
      thumbnailBase64 != null && thumbnailBase64!.trim().isNotEmpty;

  ChatAttachment copyWith({
    String? id,
    String? name,
    AttachmentKind? kind,
    String? mimeType,
    int? sizeBytes,
    String? previewText,
    DateTime? createdAt,
    String? localPath,
    bool clearLocalPath = false,
    String? base64Data,
    bool clearBase64Data = false,
    String? thumbnailBase64,
    bool clearThumbnailBase64 = false,
  }) {
    return ChatAttachment(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      previewText: previewText ?? this.previewText,
      createdAt: createdAt ?? this.createdAt,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      base64Data: clearBase64Data ? null : (base64Data ?? this.base64Data),
      thumbnailBase64: clearThumbnailBase64
          ? null
          : (thumbnailBase64 ?? this.thumbnailBase64),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'kind': kind.name,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'previewText': previewText,
      'createdAt': createdAt.toIso8601String(),
      if (localPath != null && localPath!.isNotEmpty) 'localPath': localPath,
      if (base64Data != null && base64Data!.isNotEmpty)
        'base64Data': base64Data,
      if (thumbnailBase64 != null && thumbnailBase64!.isNotEmpty)
        'thumbnailBase64': thumbnailBase64,
    };
  }

  static String? _readOptionalString(Object? value) {
    if (value is! String) {
      return null;
    }

    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : value;
  }
}
