String? setupFailureGuidance({
  required String phase,
  required String detail,
  required bool arabicUi,
}) {
  final normalized = '$phase $detail'.toLowerCase();
  if (normalized.contains('not enough internal space') ||
      normalized.contains('مساحة داخلية كافية')) {
    return arabicUi
        ? 'الإجراء المقترح: حرّر مساحة داخلية ثم اضغط «تنزيل وإعداد Arch» للاستئناف من الملف أو checkpoint المحفوظ.'
        : 'Suggested action: free internal storage, then select Download and set up Arch to resume from the saved file or checkpoint.';
  }
  if (normalized.contains('storage access') ||
      normalized.contains('إذن مساحة التخزين')) {
    return arabicUi
        ? 'الإجراء المقترح: افتح إعداد حفظ Arch وفعّل إذن التخزين العام، ثم أعد المحاولة.'
        : 'Suggested action: open Arch storage settings, grant shared-storage access, then retry.';
  }
  if (normalized.contains('sha-256') || normalized.contains('integrity')) {
    return arabicUi
        ? 'الإجراء المقترح: أعد المحاولة؛ لن يستخدم التطبيق الأرشيف غير السليم.'
        : 'Suggested action: retry. The app will not use an archive that fails integrity verification.';
  }
  if (normalized.contains('http') ||
      normalized.contains('network') ||
      normalized.contains('unknownhost') ||
      normalized.contains('dns')) {
    return arabicUi
        ? 'الإجراء المقترح: تحقق من الشبكة، ثم اضغط متابعة؛ سيستأنف التنزيل من الجزء المحفوظ.'
        : 'Suggested action: check connectivity, then continue; downloading resumes from the saved part.';
  }
  if (phase == 'extracting' ||
      normalized.contains('archive') ||
      normalized.contains('tar')) {
    return arabicUi
        ? 'الإجراء المقترح: أعد فتح التطبيق أو أعد المحاولة؛ ستُستخدم نقطة الاستخراج المحفوظة ولا يُعتمد تثبيت جزئي.'
        : 'Suggested action: reopen the app or retry; the saved extraction checkpoint is used and a partial install is never accepted.';
  }
  return arabicUi
      ? 'الإجراء المقترح: انسخ التفصيل، ثم أعد المحاولة من لوحة إعداد Arch.'
      : 'Suggested action: copy the detail, then retry from the Arch setup panel.';
}
