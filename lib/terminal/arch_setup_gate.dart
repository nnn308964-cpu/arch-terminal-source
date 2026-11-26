/// الإجراء الذي تعرضه بوابة إعداد Arch بعد قراءة الصلاحيات وحالة الملفات.
enum ArchSetupAction {
  openPermissionGate,
  useInstalledRootfs,
  reusePublicArchive,
  downloadRootfs,
}

enum ArchPermissionStep { notification, battery, sharedStorage, ready }

/// ترتيب البوابة ثابت حتى يعرف المستخدم بوضوح ما الذي يحتاجه قبل الإعداد.
ArchPermissionStep nextArchPermissionStep({
  required bool notificationsGranted,
  required bool batteryOptimizationIgnored,
  required bool publicStorageGranted,
}) {
  if (!notificationsGranted) return ArchPermissionStep.notification;
  if (!batteryOptimizationIgnored) return ArchPermissionStep.battery;
  if (!publicStorageGranted) return ArchPermissionStep.sharedStorage;
  return ArchPermissionStep.ready;
}

/// لا يبدأ إعداد Arch قبل منح الصلاحيات المطلوبة. بعد ذلك يُفضَّل دائماً
/// التشغيل من RootFS المثبت أو الأرشيف العام الذي سيُتحقَّق منه قبل استخراجه.
ArchSetupAction decideArchSetupAction({
  required bool notificationsGranted,
  required bool batteryOptimizationIgnored,
  required bool publicStorageGranted,
  required bool archInstalled,
  required bool prootAvailable,
  required bool publicArchivePresent,
}) {
  if (!notificationsGranted ||
      !batteryOptimizationIgnored ||
      !publicStorageGranted) {
    return ArchSetupAction.openPermissionGate;
  }
  if (archInstalled && prootAvailable) {
    return ArchSetupAction.useInstalledRootfs;
  }
  if (publicArchivePresent) return ArchSetupAction.reusePublicArchive;
  return ArchSetupAction.downloadRootfs;
}
