// Copies the prebuilt native library of this package next to an application.
//
// A compiled Dart executable keeps no package configuration, so it cannot find
// the library inside the pub cache on its own. This executable locates the
// package and copies the library and the ICU data file into the directory of
// the application.
//
//   dart run duix:setup_native build
//
// The directory argument is optional and defaults to the current directory.
import 'dart:io';

import 'package:duix/native.dart';

Future<void> main(List<String> arguments) async {
  final target = Directory(
    arguments.isEmpty ? Directory.current.path : arguments.first,
  );
  final package = await NativeBindings.packageDirectory();
  if (package == null) {
    stderr.writeln(
      'Could not resolve the package directory. Run this command with '
      '"dart run", so the package configuration is available.',
    );
    exitCode = 1;
    return;
  }

  final source = Directory(
    '$package${Platform.pathSeparator}native${Platform.pathSeparator}bin'
    '${Platform.pathSeparator}${NativeBindings.platformKey}',
  );
  if (!source.existsSync()) {
    stderr.writeln(
      'The package does not contain a native library for '
      '${NativeBindings.platformKey}: ${source.path}',
    );
    stderr.writeln(
      'Build it from source with "python tools/bootstrap_native.py" or download '
      'a release that ships the binary.',
    );
    exitCode = 1;
    return;
  }

  if (!target.existsSync()) {
    target.createSync(recursive: true);
  }
  var copied = 0;
  for (final file in source.listSync()) {
    if (file is! File) continue;
    file.copySync(
        '${target.path}${Platform.pathSeparator}${file.uri.pathSegments.last}');
    stdout.writeln('Copied ${file.uri.pathSegments.last} to ${target.path}');
    copied++;
  }
  if (copied == 0) {
    stderr.writeln('The package folder ${source.path} is empty.');
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'The native library is ready. Keep it next to the executable of the '
    'application.',
  );
}
