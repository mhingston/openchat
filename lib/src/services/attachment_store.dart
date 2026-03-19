import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

import '../models/attachment.dart';
import 'attachment_store_local.dart' as local_store;

class UnsupportedAttachmentException implements Exception {
  const UnsupportedAttachmentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AttachmentStore {
  AttachmentStore._({
    required this.localStoragePath,
    ImagePicker? imagePicker,
    Future<XFile?> Function(ImageSource source)? pickImage,
    Future<FilePickerResult?> Function()? pickFile,
  })  : _imagePicker = imagePicker ?? ImagePicker(),
        _pickImage = pickImage,
        _pickFile = pickFile;

  factory AttachmentStore.memory({
    ImagePicker? imagePicker,
    Future<XFile?> Function(ImageSource source)? pickImage,
    Future<FilePickerResult?> Function()? pickFile,
  }) {
    return AttachmentStore._(
      localStoragePath: null,
      imagePicker: imagePicker,
      pickImage: pickImage,
      pickFile: pickFile,
    );
  }

  static Future<AttachmentStore> create({ImagePicker? imagePicker}) async {
    if (kIsWeb) {
      return AttachmentStore._(
        localStoragePath: null,
        imagePicker: imagePicker,
      );
    }

    final String storagePath =
        await local_store.createAttachmentStoragePath('openchat');
    return AttachmentStore._(
      localStoragePath: storagePath,
      imagePicker: imagePicker,
    );
  }

  final String? localStoragePath;
  final ImagePicker _imagePicker;
  final Future<XFile?> Function(ImageSource source)? _pickImage;
  final Future<FilePickerResult?> Function()? _pickFile;

  Future<ChatAttachment?> pickImageFromCamera() async {
    if (kIsWeb) {
      throw const UnsupportedAttachmentException(
        'Camera capture is not available in the web preview yet. Use Photos or Files instead.',
      );
    }

    final XFile? file = await _resolveImagePicker()(ImageSource.camera);
    if (file == null) {
      return null;
    }

    return importImageFile(file, source: 'camera');
  }

  Future<ChatAttachment?> pickImageFromGallery() async {
    final XFile? file = await _resolveImagePicker()(ImageSource.gallery);
    if (file == null) {
      return null;
    }

    return importImageFile(file, source: 'gallery');
  }

  Future<ChatAttachment?> pickFile() async {
    final FilePickerResult? result = await _resolveFilePicker()();
    if (result == null || result.files.isEmpty) {
      return null;
    }

    return importPlatformFile(result.files.single);
  }

  Future<ChatAttachment> importImageFile(
    XFile file, {
    String source = 'image',
  }) async {
    final List<int> rawBytes = await file.readAsBytes();
    final String name = file.name.trim().isEmpty
        ? 'image-${DateTime.now().millisecondsSinceEpoch}.jpg'
        : file.name.trim();

    final String originalMime = _detectMimeType(name, rawBytes, AttachmentKind.image);
    final (Uint8List finalBytes, String finalMime) =
        await _compressImage(Uint8List.fromList(rawBytes), originalMime);

    // Use final (possibly compressed) name with correct extension
    final String finalName = finalMime == 'image/jpeg' && !name.toLowerCase().endsWith('.jpg') && !name.toLowerCase().endsWith('.jpeg')
        ? '${name.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg'
        : name;

    return _buildAttachment(
      name: finalName,
      bytes: finalBytes,
      forcedKind: AttachmentKind.image,
      forcedMime: finalMime,
      previewText: _buildImagePreviewText(
        source: source,
        sizeBytes: finalBytes.length,
      ),
    );
  }

  Future<ChatAttachment> importPlatformFile(PlatformFile file) async {
    final String name =
        file.name.trim().isEmpty ? 'attachment' : file.name.trim();
    List<int>? bytes = file.bytes;

    if (bytes == null && file.path != null && file.path!.trim().isNotEmpty) {
      bytes = await local_store.readAttachmentBytes(file.path!);
    }

    if (bytes == null) {
      throw UnsupportedAttachmentException(
        'Could not read the file "$name" from the current platform picker.',
      );
    }

    final String mimeType = _detectMimeType(name, bytes, null);
    final AttachmentKind kind = mimeType.startsWith('image/')
        ? AttachmentKind.image
        : AttachmentKind.file;

    List<int> finalBytes = bytes;
    String finalMime = mimeType;
    String finalName = name;

    if (kind == AttachmentKind.image) {
      final (Uint8List compressed, String compressedMime) =
          await _compressImage(Uint8List.fromList(bytes), mimeType);
      finalBytes = compressed;
      finalMime = compressedMime;
      if (compressedMime == 'image/jpeg' &&
          !name.toLowerCase().endsWith('.jpg') &&
          !name.toLowerCase().endsWith('.jpeg')) {
        finalName = '${name.replaceAll(RegExp(r'\.[^.]+$'), '')}.jpg';
      }
    }

    return _buildAttachment(
      name: finalName,
      bytes: finalBytes,
      forcedKind: kind,
      forcedMime: finalMime,
      previewText: _buildFilePreviewText(
        fileName: finalName,
        mimeType: finalMime,
        bytes: finalBytes,
        sizeBytes: finalBytes.length,
      ),
    );
  }

  Future<void> deleteAttachment(ChatAttachment attachment) async {
    final String? localPath = attachment.localPath;
    if (localPath == null || localPath.trim().isEmpty) {
      return;
    }

    await local_store.deleteAttachmentFile(localPath);
  }

  Future<String> toImageDataUrl(ChatAttachment attachment) async {
    if (!attachment.isImage) {
      throw const UnsupportedAttachmentException(
        'Only image attachments can be sent as image content.',
      );
    }

    final String base64Data = await readBase64Data(attachment);
    final String imageMime = attachment.mimeType.startsWith('image/')
        ? attachment.mimeType
        : 'image/jpeg';
    return 'data:$imageMime;base64,$base64Data';
  }

  Future<String> readBase64Data(ChatAttachment attachment) async {
    if (attachment.hasBase64Data) {
      return attachment.base64Data!;
    }

    final String? localPath = attachment.localPath;
    if (localPath == null || localPath.trim().isEmpty) {
      throw UnsupportedAttachmentException(
        'The attachment "${attachment.name}" is missing file data.',
      );
    }

    if (!await local_store.attachmentFileExists(localPath)) {
      throw UnsupportedAttachmentException(
        'The attachment "${attachment.name}" could not be found on disk.',
      );
    }

    final List<int> bytes = await local_store.readAttachmentBytes(localPath);
    return base64Encode(bytes);
  }

  Future<String> readTextFile(ChatAttachment attachment) async {
    if (!_isReadableTextMime(attachment.mimeType, attachment.name)) {
      throw UnsupportedAttachmentException(
        'The file "${attachment.name}" is not a supported text attachment.',
      );
    }

    if (attachment.hasBase64Data) {
      try {
        return utf8.decode(base64Decode(attachment.base64Data!));
      } on FormatException {
        throw UnsupportedAttachmentException(
          'The file "${attachment.name}" could not be decoded as UTF-8 text.',
        );
      }
    }

    final String? localPath = attachment.localPath;
    if (localPath == null || localPath.trim().isEmpty) {
      throw UnsupportedAttachmentException(
        'The file "${attachment.name}" is missing local file data.',
      );
    }

    if (!await local_store.attachmentFileExists(localPath)) {
      throw UnsupportedAttachmentException(
        'The file "${attachment.name}" could not be found on disk.',
      );
    }

    try {
      return await local_store.readAttachmentText(localPath);
    } on FormatException {
      throw UnsupportedAttachmentException(
        'The file "${attachment.name}" could not be decoded as UTF-8 text.',
      );
    }
  }

  Future<ChatAttachment> _buildAttachment({
    required String name,
    required List<int> bytes,
    required AttachmentKind forcedKind,
    required String previewText,
    String? forcedMime,
  }) async {
    final String mimeType = forcedMime ?? _detectMimeType(name, bytes, forcedKind);
    final AttachmentKind kind =
        forcedKind == AttachmentKind.file && mimeType.startsWith('image/')
            ? AttachmentKind.image
            : forcedKind;
    final DateTime createdAt = DateTime.now();
    final String id = 'attachment-${createdAt.microsecondsSinceEpoch}';

    if (kIsWeb || localStoragePath == null || localStoragePath!.isEmpty) {
      return ChatAttachment(
        id: id,
        name: name,
        kind: kind,
        mimeType: mimeType,
        sizeBytes: bytes.length,
        previewText: previewText,
        createdAt: createdAt,
        base64Data: base64Encode(bytes),
      );
    }

    final String safeName = _sanitizeFileName(name);
    final String storedPath = await local_store.writeAttachmentFile(
      directoryPath: localStoragePath!,
      fileName:
          '${createdAt.microsecondsSinceEpoch}_${safeName.isEmpty ? 'attachment' : safeName}',
      bytes: bytes,
    );

    String? thumbnailBase64;
    if (kind == AttachmentKind.image) {
      thumbnailBase64 = await _generateThumbnailBase64(bytes);
    }

    return ChatAttachment(
      id: id,
      name: name,
      kind: kind,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      previewText: previewText,
      createdAt: createdAt,
      localPath: storedPath,
      thumbnailBase64: thumbnailBase64,
    );
  }

  Future<XFile?> Function(ImageSource source) _resolveImagePicker() {
    return _pickImage ??
        (ImageSource source) => _imagePicker.pickImage(source: source);
  }

  Future<FilePickerResult?> Function() _resolveFilePicker() {
    return _pickFile ??
        () => FilePicker.platform.pickFiles(
              allowMultiple: false,
              withData: true,
              type: FileType.any,
            );
  }

  String _detectMimeType(
    String name,
    List<int> bytes,
    AttachmentKind? forcedKind,
  ) {
    final String? mimeType =
        lookupMimeType(name, headerBytes: bytes.take(32).toList());
    if (mimeType != null && mimeType.trim().isNotEmpty) {
      return mimeType;
    }

    return _fallbackMimeType(name, forcedKind: forcedKind);
  }

  String _fallbackMimeType(
    String fileName, {
    AttachmentKind? forcedKind,
  }) {
    final String extension = _fileExtension(fileName);
    if (forcedKind == AttachmentKind.image) {
      if (extension.isEmpty) {
        return 'image/jpeg';
      }
      return 'image/$extension';
    }

    if (_isReadableTextMime('text/plain', fileName)) {
      return 'text/plain';
    }

    return 'application/octet-stream';
  }

  String _buildImagePreviewText({
    required String source,
    required int sizeBytes,
  }) {
    final String sourceLabel = switch (source) {
      'camera' => 'Camera image',
      'gallery' => 'Photo',
      _ => 'Image',
    };
    return '$sourceLabel • ${_formatSize(sizeBytes)}';
  }

  String _buildFilePreviewText({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    required int sizeBytes,
  }) {
    if (mimeType.startsWith('image/')) {
      return 'Image • ${_formatSize(sizeBytes)}';
    }

    if (_isReadableTextMime(mimeType, fileName)) {
      try {
        final String text = utf8.decode(bytes);
        final String condensed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (condensed.isNotEmpty) {
          return condensed.length > 120
              ? '${condensed.substring(0, 120)}…'
              : condensed;
        }
      } on FormatException {
        return 'Text file • ${_formatSize(sizeBytes)}';
      }
      return 'Text file • ${_formatSize(sizeBytes)}';
    }

    final String extension = _fileExtension(fileName).toUpperCase();
    final String label = extension.isEmpty ? 'File' : '$extension file';
    return '$label • ${_formatSize(sizeBytes)}';
  }

  bool _isReadableTextMime(String mimeType, String fileName) {
    if (mimeType.startsWith('text/')) {
      return true;
    }

    const Set<String> textExtensions = <String>{
      'txt',
      'md',
      'markdown',
      'json',
      'yaml',
      'yml',
      'csv',
      'log',
      'xml',
      'html',
      'css',
      'js',
      'ts',
      'tsx',
      'dart',
      'py',
      'go',
      'java',
      'kt',
      'swift',
      'sql',
      'sh',
    };
    final String extension = _fileExtension(fileName);
    if (textExtensions.contains(extension)) {
      return true;
    }

    return mimeType.contains('json') || mimeType.contains('xml');
  }

  String _fileExtension(String fileName) {
    final String trimmed = fileName.trim();
    final int dotIndex = trimmed.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == trimmed.length - 1) {
      return '';
    }
    return trimmed.substring(dotIndex + 1).toLowerCase();
  }

