/// Preserves terminal control frames that are split across PTY reads.
///
/// Shell-integration controls have no user-facing meaning in this application.
/// They are removed only after a complete frame arrives, while normal CSI/ANSI
/// colours and ordinary terminal text remain untouched.
class TerminalControlFilter {
  static const _bracketedPasteEnable = '\x1b[?2004h';
  static const _bracketedPasteDisable = '\x1b[?2004l';
  static const _cursorShow = '\x1b[?25h';
  static const _cursorHide = '\x1b[?25l';
  static const _maxPendingControlChars = 64 * 1024;
  static const _ignoredCsi = <String>[
    _bracketedPasteEnable,
    _bracketedPasteDisable,
    _cursorShow,
    _cursorHide,
  ];
  String _pending = '';

  String consume(String input) {
    if (input.isEmpty && _pending.isEmpty) return '';
    final source = '$_pending$input';
    _pending = '';
    final output = StringBuffer();
    var index = 0;

    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code != 0x1b) {
        output.writeCharCode(code);
        index++;
        continue;
      }

      if (index + 1 >= source.length) {
        _pending = source.substring(index);
        break;
      }

      final next = source.codeUnitAt(index + 1);
      if (next == 0x5d) {
        final end = _oscEnd(source, index + 2);
        if (end == null) {
          _pending = source.substring(index);
          if (_pending.length > _maxPendingControlChars) {
            _pending = '';
            output.write('[terminal control sequence truncated]');
          }
          break;
        }
        // Suppress completed OSC frames (including Bash OSC 3008 and window
        // titles). This prevents unsupported OSC handlers from rendering the
        // payload as visible text on Android devices.
        index = end;
        continue;
      }

      final ignoredCsi = _ignoredCsi.firstWhere(
        (value) => source.startsWith(value, index),
        orElse: () => '',
      );
      if (ignoredCsi.isNotEmpty) {
        index += ignoredCsi.length;
        continue;
      }

      if (next == 0x5b) {
        final tail = source.substring(index);
        if (_ignoredCsi.any((value) => value.startsWith(tail))) {
          _pending = tail;
          break;
        }
      }

      output.writeCharCode(code);
      index++;
    }
    return output.toString();
  }

  int? _oscEnd(String source, int start) {
    final shellIntegration = source.startsWith('3008;', start);
    for (var i = start; i < source.length; i++) {
      if (source.codeUnitAt(i) == 0x07) return i + 1;
      if (source.codeUnitAt(i) == 0x1b &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == 0x5c) {
        return i + 2;
      }
      // If the PTY splits the ESC part of an OSC title terminator away from
      // its backslash, the following CSI begins a new control frame. Close the
      // incomplete OSC immediately before that CSI so it cannot consume the
      // prompt and colour sequence that follows.
      if (source.codeUnitAt(i) == 0x1b &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == 0x5b) {
        return i;
      }
      // A few Android PTY paths deliver the ESC before the ST terminator in a
      // separate chunk. Bash OSC 3008 then appears as a bare backslash before
      // the next CSI. Treat that documented shell-integration frame as closed
      // rather than swallowing the following pacman output.
      if (shellIntegration && source.codeUnitAt(i) == 0x5c) return i + 1;
    }
    return null;
  }
}
