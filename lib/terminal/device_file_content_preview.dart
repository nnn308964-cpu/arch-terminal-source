import 'dart:typed_data';

enum DeviceFileContentKind { text, image }

class DeviceFileContentPreview {
  const DeviceFileContentPreview._({
    required this.kind,
    required this.path,
    required this.sizeBytes,
    this.text,
    this.bytes,
    this.width,
    this.height,
  });

  final DeviceFileContentKind kind;
  final String path;
  final int sizeBytes;
  final String? text;
  final Uint8List? bytes;
  final int? width;
  final int? height;

  factory DeviceFileContentPreview.fromMap(Map<String, Object?> value) {
    final kind = switch (value['kind']?.toString()) {
      'text' => DeviceFileContentKind.text,
      'image' => DeviceFileContentKind.image,
      _ => throw const FormatException('Unsupported local file preview kind'),
    };
    final path = value['path']?.toString().trim() ?? '';
    final sizeBytes = (value['sizeBytes'] as num?)?.toInt() ?? -1;
    if (!RegExp(r'^/sdcard(?:/[^\n\r]*)?$').hasMatch(path) || sizeBytes < 1) {
      throw const FormatException('Invalid local file preview payload');
    }
    if (kind == DeviceFileContentKind.text) {
      final text = value['text']?.toString();
      if (text == null) throw const FormatException('Missing text preview');
      return DeviceFileContentPreview._(
        kind: kind,
        path: path,
        sizeBytes: sizeBytes,
        text: text,
      );
    }
    final rawBytes = value['bytes'];
    final bytes = switch (rawBytes) {
      Uint8List value => value,
      List value => Uint8List.fromList(
        value.cast<num>().map((v) => v.toInt()).toList(),
      ),
      _ => null,
    };
    final width = (value['width'] as num?)?.toInt();
    final height = (value['height'] as num?)?.toInt();
    if (bytes == null ||
        bytes.isEmpty ||
        width == null ||
        height == null ||
        width < 1 ||
        height < 1) {
      throw const FormatException('Missing image preview');
    }
    return DeviceFileContentPreview._(
      kind: kind,
      path: path,
      sizeBytes: sizeBytes,
      bytes: bytes,
      width: width,
      height: height,
    );
  }
}
