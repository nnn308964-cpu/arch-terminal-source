import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Emits only the newly appended part of a mobile IME composition.
///
/// Terminal applications need each committed character to reach the PTY so
/// their cursor advances normally. Keeping the composition as a visual overlay
/// leaves the terminal cursor behind until the keyboard closes.
class ComposingTextRelay {
  String _forwarded = '';

  String takeDelta(String composingText) {
    if (!composingText.startsWith(_forwarded)) {
      // Prediction revisions are handled by the native keyboard on the next
      // committed update. Do not replay an entire word into the PTY.
      _forwarded = composingText;
      return '';
    }

    final delta = composingText.substring(_forwarded.length);
    _forwarded = composingText;
    return delta;
  }

  bool get hasForwardedText => _forwarded.isNotEmpty;

  void reset() => _forwarded = '';
}

class CustomTextEdit extends StatefulWidget {
  CustomTextEdit({
    super.key,
    required this.child,
    required this.onInsert,
    required this.onDelete,
    required this.onComposing,
    required this.onAction,
    required this.onKeyEvent,
    required this.focusNode,
    this.autofocus = false,
    this.readOnly = false,
    // this.initEditingState = TextEditingValue.empty,
    this.inputType = TextInputType.text,
    this.inputAction = TextInputAction.newline,
    this.keyboardAppearance = Brightness.light,
    this.deleteDetection = false,
  });

  final Widget child;

  final void Function(String) onInsert;

  final void Function() onDelete;

  final void Function(String?) onComposing;

  final void Function(TextInputAction) onAction;

  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  final FocusNode focusNode;

  final bool autofocus;

  final bool readOnly;

  final TextInputType inputType;

  final TextInputAction inputAction;

  final Brightness keyboardAppearance;

  final bool deleteDetection;

  @override
  CustomTextEditState createState() => CustomTextEditState();
}

class CustomTextEditState extends State<CustomTextEdit> with TextInputClient {
  static const _deleteMarker = '\u2060';
  static const _spaceCommitDelay = Duration(milliseconds: 180);

  TextInputConnection? _connection;
  final _composingRelay = ComposingTextRelay();
  Timer? _pendingSpaceCommit;

  @override
  void initState() {
    widget.focusNode.addListener(_onFocusChange);
    super.initState();
  }

