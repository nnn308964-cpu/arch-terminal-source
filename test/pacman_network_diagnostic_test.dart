import 'package:arch_terminal/terminal/pacman_network_diagnostic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'explains a package 404 as a stale database rather than a DNS failure',
    () {
      const output = '''
error: failed retrieving file 'python-3.14.6-1-armv7h.pkg.tar.xz' from mirror.archlinuxarm.org : The requested URL returned error: 404
warning: failed to retrieve some files
error: failed to commit transaction (failed to retrieve some files)
''';

      final diagnostic = pacmanNetworkDiagnostic(
        output: output,
        arabicUi: false,
        dnsConfigured: true,
        mirrorUrl: 'http://mirror.archlinuxarm.org/\$arch/\$repo',
      );

      expect(diagnostic, contains('outdated local database'));
      expect(diagnostic, contains('pacman -Syu'));
      expect(diagnostic, contains('Do not automatically use -Syy'));
    },
  );

  test('keeps DNS diagnostics distinct from a stale package database', () {
    final diagnostic = pacmanNetworkDiagnostic(
      output: 'error: failed retrieving file core.db from mirror: Could not resolve host: mirror.archlinuxarm.org',
      arabicUi: true,
      dnsConfigured: false,
      mirrorUrl: 'http://mirror.archlinuxarm.org/\$arch/\$repo',
    );

    expect(diagnostic, contains('DNS=تحقق منه'));
    expect(diagnostic, isNot(contains('قاعدة محلية متقادمة')));
  });
}
