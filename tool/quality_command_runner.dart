import 'dart:io';

Directory repositoryRootFromScript(Uri scriptUri) {
  return File.fromUri(scriptUri).parent.parent;
}

List<String> topLevelTestFiles(Directory repositoryRoot) {
  final Directory testDirectory =
      Directory.fromUri(repositoryRoot.uri.resolve('test/'));
  if (!testDirectory.existsSync()) {
    return const <String>[];
  }

  final List<String> testFiles = testDirectory
      .listSync()
      .whereType<File>()
      .where(
        (File file) => file.path.endsWith('_test.dart'),
      )
      .map(
        (File file) => file.uri.pathSegments.last,
      )
      .toList()
    ..sort();

  return testFiles.map((String fileName) => 'test/$fileName').toList();
}

Future<int> runFlutterCommand(
  List<String> arguments, {
  required Directory workingDirectory,
}) async {
  final String executable = _resolveFlutterExecutable();

  try {
    final Process process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory.path,
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    return await process.exitCode;
  } on ProcessException catch (error) {
    stderr.writeln('Failed to run "$executable ${arguments.join(' ')}".');
    stderr.writeln(error.message);
    return 1;
  }
}

String _resolveFlutterExecutable() {
  final String? override = Platform.environment['FLUTTER_BIN'];
  if (override != null && override.trim().isNotEmpty) {
    return override.trim();
  }

  final File dartExecutable = File(Platform.resolvedExecutable);
  final String flutterBinaryName =
      Platform.isWindows ? 'flutter.bat' : 'flutter';
  final List<File> candidates = <File>[
    if (Platform.environment['FLUTTER_ROOT'] case final String flutterRoot
        when flutterRoot.trim().isNotEmpty)
      File.fromUri(
        Directory(flutterRoot.trim()).uri.resolve('bin/$flutterBinaryName'),
      ),
    File.fromUri(dartExecutable.parent.uri.resolve(flutterBinaryName)),
    File.fromUri(
      dartExecutable.parent.parent.parent.parent.uri.resolve(flutterBinaryName),
    ),
  ];

  for (final File candidate in candidates) {
    if (candidate.existsSync()) {
      return candidate.path;
    }
  }

  return 'flutter';
}
