import 'package:flutter_test/flutter_test.dart';
import 'package:arch_terminal/terminal/terminal_control_filter.dart';
import 'package:arch_terminal/terminal/inline_terminal_image.dart';

void main() {
  test('removes a complete OSC sequence before it can render as text', () {
    final filter = TerminalControlFilter();
    expect(filter.consume('before\x1b]3008;start=id\x07after'), 'beforeafter');
  });

  test('removes an OSC sequence split across PTY chunks', () {
    final filter = TerminalControlFilter();
    expect(filter.consume('before\x1b]3008;start='), 'before');
    expect(filter.consume('id\x07after'), 'after');
  });

  test('removes split bracketed-paste mode without removing ANSI text', () {
    final filter = TerminalControlFilter();
    expect(filter.consume('red\x1b[?20'), 'red');
    expect(filter.consume('04lblue'), 'blue');
  });

  test('removes the exact shell frames reported by pacman without changing its output', () {
    final filter = TerminalControlFilter();
    final first = filter.consume(
      '\x1b[?2004l\r\x1b]3008;start=job;cwd=/root\\\x1b[?25l\x1b[1;34m::\x1b[0m Synchronizing',
    );
    final second = filter.consume(
      '\x1b[?25h\x1b]3008;end=job;exit=success\\\x1b]0;@localhost:~\x1b[?2004h\x1b[31m#\x1b[0m ',
    );

    expect(first, '\r\x1b[1;34m::\x1b[0m Synchronizing');
    expect(second, '\x1b[31m#\x1b[0m ');
  });

  test('removes physical PTY shell frames after the inline-image decoder splits OSC data', () {
    final images = InlineTerminalImageDecoder();
    final filter = TerminalControlFilter();
    final first = images.consume('\x1b[?2004l\r\x1b]3008;start=job;cwd=/root');
    final second = images.consume(
      '\\\x1b[?25l\x1b[1;34m::\x1b[0m Synchronizing\x1b[?25h\x1b]0;@localhost:~\x1b[?2004h',
    );

    expect(filter.consume(first.terminalText), '\r');
    expect(
      filter.consume(second.terminalText),
      '\x1b[1;34m::\x1b[0m Synchronizing',
    );
  });

  test('does not alter ordinary ANSI colours', () {
    final filter = TerminalControlFilter();
    expect(filter.consume('\x1b[31mred\x1b[0m'), '\x1b[31mred\x1b[0m');
  });
}
