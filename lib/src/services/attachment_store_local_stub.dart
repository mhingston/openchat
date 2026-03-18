Future<String> createAttachmentStoragePath(String appFolderName) async {
  throw UnsupportedError('Local attachment storage is not available on web.');
}

Future<String> writeAttachmentFile({
  required String directoryPath,
  required String fileName,
  required List<int> bytes,
}) async {
  throw UnsupportedError('Local attachment storage is not available on web.');
}

Future<List<int>> readAttachmentBytes(String path) async {
  throw UnsupportedError('Local attachment files are not available on web.');
}

Future<String> readAttachmentText(String path) async {
  throw UnsupportedError('Local attachment files are not available on web.');
}

Future<bool> attachmentFileExists(String path) async {
  return false;
}

Future<void> deleteAttachmentFile(String path) async {}
