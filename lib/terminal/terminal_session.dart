import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kyroon_pty/kyroon_pty.dart';

class TerminalSession {
  TerminalSession({
    required this.onOutput,
    required this.onExit,
    required this.onError,
  });

  final void Function(String text) onOutput;
  final void Function(int code) onExit;
  final void Function(Object error) onError;

  Pty? _pty;
  StreamSubscription<String>? _outputSubscription;
  bool _running = false;
  bool _stopping = false;

  bool get isRunning => _running;

  Future<void> start({
    required String executable,
    List<String> arguments = const <String>[],
    Map<String, String>? environment,
    String? workingDirectory,
    int rows = 24,
    int columns = 80,
  }) async {
    if (_running) return;

    try {
      _stopping = false;
      final pty = Pty.start(
        executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: <String, String>{
          ...Platform.environment,
          'TERM': 'xterm-256color',
          'LANG': 'C.UTF-8',
          'LC_ALL': 'C.UTF-8',
          ...?environment,
        },
        rows: rows,
        columns: columns,
      );
      _pty = pty;
      _running = true;

      // The stream decoder is stateful, so UTF-8 glyphs split across chunks
      // (Arabic combining marks, box drawing and emoji) are not corrupted.
      _outputSubscription = pty.output
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            onOutput,
            onError: onError,
            onDone: () {},
            cancelOnError: false,
          );

      unawaited(() async {
        try {
          final code = await pty.exitCode;
          if (!_stopping) onExit(code);
          _running = false;
        } catch (error) {
          if (!_stopping) onError(error);
          _running = false;
        }
      }());
    } catch (error) {
      _running = false;
      _pty = null;
      onError(error);
      rethrow;
    }
  }

  void write(String text) {
    final pty = _pty;
    if (pty == null || !_running) return;
    pty.write(Uint8List.fromList(utf8.encode(text)));
  }

  void resize({required int rows, required int columns}) {
    final pty = _pty;
    if (pty == null || !_running) return;
    pty.resize(rows, columns);
  }

  Future<void> stop() async {
    final pty = _pty;
    _stopping = true;
    _running = false;
    _pty = null;
    if (pty != null) {
      try {
        pty.kill();
      } catch (_) {
        // The child may have exited between the UI state check and cleanup.
      }
      try {
        await _outputSubscription?.cancel();
      } finally {
        _outputSubscription = null;
        // kyroon_pty closes its native handles after the child exit stream ends.
      }
    }
  }
}
