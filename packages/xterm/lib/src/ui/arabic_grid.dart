import 'package:arabic_bidi/arabic_bidi.dart';

/// Converts an Arabic-dominant logical grid run into visual LTR cells. This is
/// used by the renderer only; terminal buffers keep the original text.
abstract final class ArabicGridText {
  static bool isArabic(int codePoint) => codePoint >= 0x0621 && codePoint <= 0x065F;

  static bool isDigit(int codePoint) =>
      (codePoint >= 0x30 && codePoint <= 0x39) ||
      (codePoint >= 0x0660 && codePoint <= 0x0669) ||
      (codePoint >= 0x06F0 && codePoint <= 0x06F9);

  static bool isLatin(int codePoint) =>
      (codePoint >= 0x41 && codePoint <= 0x5A) || (codePoint >= 0x61 && codePoint <= 0x7A);

  static bool canJoinArabicGridRun(int codePoint) =>
      isArabic(codePoint) || isDigit(codePoint) || !isLatin(codePoint);

  /// Shapes every Arabic token then reverses token order. Digit tokens preserve
  /// their own character order, e.g. `ملف 123 محفوظ` paints as
  /// `ظوفحم 123 فلم` in an LTR grid and reads correctly right-to-left.
  static List<int> visualCells(List<int> logical) {
    if (logical.isEmpty) return const <int>[];
    final tokens = <_GridToken>[];
    var kind = _kindOf(logical.first);
    var start = 0;
    for (var index = 1; index < logical.length; index++) {
      final next = _kindOf(logical[index]);
      if (next != kind) {
        tokens.add(_GridToken(kind, logical.sublist(start, index)));
        kind = next;
        start = index;
      }
    }
    tokens.add(_GridToken(kind, logical.sublist(start)));

    return tokens.reversed.expand((token) {
      if (token.kind != _GridTokenKind.arabic) return token.runes;
      final shaped = ArabicBidi.reshape(String.fromCharCodes(token.runes));
      return shaped.runes.toList(growable: false).reversed;
    }).toList(growable: false);
  }

  static _GridTokenKind _kindOf(int codePoint) {
    if (isArabic(codePoint)) return _GridTokenKind.arabic;
    if (isDigit(codePoint)) return _GridTokenKind.number;
    return _GridTokenKind.neutral;
  }
}

enum _GridTokenKind { arabic, number, neutral }

class _GridToken {
  const _GridToken(this.kind, this.runes);
  final _GridTokenKind kind;
  final List<int> runes;
}
