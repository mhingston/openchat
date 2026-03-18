import 'package:flutter_test/flutter_test.dart';

import 'package:openchat/src/models/attachment.dart';

void main() {
  group('ChatAttachment', () {
    test('preserves new attachment fields in JSON', () {
      final DateTime createdAt = DateTime.parse('2026-03-16T12:00:00.000Z');
      final ChatAttachment attachment = ChatAttachment(
        id: 'attachment-1',
        name: 'photo.png',
        kind: AttachmentKind.image,
        mimeType: 'image/png',
        sizeBytes: 42,
        previewText: 'Image • 42 B',
        createdAt: createdAt,
        localPath: '/tmp/photo.png',
        base64Data: 'YWJj',
      );

      final Map<String, dynamic> json = attachment.toJson();
      final ChatAttachment decoded = ChatAttachment.fromJson(json);

      expect(decoded.localPath, '/tmp/photo.png');
      expect(decoded.base64Data, 'YWJj');
      expect(decoded.kind, AttachmentKind.image);
      expect(decoded.createdAt, createdAt);
    });

    test('remains backward compatible with legacy JSON payloads', () {
      final ChatAttachment decoded = ChatAttachment.fromJson(
        <String, dynamic>{
          'id': 'attachment-legacy',
          'name': 'Reference note',
          'kind': 'note',
          'mimeType': 'text/plain',
          'sizeBytes': 14,
          'previewText': 'Legacy preview',
          'createdAt': '2026-03-16T12:00:00.000Z',
        },
      );

      expect(decoded.kind, AttachmentKind.note);
      expect(decoded.localPath, isNull);
      expect(decoded.base64Data, isNull);
      expect(decoded.previewText, 'Legacy preview');
    });
  });
}
