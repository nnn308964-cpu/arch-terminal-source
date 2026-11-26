enum TerminalCursorType {
  block,

  /// A smaller filled block centred in the current character cell.
  /// It advances one cell with the terminal cursor, like a compact mobile
  /// terminal caret, without covering the whole line height.
  compactBlock,

  underline,

  verticalBar,
}