  @override
  void didUpdateWidget(CustomTextEdit oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else {
      if (oldWidget.readOnly && widget.focusNode.hasFocus) {
        _openInputConnection();
      }
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _cancelPendingSpace();
    _closeInputConnectionIfNeeded();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }

  bool get hasInputConnection => _connection != null && _connection!.attached;

  void requestKeyboard() {
    _cancelPendingSpace();
    if (widget.focusNode.hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void closeKeyboard() {
    _cancelPendingSpace();
    _clearComposingWithoutInput();
    if (hasInputConnection) {
      _connection?.close();
      _connection = null;
    }
  }

  void setEditingState(TextEditingValue value) {
    _currentEditingState = value;
    _connection?.setEditingState(value);
  }

  void setEditableRect(Rect rect, Rect caretRect) {
    if (!hasInputConnection) {
      return;
    }

    _connection?.setEditableSizeAndTransform(
      rect.size,
      Matrix4.translationValues(0, 0, 0),
    );

    _connection?.setCaretRect(caretRect);
  }

  void _onFocusChange() {
    _openOrCloseInputConnectionIfNeeded();
  }

  KeyEventResult _onKeyEvent(FocusNode focusNode, KeyEvent event) {
    if (_currentEditingState.composing.isCollapsed) {
      return widget.onKeyEvent(focusNode, event);
    }

    return KeyEventResult.skipRemainingHandlers;
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (widget.focusNode.hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!widget.focusNode.hasFocus) {
      _closeInputConnectionIfNeeded();
    }
  }

  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  void _openInputConnection() {
    _cancelPendingSpace();
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (hasInputConnection) {
      _connection!.show();
    } else {
      final config = TextInputConfiguration(
        inputType: widget.inputType,
        inputAction: widget.inputAction,
        keyboardAppearance: widget.keyboardAppearance,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
      );

      _connection = TextInput.attach(this, config);

      _connection!.show();

      // setEditableRect(Rect.zero, Rect.zero);

      _connection!.setEditingState(_initEditingState);
    }
  }

  void _closeInputConnectionIfNeeded() {
    _cancelPendingSpace();
    if (_connection != null && _connection!.attached) {
      _connection!.close();
      _connection = null;
    }
  }

  TextEditingValue get _initEditingState => widget.deleteDetection
      ? const TextEditingValue(
          // This invisible marker preserves backspace detection without ever
          // becoming a space in the terminal when Android closes its IME.
          text: _deleteMarker,
          selection: TextSelection.collapsed(offset: 1),
        )
      : const TextEditingValue(
          text: '',
          selection: TextSelection.collapsed(offset: 0),
        );

  late var _currentEditingState = _initEditingState.copyWith();

  @override
  TextEditingValue? get currentTextEditingValue {
    return _currentEditingState;
  }

  @override
  AutofillScope? get currentAutofillScope {
    return null;
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    _currentEditingState = value;

    if (!_currentEditingState.composing.isCollapsed) {
      final composingText = _currentEditingState.composing.textInside(
        _currentEditingState.text,
      );
      final delta = _composingRelay.takeDelta(composingText);
      if (delta.isNotEmpty) {
        widget.onInsert(delta);
      }
      // PTY echo now owns the displayed text and cursor position; do not draw
      // a duplicate IME overlay over the real terminal cells.
      widget.onComposing(null);
      return;
    }

    widget.onComposing(null);

    // The complete composition was already forwarded character by character.
    // Ignore the final collapsed callback so closing the keyboard cannot replay
    // text or emit the old deletion-detection padding as a space.
    if (_composingRelay.hasForwardedText) {
      _composingRelay.reset();
      _resetEditingState();
      return;
    }

    if (_currentEditingState.text.length < _initEditingState.text.length) {
      if (!_cancelPendingSpace()) {
        widget.onDelete();
      }
    } else {
      var textDelta = _currentEditingState.text.substring(
        _initEditingState.text.length,
      );

      if (textDelta.startsWith(_deleteMarker)) {
        textDelta = textDelta.substring(_deleteMarker.length);
      }

      _commitTextDelta(textDelta);
    }

    if (_currentEditingState.composing.isCollapsed &&
        _currentEditingState.text != _initEditingState.text) {
      _resetEditingState();
    }
  }

  void _resetEditingState() {
    _currentEditingState = _initEditingState;
    _connection?.setEditingState(_currentEditingState);
  }

  void _clearComposingWithoutInput() {
    _composingRelay.reset();
    widget.onComposing(null);
    _currentEditingState = _initEditingState;
  }

  /// Android IMEs can emit one final literal space while their window is being
  /// dismissed. Delay only a standalone space briefly; a following character
  /// commits it normally, while [onKeyboardHide] cancels the spurious event.
  void _commitTextDelta(String textDelta) {
    if (textDelta.isEmpty) {
      return;
    }

    if (textDelta == ' ') {
      _cancelPendingSpace();
      _pendingSpaceCommit = Timer(_spaceCommitDelay, () {
        _pendingSpaceCommit = null;
        widget.onInsert(' ');
      });
      return;
    }

    if (_cancelPendingSpace()) {
      widget.onInsert(' ');
    }
    widget.onInsert(textDelta);
  }

  bool _cancelPendingSpace() {
    final hadPendingSpace = _pendingSpaceCommit != null;
    _pendingSpaceCommit?.cancel();
    _pendingSpaceCommit = null;
    return hadPendingSpace;
  }

  /// Called from the view-inset observer when the system keyboard hides.
  void onKeyboardHide() {
    _cancelPendingSpace();
    _clearComposingWithoutInput();
    _resetEditingState();
  }

  @override
  void performAction(TextInputAction action) {
    // print('performAction $action');
    widget.onAction(action);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // print('updateFloatingCursor $point');
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // print('showAutocorrectionPromptRect');
  }

  @override
  void connectionClosed() {
    _cancelPendingSpace();
    _connection = null;
    _clearComposingWithoutInput();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    // print('performPrivateCommand $action');
  }

  @override
  void insertTextPlaceholder(Size size) {
    // print('insertTextPlaceholder');
  }

  @override
  void removeTextPlaceholder() {
    // print('removeTextPlaceholder');
  }

  @override
  void showToolbar() {
    // print('showToolbar');
  }
}
