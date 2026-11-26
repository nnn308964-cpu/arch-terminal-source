class DeepTranscriptBuffer {
  DeepTranscriptBuffer({required this.maxChars});

  final int maxChars;
  String _text = '';

  void append(String text) {
    if (text.isEmpty) return;
    _text += text;
    if (_text.length > maxChars) {
      _text = _text.substring(_text.length - maxChars);
    }
  }

  String take() {
    final result = _text;
    _text = '';
    return result;
  }
}
