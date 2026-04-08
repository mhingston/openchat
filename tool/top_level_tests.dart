import 'dart:io';

import 'quality_command_runner.dart';

Future<void> main() async {
  final Directory repositoryRoot = repositoryRootFromScript(Platform.script);
  final List<String> testFiles = topLevelTestFiles(repositoryRoot);
  if (testFiles.isEmpty) {
    stdout.writeln('No top-level tests found.');
    return;
  }

  final int exitCode = await runFlutterCommand(
    <String>['test', ...testFiles],
    workingDirectory: repositoryRoot,
  );
  if (exitCode != 0) {
    exit(exitCode);
  }
}
