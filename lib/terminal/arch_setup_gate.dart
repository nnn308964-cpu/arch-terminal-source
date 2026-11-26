/// Action displayed by the Arch setup gate after reading permissions and file state.
enum ArchSetupAction {
  openPermissionGate,
  useInstalledRootfs,
  reusePublicArchive,
  downloadRootfs,
}

enum ArchPermissionStep { notification, battery, sharedStorage, ready }

/// The gate order is fixed so users can clearly see what setup still requires.
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

/// Arch setup does not start until the required permissions are granted. After
/// that, the installed RootFS or verified public archive is preferred.
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
