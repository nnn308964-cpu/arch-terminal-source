String? pacmanNetworkDiagnostic({
  required String output,
  required bool arabicUi,
  required bool dnsConfigured,
  required String mirrorUrl,
}) {
  final normalized = output.toLowerCase();
  final looksLikeDnsFailure =
      normalized.contains('could not resolve host') ||
      normalized.contains('temporary failure in name resolution') ||
      normalized.contains('name or service not known');
  final looksLikeMirrorFailure =
      normalized.contains('failed to synchronize all databases') &&
      normalized.contains('invalid url for server');
  final looksLikeStalePackageDatabase =
      normalized.contains('failed retrieving file') &&
      normalized.contains('requested url returned error: 404') &&
      normalized.contains('failed to commit transaction');
  if (looksLikeStalePackageDatabase) {
    return arabicUi
        ? 'أعاد مستودع pacman خطأ 404 لحزمة تشير إليها قاعدة محلية متقادمة. لا تُعِد تثبيت الحزمة وحدها؛ وافق على ترقية كاملة بـ pacman -Syu ثم أعد طلب الحزمة. لا تستخدم -Syy تلقائياً.'
        : 'pacman received a 404 for a package named by an outdated local database. Do not retry the package install alone; approve a full pacman -Syu upgrade, then request the package again. Do not automatically use -Syy.';
  }
  if (!looksLikeDnsFailure && !looksLikeMirrorFailure) return null;

  final dns = dnsConfigured
      ? (arabicUi ? 'جاهز' : 'ready')
      : (arabicUi ? 'تحقق منه' : 'check it');
  return arabicUi
      ? 'فشل اتصال pacman: DNS=$dns، resolv.conf=/etc/resolv.conf، المرآة=$mirrorUrl'
      : 'pacman network failure: DNS=$dns, resolv.conf=/etc/resolv.conf, mirror=$mirrorUrl';
}
