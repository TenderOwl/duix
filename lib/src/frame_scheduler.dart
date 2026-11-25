final class FrameScheduler {
  bool _frameScheduled = false;
  bool _layoutInProgress = false;
  void Function()? _onFrameScheduled;

  int _scheduledFrameCount = 0;
  int _layoutPassCount = 0;
  int _paintPassCount = 0;

  bool get frameScheduled => _frameScheduled;
  int get scheduledFrameCount => _scheduledFrameCount;
  int get layoutPassCount => _layoutPassCount;
  int get paintPassCount => _paintPassCount;

  void setFrameRequestHandler(void Function()? handler) {
    _onFrameScheduled = handler;
    if (handler != null && _frameScheduled) handler();
  }

  void requestFrame() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    _scheduledFrameCount++;
    _onFrameScheduled?.call();
  }

  bool tryBeginFrame() {
    if (!_frameScheduled) return false;
    _frameScheduled = false;
    return true;
  }

  void layout(void Function() callback) {
    if (_layoutInProgress) {
      throw StateError('Recursive layout is not allowed.');
    }
    _layoutInProgress = true;
    try {
      callback();
      _layoutPassCount++;
    } finally {
      _layoutInProgress = false;
    }
  }

  void paint(void Function() callback) {
    callback();
    _paintPassCount++;
  }
}
