class TripleTapGate {
  TripleTapGate({
    this.window = const Duration(milliseconds: 1100),
    this.requiredTaps = 3,
  });

  final Duration window;
  final int requiredTaps;
  DateTime? _lastTap;
  int _count = 0;

  bool register(DateTime now) {
    if (_lastTap == null || now.difference(_lastTap!) > window) _count = 0;
    _lastTap = now;
    _count++;
    if (_count < requiredTaps) return false;
    reset();
    return true;
  }

  void reset() {
    _count = 0;
    _lastTap = null;
  }
}
