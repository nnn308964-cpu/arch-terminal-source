import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(10240);
  final _arabicRunParagraphCache = ParagraphCache(2048);

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) return;
    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _arabicRunParagraphCache.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _arabicRunParagraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) return;
    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
    _arabicRunParagraphCache.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final builder = ParagraphBuilder(textStyle.getParagraphStyle());
    builder.pushStyle(
      textStyle.getTextStyle(textScaler: _textScaler),
    );
    builder.addText(test);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    final result = Size(
      paragraph.maxIntrinsicWidth / test.length,
      paragraph.height,
    );

    paragraph.dispose();
    return result;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _arabicRunParagraphCache.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.compactBlock:
        paint.style = PaintingStyle.fill;
        final width = _cellSize.width * 0.62;
        final height = _cellSize.height * 0.62;
        final compactOffset = Offset(
          offset.dx + (_cellSize.width - width) / 2,
          offset.dy + (_cellSize.height - height) / 2,
        );
        return canvas.drawRRect(
          RRect.fromRectAndRadius(
            compactOffset & Size(width, height),
            const Radius.circular(1.5),
          ),
          paint,
        );
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset =
        offset.translate(length * _cellSize.width, _cellSize.height);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(
      Rect.fromPoints(offset, endOffset),
      paint,
    );
  }

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line,
  ) {
    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;

    for (var i = 0; i < line.length; i++) {
      line.getCellData(i, cellData);
      final charWidth = cellData.content >> CellContent.widthShift;
      final cellOffset = offset.translate(i * cellWidth, 0);

      final charCode = cellData.content & CellContent.codepointMask;
      if (_isArabic(charCode)) {
        final end = _arabicRunEnd(line, i);
        _paintArabicRun(canvas, offset, line, i, end);
        i = end - 1;
        continue;
      }

      paintCell(canvas, cellOffset, cellData);

      if (charWidth == 2) {
        i++;
      }
    }
  }

  int _arabicRunEnd(BufferLine line, int start) {
    final cell = CellData.empty();
    var end = start;
    while (end < line.length) {
      line.getCellData(end, cell);
      final code = cell.content & CellContent.codepointMask;
      if (code != 0 && (_isArabic(code) || _isDigit(code) || !_isLatin(code))) {
        end++;
        continue;
      }
      break;
    }
    while (end > start) {
      line.getCellData(end - 1, cell);
      if (cell.content & CellContent.codepointMask != 0x20) break;
      end--;
    }
    return end;
  }

  void _paintArabicRun(Canvas canvas, Offset offset, BufferLine line, int start, int end) {
    final cellWidth = _cellSize.width;
    final logical = <int>[];
    final cells = <CellData>[];
    for (var index = start; index < end; index++) {
      final cell = CellData.empty();
      line.getCellData(index, cell);
      cells.add(cell);
      logical.add(cell.content & CellContent.codepointMask);
      paintCellBackground(canvas, offset.translate(index * cellWidth, 0), cell);
    }

    // Draw the whole logical run in one paragraph. Flutter's shaping and BiDi
    // engine can connect Arabic glyphs and preserve embedded Latin/digits;
    // BufferLine remains unchanged for terminal semantics and clipboard copy.
    final cell = cells.first;
    final flags = cell.flags;
    var color = flags & CellFlags.inverse == 0
        ? resolveForegroundColor(cell.foreground)
        : resolveBackgroundColor(cell.background);
    if (flags & CellFlags.faint != 0) color = color.withOpacity(0.5);
    final style = _textStyle.toTextStyle(
      color: color,
      bold: flags & CellFlags.bold != 0,
      italic: flags & CellFlags.italic != 0,
      underline: flags & CellFlags.underline != 0,
    );
    final text = String.fromCharCodes(logical);
    final key = Object.hash(cell.getHash(), text, _textScaler);
    var paragraph = _arabicRunParagraphCache.getLayoutFromCache(key);
    if (paragraph == null) {
      paragraph = _arabicRunParagraphCache.performAndCacheLayout(
        text,
        style,
        _textScaler,
        key,
        paragraphStyle: ParagraphStyle(
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          maxLines: 1,
        ),
      );
    }
    paragraph.layout(ParagraphConstraints(width: (end - start) * cellWidth));
    canvas.drawParagraph(paragraph, offset.translate(start * cellWidth, 0));
  }

  bool _isArabic(int codePoint) => codePoint >= 0x0621 && codePoint <= 0x065F;

  bool _isDigit(int codePoint) =>
      (codePoint >= 0x30 && codePoint <= 0x39) ||
      (codePoint >= 0x0660 && codePoint <= 0x0669) ||
      (codePoint >= 0x06F0 && codePoint <= 0x06F9);

  bool _isLatin(int codePoint) =>
      (codePoint >= 0x41 && codePoint <= 0x5A) || (codePoint >= 0x61 && codePoint <= 0x7A);

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(
    Canvas canvas,
    Offset offset,
    CellData cellData, {
    int? overrideCharCode,
  }) {
    final charCode = overrideCharCode ?? (cellData.content & CellContent.codepointMask);
    if (charCode == 0) return;

    final cacheKey = cellData.getHash() ^ charCode ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final cellFlags = cellData.flags;

      var color = cellFlags & CellFlags.inverse == 0
          ? resolveForegroundColor(cellData.foreground)
          : resolveBackgroundColor(cellData.background);

      if (cellData.flags & CellFlags.faint != 0) {
        color = color.withOpacity(0.5);
      }

      final style = _textStyle.toTextStyle(
        color: color,
        bold: cellFlags & CellFlags.bold != 0,
        italic: cellFlags & CellFlags.italic != 0,
        underline: cellFlags & CellFlags.underline != 0,
      );

      // Flutter does not draw an underline below a space which is not between
      // other regular characters. As only single characters are drawn, this
      // will never produce an underline below a space in the terminal. As a
      // workaround the regular space CodePoint 0x20 is replaced with
      // the CodePoint 0xA0. This is a non breaking space and a underline can be
      // drawn below it.
      var char = String.fromCharCode(charCode);
      if (cellFlags & CellFlags.underline != 0 && charCode == 0x20) {
        char = String.fromCharCode(0xA0);
      }

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
