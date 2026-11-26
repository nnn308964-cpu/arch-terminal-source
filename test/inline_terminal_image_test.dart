import 'package:arch_terminal/terminal/inline_terminal_image.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves a generic OSC 3008 frame split across PTY chunks', () {
    final decoder = InlineTerminalImageDecoder();

    expect(decoder.consume('before\x1b]3008;start=').terminalText, 'before');
    final result = decoder.consume('command-id\x07after');

    expect(result.terminalText, '\x1b]3008;start=command-id\x07after');
    expect(result.images, isEmpty);
  });

  test('preserves a generic OSC frame whose ESC prefix is split', () {
    final decoder = InlineTerminalImageDecoder();

    expect(decoder.consume('before\x1b').terminalText, 'before');
    expect(
      decoder.consume(']0;title\x1b\\after').terminalText,
      '\x1b]0;title\x1b\\after',
    );
  });

  test('continues to decode a valid iTerm2 inline image frame', () {
    final decoder = InlineTerminalImageDecoder();
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';

    final result = decoder.consume('\x1b]1337;File=inline=1:$pngBase64\x07');

    expect(result.terminalText, isEmpty);
    expect(result.images, hasLength(1));
  });

  test('decodes an iTerm2 image split across three PTY chunks', () {
    final decoder = InlineTerminalImageDecoder();
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';
    final frame = '\x1b]1337;File=inline=1:$pngBase64\x07';

    expect(decoder.consume(frame.substring(0, 18)).images, isEmpty);
    expect(decoder.consume(frame.substring(18, 59)).images, isEmpty);
    final result = decoder.consume(frame.substring(59));

    expect(result.terminalText, isEmpty);
    expect(result.images, hasLength(1));
  });

  test(
    'bounds an incomplete image OSC instead of retaining it indefinitely',
    () {
      final decoder = InlineTerminalImageDecoder(maxPendingControlChars: 40);

      final result = decoder.consume('\x1b]1337;File=inline=1:${'a' * 41}');

      expect(
        result.terminalText,
        '[inline image rejected: incomplete OSC exceeds limit]',
      );
      expect(decoder.consume('ready').terminalText, 'ready');
    },
  );

  test(
    'bounds an incomplete unknown OSC while preserving later terminal text',
    () {
      final decoder = InlineTerminalImageDecoder(maxPendingControlChars: 24);

      final result = decoder.consume('before\x1b]3008;${'x' * 25}');

      expect(
        result.terminalText,
        'before[terminal control sequence truncated]',
      );
      expect(decoder.consume('after').terminalText, 'after');
    },
  );

  test('reports invalid Base64 and unsupported image bytes distinctly', () {
    final decoder = InlineTerminalImageDecoder();

    final malformed = decoder.consume(
      '\x1b]1337;File=inline=1:not-base64!\x07',
    );
    final unsupported = decoder.consume('\x1b]1337;File=inline=1:aGVsbG8=\x07');

    expect(
      malformed.terminalText,
      '[inline image rejected: invalid Base64 image data]',
    );
    expect(
      unsupported.terminalText,
      '[inline image rejected: expected a valid PNG, JPEG, or GIF file]',
    );
  });
}
