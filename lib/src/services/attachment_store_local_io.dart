import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> createAttachmentStoragePath(String appFolderName) async {
  final Directory supportDirectory = await getApplicationSupportDirectory();
  final Directory attachmentsDirectory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}$appFolderName${Platform.pathSeparator}attachments',
  );
  await attachmentsDirectory.create(recursive: true);
  return attachmentsDirectory.path;
}

Future<String> writeAttachmentFile({
  required String directoryPath,
  required String fileName,
  required List<int> bytes,
}) async {
  final File destination =
      File('$directoryPath${Platform.pathSeparator}$fileName');
  await destination.writeAsBytes(bytes, flush: true);
  return destination.path;
}

Future<List<int>> readAttachmentBytes(String path) async {
  final File file = File(path);
  return file.readAsBytes();
}

Future<String> readAttachmentText(String path) async {
  final File file = File(path);
  return file.readAsString();
}

Future<bool> attachmentFileExists(String path) async {
  final File file = File(path);
  return file.exists();
}

Future<void> deleteAttachmentFile(String path) async {
  final File file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}
