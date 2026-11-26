import 'package:arch_terminal/terminal/environment_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final runtimeStatus = <String, Object?>{
    'abi': 'arm64-v8a',
    'rootfsPath': '/data/user/0/example/files/arch',
    'storagePath': '/storage/emulated/0',
    'prootAvailable': true,
    'pacmanSandboxDisabled': true,
  };

  test('captures a split local Arch probe and hides only sentinel output', () {
    final detector = EnvironmentDetector();
    final command = detector.beginProbe();
    final token = RegExp(r'__arch_terminal_env_probe ([0-9a-f]+)')
        .firstMatch(command)!
        .group(1)!;
    final begin = '__ARCH_TERMINAL_ENV_BEGIN_${token}__';
    final end = '__ARCH_TERMINAL_ENV_END_${token}__';

    expect(
      detector
          .consume('visible ${begin.substring(0, 3)}', runtimeStatus)
          .terminalText,
      'visible ',
    );
    final partial = detector.consume(
      '${begin.substring(3)}\nuser=root\nuid=0\narchitecture=',
      runtimeStatus,
    );
    expect(partial.terminalText, isEmpty);
    expect(partial.snapshot, isNull);

    final result = detector.consume(
      'aarch64\nos_name=Arch Linux ARM\npacman=yes\npacman_packages=123\nrepo_configured=yes\nrepo_mirror=http://mirror.archlinuxarm.org/\$arch/\$repo\nrepo_names=core,extra,alarm,aur\nrepo_database_count=4\npwd=/root\nroot_free_kib=2048\nstorage_bound=yes\n$end\n[root@localhost ~]# ',
      runtimeStatus,
    );

    expect(result.terminalText, '[root@localhost ~]# ');
    expect(result.snapshot, isNotNull);
    expect(result.snapshot!.isRoot, isTrue);
    expect(result.snapshot!.architecture, 'aarch64');
    expect(result.snapshot!.pacmanPackageCount, 123);
    expect(result.snapshot!.repositoryConfigured, isTrue);
    expect(result.snapshot!.repositoryNames, 'core,extra,alarm,aur');
    expect(result.snapshot!.repositoryDatabaseCount, 4);
    expect(
      result.snapshot!.repositoryMirror,
      contains('mirror.archlinuxarm.org'),
    );
    expect(result.snapshot!.storageBound, isTrue);
    expect(result.snapshot!.rootfsPath, '/data/user/0/example/files/arch');
    expect(detector.isProbeActive, isFalse);
  });

  test(
    'probe invocation uses the internal read-only profile function and no sudo',
    () {
      final command = EnvironmentDetector().beginProbe();

      expect(command, startsWith('__arch_terminal_env_probe '));
      expect(command, isNot(contains('sudo')));
      expect(command, endsWith('\n'));
    },
  );
}
