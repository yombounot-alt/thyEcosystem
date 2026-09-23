/// What the scanner shows the user after a code was read: [message] for a moment over the camera,
/// as a success or as a problem (unknown code, out of stock…).
class ScanFeedback {
  const ScanFeedback.ok(this.message) : isProblem = false;
  const ScanFeedback.problem(this.message) : isProblem = true;

  final String message;
  final bool isProblem;
}

/// Called for every code the camera reads; whoever opened the scanner decides what a code means.
typedef ScanHandler = Future<ScanFeedback> Function(String code);

/// Stops one held-still barcode from being read fifty times a second: a code is accepted again
/// only after the camera has not seen it for [gap]. Holding it in view never re-adds it; taking
/// it away and showing it again (a second identical article) does.
class ScanDebouncer {
  ScanDebouncer({this.gap = const Duration(milliseconds: 1200), DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final Duration gap;
  final DateTime Function() _now;
  final Map<String, DateTime> _lastSeen = {};

  bool accept(String code) {
    final now = _now();
    final previous = _lastSeen[code];
    _lastSeen[code] = now; // seeing it again, even if ignored, keeps it "in view"
    return previous == null || now.difference(previous) > gap;
  }
}
