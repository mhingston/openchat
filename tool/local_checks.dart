import 'dart:io';

import 'quality_command_runner.dart';

Future<void> main() async {
  final Directory repositoryRoot = repositoryRootFromScript(Platform.script);

  int exitCode = await runFlutterCommand(
    const <String>['analyze'],
    workingDirectory: repositoryRoot,
  );
  if (exitCode != 0) {
    exit(exitCode);
  }

  final List<String> testFiles = topLevelTestFiles(repositoryRoot);
  if (testFiles.isEmpty) {
    return;
  }

  exitCode = await runFlutterCommand(
    <String>['test', ...testFiles],
    workingDirectory: repositoryRoot,
  );
  if (exitCode != 0) {
    exit(exitCode);
  }
}
