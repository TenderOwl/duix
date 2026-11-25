import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:duix/dui.dart';
import 'package:duix/native.dart';
import 'package:ffi/ffi.dart';

Future<void> main() async {
  const updateCount = 60;
  final host = await SdlSkiaHost.initialize(diagnosticsEnabled: true);
  final application = Application(host: host);
  final text = Label(text: 'Idle', fontSize: 24);
  final window = Window(
    title: 'DUI — frame benchmark',
    width: 480,
    height: 160,
    content: StackPanel(
      padding: const EdgeInsets.all(20),
      children: [text],
    ),
  );

  try {
    await application.run(window);
    final watch = Stopwatch()..start();
    final cpuStart = _ProcessCpuSample.read();
    late NativeWindowDiagnostics idleDiagnostics;
    late int idleWallMicroseconds;
    late int idleCpu100ns;

    var active = false;
    var updatesIssued = 0;
    var updatesPainted = 0;
    var pendingInvalidations = 0;
    var firstInvalidatedAt = 0;
    final latenciesMicroseconds = <int>[];
    Timer? updateTimer;

    Timer(const Duration(seconds: 1), () {
      idleDiagnostics = host.diagnosticsFor(window)!;
      idleWallMicroseconds = watch.elapsedMicroseconds;
      idleCpu100ns = _elapsedCpu100ns(cpuStart, _ProcessCpuSample.read());
      active = true;
      updateTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
        if (pendingInvalidations == 0) {
          firstInvalidatedAt = watch.elapsedMicroseconds;
        }
        pendingInvalidations++;
        updatesIssued++;
        text.text = 'Async update $updatesIssued / $updateCount';
        if (updatesIssued == updateCount) timer.cancel();
      });
    });

    while (host.isOpen(window) &&
        (!active ||
            updatesPainted < updateCount ||
            pendingInvalidations > 0 ||
            window.frameScheduled)) {
      host.waitForEvent(window);
      final previousPaintCount = window.paintPassCount;
      host.presentWindow(window);
      if (window.paintPassCount > previousPaintCount &&
          pendingInvalidations > 0) {
        latenciesMicroseconds.add(
          watch.elapsedMicroseconds - firstInvalidatedAt,
        );
        updatesPainted += pendingInvalidations;
        pendingInvalidations = 0;
      }
      await Future<void>.delayed(Duration.zero);
    }
    updateTimer?.cancel();

    if (updatesIssued != updateCount || updatesPainted != updateCount) {
      throw StateError(
        'Benchmark did not finish: issued=$updatesIssued, '
        'painted=$updatesPainted.',
      );
    }
    final finalDiagnostics = host.diagnosticsFor(window)!;
    final totalCpu100ns = _elapsedCpu100ns(cpuStart, _ProcessCpuSample.read());
    latenciesMicroseconds.sort();
    final averageLatency = latenciesMicroseconds.reduce((a, b) => a + b) /
        latenciesMicroseconds.length;
    final medianLatency =
        latenciesMicroseconds[latenciesMicroseconds.length ~/ 2];

    print('Native frame benchmark:');
    print(
      '  idle: wall=${_milliseconds(idleWallMicroseconds)}, '
      'CPU=${_cpu(idleCpu100ns)}, '
      'CPU%=${_cpuPercent(idleCpu100ns, idleWallMicroseconds)}',
    );
    print('  idle diagnostics: $idleDiagnostics');
    print(
      '  async updates: $updateCount, '
      'frames=${finalDiagnostics.paintPassCount - idleDiagnostics.paintPassCount}, '
      'latency avg=${_microseconds(averageLatency)}, '
      'median=${_microseconds(medianLatency.toDouble())}, '
      'max=${_microseconds(latenciesMicroseconds.last.toDouble())}',
    );
    print(
      '  total: wall=${_milliseconds(watch.elapsedMicroseconds)}, '
      'CPU=${_cpu(totalCpu100ns)}, '
      'CPU%=${_cpuPercent(totalCpu100ns, watch.elapsedMicroseconds)}',
    );
    print('  final diagnostics: $finalDiagnostics');
  } finally {
    await application.shutdown(window);
    host.dispose();
  }
}

String _milliseconds(int microseconds) =>
    '${(microseconds / 1000).toStringAsFixed(1)} ms';

String _microseconds(double value) => '${value.toStringAsFixed(1)} us';

String _cpu(int cpu100ns) => cpu100ns < 0
    ? 'unsupported'
    : '${(cpu100ns / 10000).toStringAsFixed(1)} ms';

String _cpuPercent(int cpu100ns, int wallMicroseconds) => cpu100ns < 0
    ? 'unsupported'
    : '${(cpu100ns / (wallMicroseconds * 10) * 100).toStringAsFixed(2)}%';

int _elapsedCpu100ns(_ProcessCpuSample? start, _ProcessCpuSample? end) {
  if (start == null || end == null) return -1;
  return end.kernelUser100ns - start.kernelUser100ns;
}

final class _ProcessCpuSample {
  const _ProcessCpuSample(this.kernelUser100ns);

  final int kernelUser100ns;

  static _ProcessCpuSample? read() {
    if (!Platform.isWindows) return null;
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getCurrentProcess =
        kernel32.lookupFunction<IntPtr Function(), int Function()>(
      'GetCurrentProcess',
    );
    final getProcessTimes = kernel32.lookupFunction<
        Int32 Function(
          IntPtr,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        ),
        int Function(
          int,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
          Pointer<Uint64>,
        )>('GetProcessTimes');
    final creation = calloc<Uint64>();
    final exit = calloc<Uint64>();
    final kernel = calloc<Uint64>();
    final user = calloc<Uint64>();
    try {
      final succeeded = getProcessTimes(
        getCurrentProcess(),
        creation,
        exit,
        kernel,
        user,
      );
      if (succeeded == 0) return null;
      return _ProcessCpuSample(kernel.value + user.value);
    } finally {
      calloc.free(creation);
      calloc.free(exit);
      calloc.free(kernel);
      calloc.free(user);
    }
  }
}
