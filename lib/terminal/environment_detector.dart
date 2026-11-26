import 'ai_environment_snapshot.dart';

class EnvironmentProbeResult {
  const EnvironmentProbeResult({required this.terminalText, this.snapshot});

  final String terminalText;
  final AiEnvironmentSnapshot? snapshot;
}

/// Runs a read-only guest probe and removes only its sentinel-delimited output
/// from the visible terminal stream.
class EnvironmentDetector {
  static const _maxProbeChars = 12 * 1024;
  String _begin = '';
  String _end = '';
  String _pending = '';
  bool _capturing = false;

  bool get isProbeActive => _begin.isNotEmpty;

  String beginProbe() {
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    _begin = '__ARCH_TERMINAL_ENV_BEGIN_${token}__';
    _end = '__ARCH_TERMINAL_ENV_END_${token}__';
    _pending = '';
    _capturing = false;
    return '__arch_terminal_env_probe $token\n';
  }

  void cancel() => _reset();

  EnvironmentProbeResult consume(
    String input,
    Map<String, Object?> runtimeStatus,
  ) {
    if (!isProbeActive || input.isEmpty) {
      return EnvironmentProbeResult(terminalText: input);
    }
    _pending += input;
    final visible = StringBuffer();
    AiEnvironmentSnapshot? snapshot;

    while (_pending.isNotEmpty) {
      if (!_capturing) {
        final start = _pending.indexOf(_begin);
        if (start < 0) {
          final keep = _partialBeginLength(_pending);
          visible.write(_pending.substring(0, _pending.length - keep));
          _pending = keep == 0
              ? ''
              : _pending.substring(_pending.length - keep);
          break;
        }
        visible.write(_pending.substring(0, start));
        _pending = _pending.substring(start + _begin.length);
        if (_pending.startsWith('\r\n')) _pending = _pending.substring(2);
        if (_pending.startsWith('\n')) _pending = _pending.substring(1);
        _capturing = true;
        continue;
      }

      final end = _pending.indexOf(_end);
      if (end < 0) {
        if (_pending.length > _maxProbeChars) {
          visible.write(_pending);
          _reset();
        }
        break;
      }
      snapshot = AiEnvironmentSnapshot.fromProbe(
        _parseValues(_pending.substring(0, end)),
        runtimeStatus,
      );
      var trailingTerminalText = _pending.substring(end + _end.length);
      if (trailingTerminalText.startsWith('\r\n')) {
        trailingTerminalText = trailingTerminalText.substring(2);
      }
      if (trailingTerminalText.startsWith('\n')) {
        trailingTerminalText = trailingTerminalText.substring(1);
      }
      _reset();
      visible.write(trailingTerminalText);
      break;
    }
    return EnvironmentProbeResult(
      terminalText: visible.toString(),
      snapshot: snapshot,
    );
  }

  int _partialBeginLength(String value) {
    final max = value.length < _begin.length - 1
        ? value.length
        : _begin.length - 1;
    for (var count = max; count > 0; count--) {
      if (_begin.startsWith(value.substring(value.length - count))) {
        return count;
      }
    }
    return 0;
  }

  Map<String, String> _parseValues(String raw) {
    final values = <String, String>{};
    for (final line in raw.replaceAll('\r', '').split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator);
      if (const <String>{
        'user',
        'uid',
        'architecture',
        'os_name',
        'pacman',
        'pacman_packages',
        'repo_configured',
        'repo_mirror',
        'repo_names',
        'repo_database_count',
        'pwd',
        'root_free_kib',
        'storage_bound',
      }.contains(key)) {
        values[key] = line.substring(separator + 1);
      }
    }
    return values;
  }

  void _reset() {
    _begin = '';
    _end = '';
    _capturing = false;
    _pending = '';
  }
}