  String _sanitizeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _formatSize(int sizeBytes) {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static const int _thumbnailMaxWidth = 200;

  /// Resizes and re-encodes large images before storage/upload.
  /// Images with both dimensions ≤ [_uploadMaxDimension] and size ≤
  /// [_uploadMinSizeToCompress] are returned unchanged.
  /// Larger images are resized to fit within [_uploadMaxDimension] and
  /// re-encoded as JPEG at [_uploadJpegQuality] quality.
  static const int _uploadMaxDimension = 2048;
  static const int _uploadJpegQuality = 85;
  static const int _uploadMinSizeToCompress = 512 * 1024; // 512 KB

  Future<(Uint8List, String)> _compressImage(
      Uint8List bytes, String mimeType) async {
    // Skip non-raster formats (GIF, SVG, etc.) that may not decode cleanly
    const Set<String> compressible = <String>{
      'image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/bmp',
      'image/tiff',
    };
    if (!compressible.contains(mimeType)) {
      return (bytes, mimeType);
    }
    if (bytes.length < _uploadMinSizeToCompress) {
      return (bytes, mimeType);
    }
    try {
      return await compute(
        _compressImageIsolate,
        (bytes, mimeType, _uploadMaxDimension, _uploadJpegQuality),
      );
    } catch (_) {
      // If compression fails for any reason, use the original bytes
      return (bytes, mimeType);
    }
  }

  Future<String?> _generateThumbnailBase64(List<int> bytes) async {
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(
        Uint8List.fromList(bytes),
        targetWidth: _thumbnailMaxWidth,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ByteData? pngBytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      frame.image.dispose();
      codec.dispose();
      if (pngBytes == null) {
        return null;
      }
      return base64Encode(pngBytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }
}

/// Top-level function required by [compute] — must not be a closure or method.
(Uint8List, String) _compressImageIsolate(
    (Uint8List, String, int, int) args) {
  final (bytes, mime, maxDim, quality) = args;

  final img.Image? decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return (bytes, mime);
  }

  final bool needsResize = decoded.width > maxDim || decoded.height > maxDim;

  img.Image processed;
  if (needsResize) {
    processed = decoded.width >= decoded.height
        ? img.copyResize(decoded,
            width: maxDim, interpolation: img.Interpolation.linear)
        : img.copyResize(decoded,
            height: maxDim, interpolation: img.Interpolation.linear);
  } else {
    processed = decoded;
  }

  final Uint8List compressed =
      Uint8List.fromList(img.encodeJpg(processed, quality: quality));

  // Only use the compressed version if it's actually smaller
  if (compressed.length >= bytes.length) {
    return (bytes, mime);
  }

  return (compressed, 'image/jpeg');
}
