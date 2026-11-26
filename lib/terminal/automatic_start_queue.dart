/// يمنع تداخل محاولات التشغيل التلقائي القصيرة فقط.
///
/// لا يحتفظ هذا الحجز بحالة الجلسة طويلة العمر؛ إذ تتحقق الواجهة من
/// [TerminalSession.isRunning] قبل بدء أي جلسة جديدة.
class AutomaticStartQueue {
  bool _reserved = false;

  bool get isReserved => _reserved;

  bool tryReserve() {
    if (_reserved) return false;
    _reserved = true;
    return true;
  }

  void release() {
    _reserved = false;
  }
}

/// يحرر الحجز فقط عندما تفشل محاولة البدء أو لا تبقى الجلسة عاملة بعدها.
bool shouldReleaseAutomaticStartReservation({
  required bool startSucceeded,
  required bool sessionRunning,
}) {
  return !startSucceeded || !sessionRunning;
}

/// يمنع إعادة الإقلاع التلقائية بعد «إنهاء الجلسة» الصريح من الإشعار.
/// يعاد فتح هذا الحاجز فقط عندما يطلب المستخدم إعداد Arch من الواجهة.
bool canQueueAutomaticStart({required bool manualEndRequested}) =>
    !manualEndRequested;

/// The native notification end flow records this intent only for the next app launch.
bool shouldResumeAfterNotificationEnd({required bool restartPending}) =>
    restartPending;

/// Allows best-effort reconnection only when the user enabled protection, the
/// native service recorded a possible process loss, and no live PTY is present.
bool shouldReconnectAfterProcessLoss({
  required bool backgroundProtectionEnabled,
  required bool reconnectPending,
  required bool serviceActive,
  required bool manualEndRequested,
  required bool sessionRunning,
}) =>
    backgroundProtectionEnabled &&
    reconnectPending &&
    !serviceActive &&
    !manualEndRequested &&
    !sessionRunning;
