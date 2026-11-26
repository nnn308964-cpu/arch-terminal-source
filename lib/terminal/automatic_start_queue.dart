/// Prevents overlapping short automatic-start attempts.
///
/// This reservation does not hold long-lived session state; the UI checks
/// [TerminalSession.isRunning] before starting a new session.
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

/// Releases the reservation only when startup fails or the session is no longer running.
bool shouldReleaseAutomaticStartReservation({
  required bool startSucceeded,
  required bool sessionRunning,
}) {
  return !startSucceeded || !sessionRunning;
}

/// Prevents an automatic restart after the user explicitly ends a session from
/// the notification. The gate reopens only when the user requests Arch setup.
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
