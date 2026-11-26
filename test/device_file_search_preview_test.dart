import 'package:arch_terminal/terminal/device_file_search_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only bounded find searches rooted at device storage', () {
    expect(
      isBoundedDeviceFileSearchCommand(
        'find /sdcard -maxdepth 3 -type f -iname "*test*" | head -n 20',
      ),
      isTrue,
    );
    expect(
      isBoundedDeviceFileSearchCommand('find / -type f | head -n 20'),
      isFalse,
    );
    expect(
      isBoundedDeviceFileSearchCommand(
        'find /sdcard -maxdepth 3 -type f -exec cat {} \\; | head -n 20',
      ),
      isFalse,
    );
  });

  test('recognizes a simple approved device-directory listing only', () {
    expect(
      deviceDirectoryFromListCommand('ls -F /sdcard/Download'),
      '/sdcard/Download',
    );
    expect(deviceDirectoryFromListCommand('ls /sdcard; whoami'), isNull);
    expect(deviceDirectoryFromListCommand('ls /tmp'), isNull);
  });

  test(
    'extracts only device paths, de-duplicates them, and honors its limit',
    () {
      final preview = parseDeviceFileSearchPreview(
        '\u001b[32m/sdcard/Download/test.png\u001b[0m\n'
        'find /sdcard -maxdepth 3 -type f | head -n 2\n'
        '/tmp/private.txt\n'
        '/sdcard/Download/test.png\n'
        '/sdcard/Pictures/a photo.jpg\n'
        '/sdcard/Documents/note.txt\n',
        maxResults: 2,
      );

      expect(preview.paths, <String>[
        '/sdcard/Download/test.png',
        '/sdcard/Pictures/a photo.jpg',
      ]);
      expect(preview.truncated, isTrue);
    },
  );

  test('keeps a bounded local preview of simple directory listing names', () {
    final result = parseDeviceDirectoryListingPreview(
      'notes.txt\nphoto.jpg\nfolder/\nnotes.txt\n',
      directory: '/sdcard/Download',
      maxResults: 2,
    );

    expect(result.paths, <String>[
      '/sdcard/Download/notes.txt',
      '/sdcard/Download/photo.jpg',
    ]);
    expect(result.truncated, isTrue);
  });

  test('quotes a selected device path before sending cd to the terminal', () {
    expect(
      terminalCdCommandForDevicePath("/sdcard/O'Brien/notes"),
      "cd -- '/sdcard/O'\\\"'\\\"'Brien/notes'",
    );
    expect(
      () => terminalCdCommandForDevicePath('/tmp/not-device-storage'),
      throwsArgumentError,
    );
  });

  test('reveals only selected device metadata in the terminal', () {
    expect(
      terminalRevealCommandForDevicePath('/sdcard/Download/test.png'),
      "ls -ld -- '/sdcard/Download/test.png'",
    );
    expect(
      () => terminalRevealCommandForDevicePath('/data/private.txt'),
      throwsArgumentError,
    );
  });
}
