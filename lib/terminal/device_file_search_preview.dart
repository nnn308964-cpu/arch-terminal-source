class DeviceFileSearchPreview {
  const DeviceFileSearchPreview({required this.paths, required this.truncated});

  final List<String> paths;
  final bool truncated;

  bool get isEmpty => paths.isEmpty;
}

/// Accepts only an explicitly bounded `find` command rooted at `/sdcard`.
/// The check deliberately excludes callbacks and content-reading constructs.
bool isBoundedDeviceFileSearchCommand(String command) {
  final normalized = command.trim().toLowerCase();
  if (!RegExp(r'(^|[;&|]\s*)find\s+/sdcard(?:\s|$)').hasMatch(normalized)) {
    return false;
  }
  if (normalized.contains(RegExp(r'\s-exec\s|\s-ok\s|\$\(|`'))) {
    return false;
  }
  return normalized.contains('-maxdepth') &&
      (normalized.contains('-type f') || normalized.contains('-type d')) &&
      (normalized.contains('head -n') || normalized.contains('head -'));
}

/// Returns the listed directory only for a simple, approved `ls` invocation
/// rooted at `/sdcard`. Shell composition is deliberately excluded; output is
/// for local UI display only and never enters the AI provider context.
String? deviceDirectoryFromListCommand(String command) {
  final normalized = command.trim();
  if (normalized.contains(RegExp(r'[;&|`]|\$\('))) return null;
  final match = RegExp(
    r'^ls(?:\s+-[A-Za-z]+)*\s+(?:--\s+)?(/sdcard(?:/[^\s]*)?)\s*$',
  ).firstMatch(normalized);
  return match?.group(1);
}

/// Keeps only absolute `/sdcard` paths from terminal output. It never reads a
/// file and deliberately imposes a small local display limit.
DeviceFileSearchPreview parseDeviceFileSearchPreview(
  String output, {
  int maxResults = 24,
}) {
  assert(maxResults > 0);
  final clean = output
      .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll('\r', '');
  final paths = <String>[];
  final seen = <String>{};
  var truncated = false;
  for (final rawLine in clean.split('\n')) {
    final path = rawLine.trim();
    if (!RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(path) ||
        path.length > 512 ||
        path.contains('\x00')) {
      continue;
    }
    if (!seen.add(path)) continue;
    if (paths.length == maxResults) {
      truncated = true;
      break;
    }
    paths.add(path);
  }
  return DeviceFileSearchPreview(paths: paths, truncated: truncated);
}

/// Converts a simple `ls` output into absolute paths under an already checked
/// `/sdcard` directory. It never reads a file and imposes a display limit.
DeviceFileSearchPreview parseDeviceDirectoryListingPreview(
  String output, {
  required String directory,
  int maxResults = 24,
}) {
  assert(maxResults > 0);
  if (!RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(directory)) {
    throw ArgumentError.value(
      directory,
      'directory',
      'Expected a path under /sdcard',
    );
  }
  final clean = output
      .replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '')
      .replaceAll('\r', '');
  final paths = <String>[];
  final seen = <String>{};
  var truncated = false;
  for (final rawLine in clean.split('\n')) {
    var entry = rawLine.trim();
    entry = entry.replaceFirst(RegExp(r'[/@*=>|]$'), '');
    if (entry.isEmpty ||
        entry == '.' ||
        entry == '..' ||
        entry.length > 180 ||
        entry.contains(RegExp(r'[\x00\n\r/]'))) {
      continue;
    }
    final path = '$directory/$entry';
    if (!seen.add(path)) continue;
    if (paths.length == maxResults) {
      truncated = true;
      break;
    }
    paths.add(path);
  }
  return DeviceFileSearchPreview(paths: paths, truncated: truncated);
}

String terminalCdCommandForDevicePath(String path) {
  if (!RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(path)) {
    throw ArgumentError.value(path, 'path', 'Expected a path under /sdcard');
  }
  return "cd -- '${_shellQuote(path)}'";
}

String terminalRevealCommandForDevicePath(String path) {
  if (!RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(path)) {
    throw ArgumentError.value(path, 'path', 'Expected a path under /sdcard');
  }
  return "ls -ld -- '${_shellQuote(path)}'";
}

String _shellQuote(String value) => value.replaceAll("'", "'\\\"'\\\"'");
