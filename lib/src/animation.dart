import 'dart:async';

/// The way an animation shapes the time of its run.
///
/// The function gets the share of the run that is over, from zero to one, and
/// gives back the share of the way that is done.
typedef EasingFunction = double Function(double t);

/// The easing that slows the animation down at its end.
///
/// The value grows quickly at the beginning and comes to its target slowly,
/// the way a thumb of a switch slides.
double easeOutCubic(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

/// A number that moves from one value to another over time.
///
/// The animation runs on the timer of the Dart event loop, so it moves in the
/// native backend and in the tests alike. Every tick reports the new value to
/// the listener of the animation.
///
/// The animation owns its timer, so the owner of the animation has to stop or
/// dispose it when it is gone.
final class ValueAnimation {
  ValueAnimation({
    this.duration = const Duration(milliseconds: 150),
    this.easing = easeOutCubic,
    this.onChanged,
  });

  /// The time the animation takes to come to its target.
  final Duration duration;

  /// The way the animation shapes the time of its run.
  final EasingFunction easing;

  /// Called with the new value on every tick of the animation.
  final void Function(double value)? onChanged;

  /// The time between two ticks of the animation.
  static const Duration tickInterval = Duration(milliseconds: 16);

  double _value = 0;
  double _start = 0;
  double _target = 0;
  Timer? _timer;
  Stopwatch? _stopwatch;

  /// The value of the animation right now.
  double get value => _value;

  /// The value the animation moves to.
  double get target => _target;

  /// Whether the animation is running.
  bool get isRunning => _timer != null;

  /// Moves the animation to the target value.
  ///
  /// The run starts at the current value, or at [from] when it is given. An
  /// animation without a time jumps to the target at once.
  void animateTo(double target, {double? from}) {
    stop();
    _target = target;
    final start = from ?? _value;
    if (duration <= Duration.zero) {
      _setValue(target);
      return;
    }
    _start = start;
    _value = start;
    _stopwatch = Stopwatch()..start();
    _timer = Timer.periodic(tickInterval, _tick);
  }

  /// Sets the value of the animation at once, without a run.
  void jumpTo(double value) {
    stop();
    _value = value;
    _start = value;
    _target = value;
  }

  /// Stops the animation where it is.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch?.stop();
    _stopwatch = null;
  }

  /// Stops the animation and gives it back.
  void dispose() => stop();

  void _tick(Timer timer) {
    final stopwatch = _stopwatch;
    if (stopwatch == null) {
      stop();
      return;
    }
    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed >= duration.inMilliseconds) {
      stop();
      _setValue(_target);
      return;
    }
    final t = elapsed / duration.inMilliseconds;
    _setValue(_start + (_target - _start) * easing(t));
  }

  void _setValue(double value) {
    if (_value == value) return;
    _value = value;
    onChanged?.call(value);
  }
}
