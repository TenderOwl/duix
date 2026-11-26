import 'dart:io';

import 'package:duix/src/native/native_bindings.dart';
import 'package:test/test.dart';

/// The name of the native library on the current platform.
String get _libraryName {
  if (Platform.isWindows) return 'dui_native.dll';
  if (Platform.isMacOS) return 'libdui_native.dylib';
  return 'libdui_native.so';
}

void main() {
  test('the native library is searched next to the executable first', () {
    final candidates = NativeBindings.defaultLibraryCandidates;
    expect(candidates, isNotEmpty);

    final directory = File(Platform.resolvedExecutable).parent.path;
    expect(
      candidates.first,
      '$directory${Platform.pathSeparator}$_libraryName',
      reason: 'a packaged application keeps the library next to its executable',
    );
    expect(candidates, contains(_libraryName));
  });

  test('the platform key names the folder inside the package', () {
    final key = NativeBindings.platformKey;
    final system = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'macos'
            : 'linux';
    expect(key, startsWith('$system-'));
    expect(key, anyOf(endsWith('-x64'), endsWith('-arm64')));
  });

  test('the installed package holds the native library', () async {
    final directory = await NativeBindings.packageDirectory();
    expect(
      directory,
      isNotNull,
      reason: 'the package directory is only known while running from source',
    );
    expect(
      File('${directory!}${Platform.pathSeparator}pubspec.yaml').existsSync(),
      isTrue,
      reason: 'the package root holds the pubspec',
    );

    final candidates = NativeBindings.packageLibraryCandidates(directory);
    expect(candidates, hasLength(1));
    expect(candidates.first, endsWith(_libraryName));
    expect(
      candidates.first,
      contains(
        '${Platform.pathSeparator}native${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}${NativeBindings.platformKey}',
      ),
    );
  });

  test(
    'the install rules put the ICU data next to the library',
    () {
      final cmake = _findExecutable('cmake');
      if (cmake == null) {
        markTestSkipped('cmake is not available.');
        return;
      }
      final build = Directory('native${Platform.pathSeparator}build');
      if (!build.existsSync()) {
        markTestSkipped('the native library is not built.');
        return;
      }

      final prefix = Directory.systemTemp.createTempSync('dui_install');
      try {
        final result = Process.runSync(
          cmake,
          ['--install', build.path, '--prefix', prefix.path],
          workingDirectory: Directory.current.path,
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );

        // The ICU loader looks for the data file next to the library, so both
        // files have to end up in the same directory of the install tree.
        final directory = Directory(
          '${prefix.path}${Platform.pathSeparator}'
          '${Platform.isWindows ? 'bin' : 'lib'}',
        );
        expect(
          File('${directory.path}${Platform.pathSeparator}$_libraryName')
              .existsSync(),
          isTrue,
          reason: 'the library is missing in ${directory.path}',
        );
        if (Platform.isWindows) {
          // The ICU loader looks for the data file next to the library, so
          // both files have to end up in the same directory of the install
          // tree. On Linux and macOS Skia links the ICU data into the
          // library, so there is no file to install.
          expect(
            File('${directory.path}${Platform.pathSeparator}icudtl.dat')
                .existsSync(),
            isTrue,
            reason: 'the ICU data is missing in ${directory.path}',
          );
        } else {
          expect(
            File('${directory.path}${Platform.pathSeparator}icudtl.dat')
                .existsSync(),
            isFalse,
            reason: 'the ICU data is linked into the library on this platform',
          );
        }
      } finally {
        prefix.deleteSync(recursive: true);
      }
    },
    tags: 'native',
  );
}

String? _findExecutable(String name) {
  if (Platform.isWindows) {
    final path = Platform.environment['PATH'];
    if (path == null) return null;
    for (final entry in path.split(';')) {
      final candidate = File('$entry${Platform.pathSeparator}$name.exe');
      if (candidate.existsSync()) return candidate.path;
    }
    return null;
  }
  for (final entry in (Platform.environment['PATH'] ?? '').split(':')) {
    final candidate = File('$entry${Platform.pathSeparator}$name');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}
