/// Tracks short-lived trips to system pickers (camera, gallery, file picker).
///
/// Those pickers push the app to the background. Returning from them is not a
/// real "app was suspended" event, so the socket must not be torn down.
class ExternalActivityGuard {
  ExternalActivityGuard._();

  static int _active = 0;
  static DateTime? _lastEnd;
  static const Duration _grace = Duration(seconds: 3);

  /// Runs [action] and marks the app as visiting an external activity.
  static Future<T> run<T>(Future<T> Function() action) async {
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      _lastEnd = DateTime.now();
    }
  }

  /// True while a picker is open, or shortly after it closed.
  static bool get isActive {
    if (_active > 0) return true;
    final end = _lastEnd;
    return end != null && DateTime.now().difference(end) < _grace;
  }
}
