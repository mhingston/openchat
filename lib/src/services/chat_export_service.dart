import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/attachment.dart';
import '../models/chat_thread.dart';

enum ExportFormat { json, markdown }

class ChatExportService {
  ChatExportService({
    Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
      required List<String> allowedExtensions,
    })? saveFile,
    Future<Uint8List?> Function()? pickImportBytes,
  })  : _saveFile = saveFile,
        _pickImportBytes = pickImportBytes;

  final Future<String?> Function({
    required String fileName,
    required Uint8List bytes,
    required List<String> allowedExtensions,
  })? _saveFile;
  final Future<Uint8List?> Function()? _pickImportBytes;

  Future<String?> exportThread({
    required ChatThread thread,
    required ExportFormat format,
  }) {
    return exportThreads(
      threads: <ChatThread>[thread],
      format: format,
      fileNamePrefix: _slugify(thread.title),
    );
  }

  Future<String?> exportThreads({
    required List<ChatThread> threads,
    required ExportFormat format,
    String fileNamePrefix = 'openchat-conversations',
  }) async {
    final String extension = format == ExportFormat.json ? 'json' : 'md';
    final String fileName =
        '${_slugify(fileNamePrefix)}-${_timestampToken()}.$extension';
    final String content = format == ExportFormat.json
        ? exportThreadsAsJson(threads)
        : exportThreadsAsMarkdown(threads);
    final Uint8List bytes = Uint8List.fromList(utf8.encode(content));
    final Future<String?> Function({
      required String fileName,
      required Uint8List bytes,
      required List<String> allowedExtensions,
    }) saveOperation = _saveFile ?? _defaultSaveFile;
    return saveOperation(
      fileName: fileName,
      bytes: bytes,
      allowedExtensions: <String>[extension],
    );
  }

  Future<ImportResult> importThreads() async {
    final Future<Uint8List?> Function() pickOperation =
        _pickImportBytes ?? _defaultPickImportBytes;
    final Uint8List? bytes = await pickOperation();
    if (bytes == null) {
      return const ImportResult.cancelled();
    }

    try {
      return importThreadsFromJson(utf8.decode(bytes));
    } on FormatException catch (error) {
      return ImportResult.error(
          'Unable to read the import file: ${error.message}');
    }
  }

  ImportResult importThreadsFromJson(String content) {
    try {
      final Object? decoded = jsonDecode(content);
      final Object? rawThreads =
          decoded is Map<String, dynamic> ? decoded['threads'] : decoded;
      if (rawThreads is! List<dynamic>) {
        return const ImportResult.error(
          'Invalid import file. Expected a JSON array of conversations.',
        );
      }

      final List<ChatThread> threads = rawThreads
          .whereType<Map<String, dynamic>>()
          .map(ChatThread.fromJson)
          .toList();
      if (threads.isEmpty) {
        return const ImportResult.error(
          'The selected file did not contain any conversations.',
        );
      }

      return ImportResult.success(threads);
    } on FormatException catch (error) {
      return ImportResult.error('Invalid JSON: ${error.message}');
    } catch (error) {
      return ImportResult.error('Unable to import conversations: $error');
    }
  }

  String exportThreadsAsJson(List<ChatThread> threads) {
    final List<Map<String, dynamic>> payload = threads
        .map((ChatThread thread) => thread.toJson())
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String exportThreadsAsMarkdown(List<ChatThread> threads) {
    final StringBuffer buffer = StringBuffer()
      ..writeln('# OpenChat conversation export')
      ..writeln()
      ..writeln('Exported ${threads.length} conversation(s).')
      ..writeln();

    for (int index = 0; index < threads.length; index += 1) {
      final ChatThread thread = threads[index];
      buffer
        ..writeln('## ${thread.title}')
        ..writeln()
        ..writeln('- Created: ${thread.createdAt.toIso8601String()}')
        ..writeln('- Updated: ${thread.updatedAt.toIso8601String()}')
        ..writeln('- Messages: ${thread.messages.length}')
        ..writeln();

      for (final message in thread.messages) {
        buffer
          ..writeln('### ${message.role.name.toUpperCase()}')
          ..writeln()
          ..writeln(message.text.trim().isEmpty ? '_No text_' : message.text);

        if (message.attachments.isNotEmpty) {
          buffer.writeln();
          for (final attachment in message.attachments) {
            final String? inlineData = attachment.thumbnailBase64 ??
                (attachment.isImage ? attachment.base64Data : null);
            if (inlineData != null) {
              buffer
                ..writeln(
                  '![${attachment.name}](data:${attachment.mimeType};base64,$inlineData)',
                )
                ..writeln()
                ..writeln(
                  '_${attachment.name} (${attachment.mimeType}, ${attachment.sizeBytes} bytes)_',
                );
            } else {
              buffer.writeln(
                '- ${attachment.name} (${attachment.mimeType}, ${attachment.sizeBytes} bytes)',
              );
            }
          }
        }

        buffer.writeln();
      }

      if (index != threads.length - 1) {
        buffer
          ..writeln('---')
          ..writeln();
      }
    }

    return buffer.toString().trimRight();
  }

  Future<String?> _defaultSaveFile({
    required String fileName,
    required Uint8List bytes,
    required List<String> allowedExtensions,
  }) {
    return FilePicker.platform.saveFile(
      dialogTitle: 'Save export',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
  }

  Future<Uint8List?> _defaultPickImportBytes() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }

    return result.files.single.bytes;
  }

  String _slugify(String value) {
    final String slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return slug.isEmpty ? 'openchat-export' : slug;
  }

  String _timestampToken() {
    return DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
  }
}

class ImportResult {
  const ImportResult.success(this.threads)
      : errorMessage = null,
        isCancelled = false;

  const ImportResult.error(this.errorMessage)
      : threads = null,
        isCancelled = false;

  const ImportResult.cancelled()
      : threads = null,
        errorMessage = null,
        isCancelled = true;

  final List<ChatThread>? threads;
  final String? errorMessage;
  final bool isCancelled;

  bool get isSuccess => threads != null;
  bool get isError => errorMessage != null;
}
