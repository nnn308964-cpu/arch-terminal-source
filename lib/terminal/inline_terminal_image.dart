import 'dart:convert';
import 'dart:typed_data';

class TerminalInlineImage {
  const TerminalInlineImage(this.bytes);

  final Uint8List bytes;
}

class TerminalImageDecodeResult {
  const TerminalImageDecodeResult({
    required this.terminalText,
    required this.images,
  });

  final String terminalText;
  final List<TerminalInlineImage> images;
}

/// Consumes only iTerm2 OSC 1337 inline-image frames. All other ANSI data is
/// passed to xterm unchanged, preserving the actual terminal emulator path.
class InlineTerminalImageDecoder {
  static const _prefix = '\x1b]1337;File=';
  static const _maxPayloadChars = 2 * 1024 * 1024;
  static const _maxPixels = 2 * 1024 * 1024;
  static const _defaultMaxPendingControlChars = _maxPayloadChars + 64 * 1024;
  InlineTerminalImageDecoder({
    int maxPendingControlChars = _defaultMaxPendingControlChars,
  }) : _maxPendingControlChars = maxPendingControlChars;

  final int _maxPendingControlChars;
  String _pending = '';

  TerminalImageDecodeResult consume(String chunk) {
    _pending += chunk;
    final text = StringBuffer();
    final images = <TerminalInlineImage>[];
    var offset = 0;

    while (offset < _pending.length) {
      final start = _pending.indexOf(_prefix, offset);
      if (start < 0) {
        final hold = _suffixPrefixLength(_pending.substring(offset));
        text.write(_pending.substring(offset, _pending.length - hold));
        if (hold > _maxPendingControlChars) {
          text.write('[terminal control sequence truncated]');
          _pending = '';
          return TerminalImageDecodeResult(
            terminalText: text.toString(),
            images: images,
          );
        }
        _pending = hold == 0 ? '' : _pending.substring(_pending.length - hold);
        return TerminalImageDecodeResult(
          terminalText: text.toString(),
          images: images,
        );
      }
      text.write(_pending.substring(offset, start));
      final bell = _pending.indexOf('\x07', start + _prefix.length);
      final st = _pending.indexOf('\x1b\\', start + _prefix.length);
      final end = _firstTerminator(bell, st);
      if (end == null) {
        _pending = _pending.substring(start);
        if (_pending.length > _maxPendingControlChars) {
          _pending = '';
          text.write('[inline image rejected: incomplete OSC exceeds limit]');
        }
        return TerminalImageDecodeResult(
          terminalText: text.toString(),
          images: images,
        );
      }

      final payloadEnd = end.$1;
      final frame = _pending.substring(start + _prefix.length, payloadEnd);
      final decoded = _decodeFrame(frame);
      if (decoded.image != null) {
        images.add(decoded.image!);
      } else {
        text.write(decoded.rejection);
      }
      offset = end.$2;
    }
    _pending = '';
    return TerminalImageDecodeResult(
      terminalText: text.toString(),
      images: images,
    );
  }

  (int, int)? _firstTerminator(int bell, int st) {
    if (bell < 0 && st < 0) return null;
    if (bell >= 0 && (st < 0 || bell < st)) return (bell, bell + 1);
    return (st, st + 2);
  }

  int _suffixPrefixLength(String value) {
    var hold = 0;
    final max = value.length < _prefix.length - 1
        ? value.length
        : _prefix.length - 1;
    for (var count = max; count > 0; count--) {
      if (_prefix.startsWith(value.substring(value.length - count))) {
        hold = count;
        break;
      }
    }

    // This decoder runs before xterm. Keep an unfinished OSC intact, even if
    // it is not an image sequence (for example, Bash OSC 3008 integration),
    // so xterm can consume it rather than render its payload as text.
    final oscStart = value.lastIndexOf('\x1b]');
    if (oscStart >= 0) {
      final tail = value.substring(oscStart + 2);
      if (!tail.contains('\x07') && !tail.contains('\x1b\\')) {
        final oscLength = value.length - oscStart;
        hold = hold < oscLength ? oscLength : hold;
      }
    } else if (value.endsWith('\x1b')) {
      hold = hold < 1 ? 1 : hold;
    }
    return hold;
  }

  _DecodedInlineImage _decodeFrame(String frame) {
    final colon = frame.indexOf(':');
    if (colon < 0) {
      return const _DecodedInlineImage.rejected(
        '[inline image rejected: malformed image frame]',
      );
    }
    final metadata = frame.substring(0, colon);
    final payload = frame.substring(colon + 1);
    if (!metadata.split(';').contains('inline=1')) {
      return const _DecodedInlineImage.rejected(
        '[inline image rejected: inline=1 metadata is required]',
      );
    }
    if (payload.length > _maxPayloadChars) {
      return const _DecodedInlineImage.rejected('[inline image rejected]');
    }
    try {
      final bytes = Uint8List.fromList(base64Decode(payload));
      final dimensions = _imageDimensions(bytes);
      if (dimensions == null) {
        return const _DecodedInlineImage.rejected(
          '[inline image rejected: expected a valid PNG, JPEG, or GIF file]',
        );
      }
      if (dimensions.$1 <= 0 ||
          dimensions.$2 <= 0 ||
          dimensions.$1 * dimensions.$2 > _maxPixels) {
        return const _DecodedInlineImage.rejected(
          '[inline image rejected: image dimensions exceed the safe limit]',
        );
      }
      return _DecodedInlineImage.image(TerminalInlineImage(bytes));
    } on FormatException {
      return const _DecodedInlineImage.rejected(
        '[inline image rejected: invalid Base64 image data]',
      );
    }
  }

  (int, int)? _imageDimensions(Uint8List bytes) {
    if (bytes.length >= 24 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return (_be32(bytes, 16), _be32(bytes, 20));
    }
    if (bytes.length >= 10 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return (bytes[6] | bytes[7] << 8, bytes[8] | bytes[9] << 8);
    }
    if (bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return _jpegDimensions(bytes);
    }
    return null;
  }

  int _be32(Uint8List bytes, int offset) =>
      bytes[offset] << 24 |
      bytes[offset + 1] << 16 |
      bytes[offset + 2] << 8 |
      bytes[offset + 3];

  (int, int)? _jpegDimensions(Uint8List bytes) {
    var index = 2;
    while (index + 9 < bytes.length) {
      if (bytes[index] != 0xff) {
        index++;
        continue;
      }
      while (index < bytes.length && bytes[index] == 0xff) {
        index++;
      }
      if (index >= bytes.length) return null;
      final marker = bytes[index++];
      if (marker == 0xd8 || marker == 0xd9) continue;
      if (index + 1 >= bytes.length) return null;
      final length = bytes[index] << 8 | bytes[index + 1];
      if (length < 2 || index + length > bytes.length) return null;
      final isSof =
          (marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf);
      if (isSof && index + 7 < bytes.length) {
        return (
          bytes[index + 5] << 8 | bytes[index + 6],
          bytes[index + 3] << 8 | bytes[index + 4],
        );
      }
      index += length;
    }
    return null;
  }
}

class _DecodedInlineImage {
  const _DecodedInlineImage.image(this.image) : rejection = '';
  const _DecodedInlineImage.rejected(this.rejection) : image = null;

  final TerminalInlineImage? image;
  final String rejection;
}
