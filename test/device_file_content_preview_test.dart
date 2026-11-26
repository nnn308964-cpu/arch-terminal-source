import 'dart:typed_data';

import 'package:arch_terminal/terminal/device_file_content_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a bounded local text preview', () {
    final preview = DeviceFileContentPreview.fromMap(<String, Object?>{
      'kind': 'text',
      'path': '/sdcard/Download/note.txt',
      'sizeBytes': 12,
      'text': 'hello local',
    });

    expect(preview.kind, DeviceFileContentKind.text);
    expect(preview.text, 'hello local');
    expect(preview.bytes, isNull);
  });

  test('parses image bytes and rejects payloads outside device storage', () {
    final preview = DeviceFileContentPreview.fromMap(<String, Object?>{
      'kind': 'image',
      'path': '/sdcard/Pictures/test.png',
      'sizeBytes': 4,
      'bytes': Uint8List.fromList(<int>[137, 80, 78, 71]),
      'width': 1,
      'height': 1,
    });

    expect(preview.kind, DeviceFileContentKind.image);
    expect(preview.bytes, hasLength(4));
    expect(
      () => DeviceFileContentPreview.fromMap(<String, Object?>{
        'kind': 'text',
        'path': '/tmp/private.txt',
        'sizeBytes': 1,
        'text': 'x',
      }),
      throwsFormatException,
    );
  });
}
