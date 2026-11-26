import 'inline_terminal_image.dart';

class InlineImageQueue {
  InlineImageQueue({required this.maxImages});

  final int maxImages;
  final List<TerminalInlineImage> _images = <TerminalInlineImage>[];

  bool get isEmpty => _images.isEmpty;
  TerminalInlineImage get last => _images.last;

  void addAll(Iterable<TerminalInlineImage> images) {
    _images.addAll(images);
    if (_images.length > maxImages) {
      _images.removeRange(0, _images.length - maxImages);
    }
  }

  void removeLast() {
    if (_images.isNotEmpty) _images.removeLast();
  }

  void clear() => _images.clear();
}
