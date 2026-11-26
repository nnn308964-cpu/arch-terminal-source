import 'package:flutter/material.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';
import 'package:xterm/src/ui/render.dart';

import 'package:arch_terminal/main.dart';
import 'package:arch_terminal/rootfs_storage_sheet.dart';
import 'package:arch_terminal/terminal/automatic_start_queue.dart';
import 'package:arch_terminal/terminal/arch_setup_gate.dart';
import 'package:arch_terminal/terminal/deep_transcript_buffer.dart';
import 'package:arch_terminal/terminal/device_file_content_preview.dart';
import 'package:arch_terminal/terminal/device_file_search_preview.dart';
import 'package:arch_terminal/terminal/inline_terminal_image.dart';
import 'package:arch_terminal/terminal/inline_image_queue.dart';
import 'package:arch_terminal/terminal/pacman_network_diagnostic.dart';
import 'package:arch_terminal/terminal/terminal_copy_text.dart';
import 'package:arch_terminal/terminal/terminal_preferences.dart';
import 'package:arch_terminal/terminal/triple_tap_gate.dart';

void main() {
  test('triple tap gate activates only on the third nearby tap and resets after activation', () {
    final gate = TripleTapGate();
    final start = DateTime(2026, 8, 21, 23, 0);

    expect(gate.register(start), isFalse);
    expect(
      gate.register(start.add(const Duration(milliseconds: 300))),
      isFalse,
    );
    expect(gate.register(start.add(const Duration(milliseconds: 700))), isTrue);
    expect(
      gate.register(start.add(const Duration(milliseconds: 800))),
      isFalse,
    );
  });

  test('triple tap gate discards a delayed sequence', () {
    final gate = TripleTapGate();
    final start = DateTime(2026, 8, 21, 23, 0);

    expect(gate.register(start), isFalse);
    expect(
      gate.register(start.add(const Duration(milliseconds: 200))),
      isFalse,
    );
    expect(
      gate.register(start.add(const Duration(milliseconds: 1400))),
      isFalse,
    );
  });

  test('copy text removes the interactive Bash prompt but preserves commands and output', () {
    final copied = withoutInteractivePrompts(
      '[root@localhost ~]# grep --color=auto root /etc/passwd\n'
      'root:x:0:0::/root:/usr/bin/bash\n'
      '[root@localhost ~]# ',
    );

    expect(copied, isNot(contains('[root@localhost ~]#')));
    expect(copied, contains('grep --color=auto root /etc/passwd'));
    expect(copied, contains('root:x:0:0::/root:/usr/bin/bash'));
  });

  test('IME relay sends Arabic, English, symbols, and emoji deltas then clears on keyboard close', () {
    final relay = ComposingTextRelay();

    expect(relay.takeDelta('ب'), 'ب');
    expect(relay.takeDelta('بت'), 'ت');
    expect(relay.takeDelta('بتع'), 'ع');
    expect(relay.hasForwardedText, isTrue);

    relay.reset();
    expect(relay.hasForwardedText, isFalse);
    expect(relay.takeDelta('A'), 'A');
    expect(relay.takeDelta('A/'), '/');
    expect(relay.takeDelta('A/@'), '@');
    expect(relay.takeDelta('A/@🙂'), '🙂');
  });

  testWidgets(
    'mobile IME forwards composition deltas once and closing the keyboard inserts nothing',
    (tester) async {
      final inserted = <String>[];
      final composing = <String?>[];
      final focusNode = FocusNode();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomTextEdit(
            focusNode: focusNode,
            onInsert: inserted.add,
            onDelete: () {},
            onComposing: composing.add,
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );

      focusNode.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u2060ب',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 1, end: 2),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u2060بت',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 1, end: 3),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u2060بت',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );

      expect(inserted, <String>['ب', 'ت']);
      expect(composing.last, isNull);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '\u2060A/@🙂',
          selection: TextSelection.collapsed(offset: 6),
        ),
      );
      expect(inserted, <String>['ب', 'ت', 'A/@🙂']);

      tester
          .state<CustomTextEditState>(find.byType(CustomTextEdit))
          .closeKeyboard();
      await tester.pump();
      expect(inserted, <String>['ب', 'ت', 'A/@🙂']);
    },
  );

  testWidgets(
    'keyboard hide cancels Android IME final space while a real space is preserved',
    (tester) async {
      final inserted = <String>[];
      final focusNode = FocusNode();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomTextEdit(
            focusNode: focusNode,
            onInsert: inserted.add,
            onDelete: () {},
            onComposing: (_) {},
            onAction: (_) {},
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: ' ',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      tester
          .state<CustomTextEditState>(find.byType(CustomTextEdit))
          .onKeyboardHide();
      await tester.pump(const Duration(milliseconds: 250));
      expect(inserted, isEmpty);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: ' ',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(inserted, <String>[' ']);
    },
  );

  test('iTerm inline image is previewed separately while ANSI terminal text remains logical', () {
    final decoder = InlineTerminalImageDecoder();
    const imagePayload =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';

    final first = decoder.consume(
      'before \x1b[31mred\x1b[0m\x1b]1337;File=inline=1:$imagePayload',
    );
    expect(first.terminalText, 'before \x1b[31mred\x1b[0m');
    expect(first.images, isEmpty);

    final second = decoder.consume('\x07 after');
    expect(second.terminalText, ' after');
    expect(second.images, hasLength(1));
    expect(second.images.single.bytes, isNotEmpty);
  });

  test('inline images preserve mixed Arabic ANSI text and reject oversized payloads', () {
    final decoder = InlineTerminalImageDecoder();
    const imagePayload =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';
    final first = decoder.consume(
      'مرحبا \x1b[36mworld 42\x1b[0m \x1b]1337;File=inline=1:$imagePayload\x07',
    );

    expect(first.terminalText, 'مرحبا \x1b[36mworld 42\x1b[0m ');
    expect(first.images, hasLength(1));

    final tooLarge = List<String>.filled(2 * 1024 * 1024 + 1, 'A').join();
    final rejected = decoder.consume('\x1b]1337;File=inline=1:$tooLarge\x07');
    expect(rejected.terminalText, '[inline image rejected]');
    expect(rejected.terminalText, isNot(contains(tooLarge.substring(0, 32))));
    expect(rejected.images, isEmpty);
  });

  test('deep transcript stores only mixed Arabic ANSI terminal text, never an inline image payload', () {
    final decoder = InlineTerminalImageDecoder();
    final transcript = DeepTranscriptBuffer(maxChars: 1024);
    const payload =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';
    final result = decoder.consume(
      'مرحبا \x1b[32mArch 42\x1b[0m \x1b]1337;File=inline=1:$payload\x07',
    );

    transcript.append(result.terminalText);
    final stored = transcript.take();

    expect(stored, 'مرحبا \x1b[32mArch 42\x1b[0m ');
    expect(stored, isNot(contains(payload.substring(0, 24))));
  });

  testWidgets(
    'image layer shows a bounded preview without replacing its terminal child',
    (tester) async {
      var closed = false;
      const payload =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';
      final decoded = InlineTerminalImageDecoder().consume(
        '\x1b[33mColor\x1b[0m مرحبا Arch 42 \x1b]1337;File=inline=1:$payload\x07',
      );
      final terminal = Terminal();
      terminal.resize(80, 24);
      terminal.write(decoded.terminalText);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: TerminalImageLayer(
                image: decoded.images.single,
                onClose: () => closed = true,
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TerminalView(terminal),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TerminalView), findsOneWidget);
      expect(find.byType(InlineImagePreview), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('inline-image-preview-viewport'))),
        const Size(160, 160),
      );
      final copied = terminal.buffer.getText(
        BufferRangeLine(const CellOffset(0, 0), const CellOffset(80, 0)),
      );
      final foreground = terminal.lines[0].getForeground(0);
      expect(copied, contains('مرحبا'));
      expect(copied, contains('Color'));
      expect(copied, contains('Arch 42'));
      expect(copied, isNot(contains(payload.substring(0, 24))));
      expect(foreground & CellColor.typeMask, CellColor.named);
      expect(foreground & CellColor.valueMask, NamedColor.yellow);
      tester.widget<IconButton>(find.byType(IconButton)).onPressed!();
      expect(closed, isTrue);
    },
  );

  test(
    'automatic start queue permits a retry after an unsuccessful attempt',
    () {
      final queue = AutomaticStartQueue();

      expect(queue.tryReserve(), isTrue);
      expect(queue.tryReserve(), isFalse);

      // تمثل هذه العملية اكتمال محاولة بدء فشلت داخل _startSession.
      queue.release();

      expect(queue.isReserved, isFalse);
      expect(queue.tryReserve(), isTrue);
    },
  );

  test('automatic start queue remains reserved after a successful attempt', () {
    final queue = AutomaticStartQueue();

    expect(queue.tryReserve(), isTrue);

    // تمثل هذه الحالة جلسة بدأت بنجاح؛ لا يصح تحرير الحجز هنا.
    expect(queue.isReserved, isTrue);
    expect(queue.tryReserve(), isFalse);
  });

  test('automatic start reservation is released only when starting does not leave a session running', () {
    expect(
      shouldReleaseAutomaticStartReservation(
        startSucceeded: false,
        sessionRunning: false,
      ),
      isTrue,
    );
    expect(
      shouldReleaseAutomaticStartReservation(
        startSucceeded: true,
        sessionRunning: false,
      ),
      isTrue,
    );
    expect(
      shouldReleaseAutomaticStartReservation(
        startSucceeded: true,
        sessionRunning: true,
      ),
      isFalse,
    );
  });

  test('automatic start remains blocked after a deliberate notification end until the user requests setup again', () {
    expect(canQueueAutomaticStart(manualEndRequested: true), isFalse);
    expect(canQueueAutomaticStart(manualEndRequested: false), isTrue);
  });

  test('notification end is resumed only when the next app launch records a restart request', () {
    expect(shouldResumeAfterNotificationEnd(restartPending: true), isTrue);
    expect(shouldResumeAfterNotificationEnd(restartPending: false), isFalse);
  });

  test('reconnect is allowed only for a protected lost session', () {
    expect(
      shouldReconnectAfterProcessLoss(
        backgroundProtectionEnabled: true,
        reconnectPending: true,
        serviceActive: false,
        manualEndRequested: false,
        sessionRunning: false,
      ),
      isTrue,
    );
    expect(
      shouldReconnectAfterProcessLoss(
        backgroundProtectionEnabled: true,
        reconnectPending: true,
        serviceActive: false,
        manualEndRequested: true,
        sessionRunning: false,
      ),
      isFalse,
    );
    expect(
      shouldReconnectAfterProcessLoss(
        backgroundProtectionEnabled: true,
        reconnectPending: true,
        serviceActive: true,
        manualEndRequested: false,
        sessionRunning: false,
      ),
      isFalse,
    );
  });

  test('pacman DNS failure exposes resolv.conf and the configured mirror', () {
    final diagnostic = pacmanNetworkDiagnostic(
      output: "error: failed retrieving file 'alarm.db' from mirror.archlinuxarm.org : Could not resolve host: mirror.archlinuxarm.org",
      arabicUi: false,
      dnsConfigured: true,
      mirrorUrl: 'http://mirror.archlinuxarm.org/\$arch/\$repo',
    );

    expect(diagnostic, contains('resolv.conf=/etc/resolv.conf'));
    expect(diagnostic, contains('mirror=http://mirror.archlinuxarm.org'));
    expect(diagnostic, contains('DNS=ready'));
  });

  test('ARM32 launch diagnosis identifies every required boot path', () {
    final text = arm32LaunchDiagnosisText(<String, Object?>{
      'prootReady': true,
      'prootTmpWritable': true,
      'guestEnvReady': true,
      'guestLoaderReady': true,
      'guestLoaderViaLibReady': true,
      'rootfsPath': '/data/user/0/example/files/arch/armeabi-v7a',
      'prootPath': '/data/user/0/example/files/bin/armeabi-v7a/proot',
      'prootTmpPath': '/data/user/0/example/files/proot-tmp/armeabi-v7a',
      'guestEnvPath': '/data/user/0/example/files/arch/armeabi-v7a/usr/bin/env',
      'guestLoaderViaLibPath':
          '/data/user/0/example/files/arch/armeabi-v7a/lib/ld-linux-armhf.so.3',
    }, arabicUi: false);

    expect(text, contains('PRoot=ready'));
    expect(text, contains('tmp=writable'));
    expect(text, contains('ld-linux=ready'));
    expect(text, contains('/arch/armeabi-v7a'));
    expect(text, contains('/proot-tmp/armeabi-v7a'));
    expect(text, contains('/usr/bin/env'));
    expect(text, contains('/lib/ld-linux-armhf.so.3'));
  });

  test('Arch setup gate requires every permission before it can reuse or download a RootFS', () {
    expect(
      decideArchSetupAction(
        notificationsGranted: true,
        batteryOptimizationIgnored: true,
        publicStorageGranted: false,
        archInstalled: false,
        prootAvailable: true,
        publicArchivePresent: true,
      ),
      ArchSetupAction.openPermissionGate,
    );
    expect(
      decideArchSetupAction(
        notificationsGranted: true,
        batteryOptimizationIgnored: true,
        publicStorageGranted: true,
        archInstalled: true,
        prootAvailable: true,
        publicArchivePresent: true,
      ),
      ArchSetupAction.useInstalledRootfs,
    );
    expect(
      decideArchSetupAction(
        notificationsGranted: true,
        batteryOptimizationIgnored: true,
        publicStorageGranted: true,
        archInstalled: false,
        prootAvailable: true,
        publicArchivePresent: true,
      ),
      ArchSetupAction.reusePublicArchive,
    );
    expect(
      decideArchSetupAction(
        notificationsGranted: true,
        batteryOptimizationIgnored: true,
        publicStorageGranted: true,
        archInstalled: false,
        prootAvailable: true,
        publicArchivePresent: false,
      ),
      ArchSetupAction.downloadRootfs,
    );
  });

  test('Arch permission gate opens the first missing permission in a fixed sequence', () {
    expect(
      nextArchPermissionStep(
        notificationsGranted: false,
        batteryOptimizationIgnored: false,
        publicStorageGranted: false,
      ),
      ArchPermissionStep.notification,
    );
    expect(
      nextArchPermissionStep(
        notificationsGranted: true,
        batteryOptimizationIgnored: false,
        publicStorageGranted: false,
      ),
      ArchPermissionStep.battery,
    );
    expect(
      nextArchPermissionStep(
        notificationsGranted: true,
        batteryOptimizationIgnored: true,
        publicStorageGranted: false,
      ),
      ArchPermissionStep.sharedStorage,
    );
    expect(
      nextArchPermissionStep(
        notificationsGranted: true,
        batteryOptimizationIgnored: true,
        publicStorageGranted: true,
      ),
      ArchPermissionStep.ready,
    );
  });

  test('builds an ARM32 PRoot command with a writable guest tmp and guest-side loader resolution', () {
    final arguments = buildArchProotArguments(
      rootfsPath: '/data/user/0/example/files/arch/armeabi-v7a',
      prootTmpPath: '/data/user/0/example/files/proot-tmp/armeabi-v7a',
      storagePath: '/storage/emulated/0',
      abi: 'armeabi-v7a',
    );

    expect(
      arguments,
      containsAllInOrder(<String>[
        '-r',
        '/data/user/0/example/files/arch/armeabi-v7a',
        '-b',
        '/data/user/0/example/files/proot-tmp/armeabi-v7a:/tmp',
        '/usr/bin/env',
        '-i',
        '/bin/bash',
        '--login',
      ]),
    );
    expect(arguments, isNot(contains('/usr/lib/ld-linux-armhf.so.3')));
    expect(
      arguments,
      isNot(
        contains('/data/user/0/example/files/arch/armeabi-v7a/usr/lib:/lib'),
      ),
    );
    expect(arguments, contains('/storage/emulated/0:/sdcard'));
  });

  test(
    'does not bind device storage into PRoot until Android access is granted',
    () {
      final arguments = buildArchProotArguments(
        rootfsPath: '/data/user/0/example/files/arch/arm64-v8a',
        prootTmpPath: '/data/user/0/example/files/proot-tmp/arm64-v8a',
        storagePath: '/storage/emulated/0',
        abi: 'arm64-v8a',
        bindDeviceStorage: false,
      );

      expect(arguments, isNot(contains('/storage/emulated/0:/sdcard')));
      expect(arguments, containsAll(<String>['-r', '/bin/bash', '--login']));
    },
  );

  test(
    'keeps logical Arabic text in the terminal buffer for copy and paste',
    () {
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 24);
      terminal.write('Arch يعمل بنجاح');

      final text = terminal.buffer.getText(
        BufferRangeLine(const CellOffset(0, 0), const CellOffset(80, 0)),
      );
      expect(text, contains('يعمل بنجاح'));
    },
  );

  test('xterm copy keeps Arabic ANSI text while an iTerm image is removed from the logical buffer', () {
    const source = 'مرحبا Arch 42';
    const payload =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';
    final result = InlineTerminalImageDecoder().consume(
      '$source \x1b[35mملون\x1b[0m \x1b]1337;File=inline=1:$payload\x07',
    );
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24);
    terminal.write(result.terminalText);

    final copied = terminal.buffer.getText(
      BufferRangeLine(const CellOffset(0, 0), const CellOffset(80, 0)),
    );
    expect(result.images, hasLength(1));
    expect(copied, contains(source));
    expect(copied, contains('ملون'));
    expect(copied, isNot(contains(payload.substring(0, 24))));
  });

  test('xterm interprets ANSI foreground color for Arabic output beside an inline image', () {
    const payload =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL4WQAAAABJRU5ErkJggg==';
    final decoded = InlineTerminalImageDecoder().consume(
      '\x1b[31mأحمر\x1b[0m \x1b]1337;File=inline=1:$payload\x07',
    );
    final terminal = Terminal(maxLines: 100);
    terminal.resize(80, 24);
    terminal.write(decoded.terminalText);

    final foreground = terminal.lines[0].getForeground(0);
    expect(decoded.images, hasLength(1));
    expect(foreground & CellColor.typeMask, CellColor.named);
    expect(foreground & CellColor.valueMask, NamedColor.red);
  });

  test('rejected oversized iTerm image stores only the bounded rejection marker in deep transcript', () {
    final payload = List<String>.filled(2 * 1024 * 1024 + 1, 'A').join();
    final result = InlineTerminalImageDecoder().consume(
      'start\x1b]1337;File=inline=1:$payload\x07end',
    );
    final transcript = DeepTranscriptBuffer(maxChars: 1024);
    transcript.append(result.terminalText);

    final stored = transcript.take();
    expect(stored, 'start[inline image rejected]end');
    expect(stored, isNot(contains(payload.substring(0, 24))));
  });

  test('inline image queue retains only the newest bounded previews', () {
    final queue = InlineImageQueue(maxImages: 2);
    final first = TerminalInlineImage(Uint8List.fromList(<int>[1]));
    final second = TerminalInlineImage(Uint8List.fromList(<int>[2]));
    final third = TerminalInlineImage(Uint8List.fromList(<int>[3]));

    queue.addAll(<TerminalInlineImage>[first, second, third]);

    expect(queue.last.bytes, Uint8List.fromList(<int>[3]));
    queue.removeLast();
    expect(queue.last.bytes, Uint8List.fromList(<int>[2]));
  });

  test(
    'inline image decoder rejects PNG dimensions above the pixel safety limit',
    () {
      final png = Uint8List(24);
      png.setAll(0, <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
      png[16] = 0x00;
      png[17] = 0x00;
      png[18] = 0x07;
      png[19] = 0xd0; // 2000 px
      png[20] = 0x00;
      png[21] = 0x00;
      png[22] = 0x07;
      png[23] = 0xd0; // 2000 px, 4,000,000 total

      final result = InlineTerminalImageDecoder().consume(
        '\x1b]1337;File=inline=1:${base64Encode(png)}\x07',
      );
      expect(result.images, isEmpty);
      expect(
        result.terminalText,
        '[inline image rejected: image dimensions exceed the safe limit]',
      );
    },
  );

  test('oversized inline image payload is rejected within the documented responsiveness budget', () {
    final payload = List<String>.filled(2 * 1024 * 1024 + 1, 'A').join();
    final stopwatch = Stopwatch()..start();
    final result = InlineTerminalImageDecoder().consume(
      '\x1b]1337;File=inline=1:$payload\x07',
    );
    stopwatch.stop();

    expect(result.images, isEmpty);
    expect(result.terminalText, '[inline image rejected]');
    // This is deliberately generous for a loaded mobile device. The decoder
    // only examines metadata and never Base64-decodes an oversized payload.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  testWidgets(
    'setup failure banner shows the root cause and recovery guidance',
    (WidgetTester tester) async {
      const progress = SetupProgressViewModel(
        running: false,
        phase: 'error',
        message: 'Arch Linux setup failed during extracting.',
        percent: null,
        downloaded: 0,
        total: -1,
        speed: 0,
        failureDetail: 'IOException: There is not enough internal space to extract Arch Linux.',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: SetupProgressBanner(progress: progress, arabicUi: false),
        ),
      );

      expect(find.byKey(const Key('setup-failure-detail')), findsOneWidget);
      expect(find.textContaining('free internal storage'), findsOneWidget);
      expect(find.textContaining('checkpoint'), findsOneWidget);
    },
  );

  testWidgets('terminal cursor render offset advances as text is written', (
    WidgetTester tester,
  ) async {
    final terminal = Terminal(maxLines: 100);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 200,
            child: TerminalView(
              terminal,
              theme: TerminalThemes.defaultTheme,
              textStyle: const TerminalStyle(fontSize: 14),
              focusNode: focusNode,
              alwaysShowCursor: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final render = tester.allRenderObjects.whereType<RenderTerminal>().single;
    final before = render.cursorOffset;

    terminal.write('A');
    await tester.pump();
    final afterLatin = render.cursorOffset;
    terminal.write('ب');
    await tester.pump();
    final afterArabic = render.cursorOffset;

    expect(afterLatin.dx, greaterThan(before.dx));
    expect(afterArabic.dx, greaterThan(afterLatin.dx));
  });

  test(
    'copies mixed Arabic, English, digits and punctuation in logical order',
    () {
      const source = 'ملف Arch رقم 123: محفوظ!';
      final terminal = Terminal(maxLines: 100);
      terminal.resize(80, 24);
      terminal.write(source);

      // الرسم البصري المتصل يعيد ترتيب glyphs فقط ولا يبدل buffer الأصلي.
      final visual = String.fromCharCodes(
        ArabicGridText.visualCells(source.runes.toList(growable: false)),
      );
      final copied = terminal.buffer.getText(
        BufferRangeLine(const CellOffset(0, 0), const CellOffset(80, 0)),
      );

      expect(visual, isNot(source));
      expect(copied, contains(source));
    },
  );

  test(
    'renders mixed Arabic, digits and punctuation as visual terminal cells',
    () {
      final visual = String.fromCharCodes(
        ArabicGridText.visualCells(
          'ملف 123 محفوظ.'.runes.toList(growable: false),
        ),
      );

      expect(visual, contains('123'));
      expect(visual, endsWith('ﻒﻠﻣ'));
      expect(visual, isNot('ملف 123 محفوظ.'));
    },
  );

  testWidgets('renders the terminal screen and opens the command panel', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ArchTerminalApp());
    await tester.pump();

    expect(find.text('ARCH TERMINAL'), findsOneWidget);
    expect(find.text('اضغط داخل الطرفية لبدء الإدخال'), findsNothing);
    expect(find.textContaining('UTF-8 • AR / EN / 123'), findsNothing);
    expect(
      find.text('محلي بالكامل — اكتب أمراً أو افتح لوحة التحكم'),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('الإعدادات والأوامر'), findsOneWidget);
    expect(find.text('تشغيل shell'), findsNothing);
    expect(find.text('صلاحيات واستمرارية'), findsOneWidget);
    expect(find.text('الواجهة والطرفية'), findsOneWidget);
    expect(find.text('لغة الواجهة'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(2));
    expect(find.text('أصوات التفاعل'), findsOneWidget);
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.first.min, TerminalPreferences.minFontSize);
    expect(sliders.first.max, TerminalPreferences.maxFontSize);
    expect(find.textContaining('اضغط مطولاً على النص'), findsOneWidget);
  });

  testWidgets(
    'shows local device file search results and reveals a selected path',
    (WidgetTester tester) async {
      String? revealedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceFileSearchPreviewCard(
              preview: const DeviceFileSearchPreview(
                paths: <String>['/sdcard/Download/test.png'],
                truncated: false,
              ),
              arabicUi: true,
              loading: false,
              onClose: () {},
              onOpen: (path) => revealedPath = path,
            ),
          ),
        ),
      );

      expect(find.text('نتائج بحث ملفات الجهاز (1)'), findsOneWidget);
      expect(find.text('/sdcard/Download/test.png'), findsOneWidget);
      expect(find.textContaining('لم تُرسل إلى مزود AI'), findsOneWidget);

      await tester.tap(find.text('/sdcard/Download/test.png'));
      expect(revealedPath, '/sdcard/Download/test.png');
    },
  );

  testWidgets('shows selected text file content only in a local preview', (
    WidgetTester tester,
  ) async {
    String? copiedText;
    final preview = DeviceFileContentPreview.fromMap(<String, Object?>{
      'kind': 'text',
      'path': '/sdcard/Download/note.txt',
      'sizeBytes': 11,
      'text': 'local note',
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceFileContentPreviewCard(
            preview: preview,
            arabicUi: true,
            onClose: () {},
            onCopyText: (text) => copiedText = text,
          ),
        ),
      ),
    );

    expect(find.text('معاينة محلية للملف'), findsOneWidget);
    expect(find.text('/sdcard/Download/note.txt'), findsOneWidget);
    expect(find.text('local note'), findsOneWidget);
    expect(
      find.textContaining('لا يرسل التطبيق المحتوى إلى مزود AI'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('نسخ النص'));
    expect(copiedText, 'local note');
  });

  testWidgets('renders live setup download progress details', (
    WidgetTester tester,
  ) async {
    const progress = SetupProgressViewModel(
      running: true,
      phase: 'downloading',
      message: 'جارٍ تنزيل Arch Linux المطابق لجهازك…',
      percent: 42,
      downloaded: 42 * 1024 * 1024,
      total: 100 * 1024 * 1024,
      speed: 2 * 1024 * 1024,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SetupProgressBanner(progress: progress, arabicUi: true),
        ),
      ),
    );

    expect(find.text('42% — التنزيل'), findsOneWidget);
    expect(find.textContaining('42.0 MB / 100.0 MB'), findsOneWidget);
    expect(find.textContaining('2.0 MB/ث'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('renders extraction file totals and estimated remaining time', (
    WidgetTester tester,
  ) async {
    const progress = SetupProgressViewModel(
      running: true,
      phase: 'extracting',
      message: 'جارٍ استخراج ملفات Arch Linux…',
      percent: 42,
      downloaded: 0,
      total: -1,
      speed: 0,
      extractedFiles: 2208,
      totalFiles: 5250,
      filesPerSecond: 12,
      secondsRemaining: 253,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SetupProgressBanner(progress: progress, arabicUi: true),
        ),
      ),
    );

    expect(find.text('الملفات: 2208 من 5250'), findsOneWidget);
    expect(find.text('السرعة: 12 ملف/ث'), findsOneWidget);
    expect(find.text('المتبقي: 4 دقيقة'), findsOneWidget);
  });

  testWidgets(
    'shows a saved-archive resume explanation and hides an implausible early extraction rate',
    (WidgetTester tester) async {
      const progress = SetupProgressViewModel(
        running: true,
        phase: 'extracting',
        message: 'جارٍ استخراج ملفات Arch Linux من الأرشيف المحفوظ.',
        percent: 77,
        downloaded: 0,
        total: -1,
        speed: 0,
        extractedFiles: 26613,
        totalFiles: 34343,
        filesPerSecond: 1074447898,
        secondsRemaining: 1,
        archiveSource: 'public',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: SetupProgressBanner(progress: progress, arabicUi: true),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('تُحفظ الملفات المكتملة للاستئناف'),
        findsOneWidget,
      );
      expect(find.text('جارٍ معايرة سرعة الاستخراج…'), findsOneWidget);
      expect(find.textContaining('1074447898 ملف/ث'), findsNothing);
    },
  );

  testWidgets(
    'renders public archive source and root cause detail when setup fails',
    (WidgetTester tester) async {
      const progress = SetupProgressViewModel(
        running: false,
        phase: 'error',
        message: 'فشل إعداد Arch Linux في مرحلة extracting.',
        percent: null,
        downloaded: 0,
        total: -1,
        speed: 0,
        archiveSource: 'public',
        failureDetail: 'IOException: مساحة داخلية غير كافية',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SetupProgressBanner(progress: progress, arabicUi: true),
          ),
        ),
      );

      expect(find.text('المصدر: ملف محفوظ في التخزين العام'), findsOneWidget);
      expect(
        find.textContaining('IOException: مساحة داخلية غير كافية'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'renders network as the active source after a saved archive is rejected',
    (WidgetTester tester) async {
      const progress = SetupProgressViewModel(
        running: true,
        phase: 'downloading',
        message: 'جارٍ تنزيل Arch Linux المطابق لجهازك…',
        percent: 10,
        downloaded: 10,
        total: 100,
        speed: 1,
        archiveSource: 'network',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SetupProgressBanner(progress: progress, arabicUi: true),
          ),
        ),
      );

      expect(find.text('المصدر: تنزيل جديد من مستودع Arch'), findsOneWidget);
    },
  );

  testWidgets('renders English setup labels when English is selected', (
    WidgetTester tester,
  ) async {
    const progress = SetupProgressViewModel(
      running: true,
      phase: 'downloading',
      message: 'Downloading Arch Linux…',
      percent: 42,
      downloaded: 0,
      total: -1,
      speed: 0,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SetupProgressBanner(progress: progress, arabicUi: false),
        ),
      ),
    );

    expect(find.text('42% — Downloading'), findsOneWidget);
  });

  testWidgets('shows persistent storage path and access command', (
    WidgetTester tester,
  ) async {
    final details = <String, Object?>{
      'rootfsStoragePersistent': true,
      'rootfsStorageReady': false,
      'rootfsStoragePath': '/storage/emulated/0/ArchTerminal/rootfs',
      'rootfsStorageCommand': "cd '/storage/emulated/0/ArchTerminal/rootfs'",
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RootfsStorageSheet(
            initial: details,
            arabicUi: true,
            onSelect: (mode) async => <String, Object?>{
              ...details,
              'rootfsStorageMode': mode,
            },
            onRequestPermission: () async {},
            onOpenLocation: () async => details,
          ),
        ),
      ),
    );

    expect(find.text('تخزين عام مستمر'), findsOneWidget);
    expect(find.text('تفعيل إذن التخزين'), findsOneWidget);
    expect(
      find.text("cd '/storage/emulated/0/ArchTerminal/rootfs'"),
      findsOneWidget,
    );
    expect(find.text('نسخ أمر الوصول'), findsOneWidget);
  });
}
