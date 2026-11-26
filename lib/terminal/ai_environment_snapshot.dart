class AiEnvironmentSnapshot {
  const AiEnvironmentSnapshot({
    required this.scannedAt,
    required this.user,
    required this.uid,
    required this.architecture,
    required this.osName,
    required this.pacmanAvailable,
    required this.pacmanPackageCount,
    required this.workingDirectory,
    required this.rootFreeKiB,
    required this.storageBound,
    required this.rootfsPath,
    required this.storagePath,
    required this.hostAbi,
    required this.prootAvailable,
    required this.pacmanSandboxDisabled,
    this.repositoryConfigured = false,
    this.repositoryMirror = '',
    this.repositoryNames = '',
    this.repositoryDatabaseCount,
  });

  final DateTime scannedAt;
  final String user;
  final String uid;
  final String architecture;
  final String osName;
  final bool pacmanAvailable;
  final int? pacmanPackageCount;
  final String workingDirectory;
  final int? rootFreeKiB;
  final bool storageBound;
  final String rootfsPath;
  final String storagePath;
  final String hostAbi;
  final bool prootAvailable;
  final bool pacmanSandboxDisabled;
  final bool repositoryConfigured;
  final String repositoryMirror;
  final String repositoryNames;
  final int? repositoryDatabaseCount;

  bool get isRoot => uid == '0';

  String get rootFreeText => rootFreeKiB == null
      ? 'unknown'
      : '${(rootFreeKiB! / 1024).toStringAsFixed(1)} MiB';

  String get repositorySummary => !repositoryConfigured
      ? 'not configured'
      : '${repositoryNames.isEmpty ? 'configured' : repositoryNames}${repositoryDatabaseCount == null ? '' : ' ($repositoryDatabaseCount local databases)'}';

  String get conciseSummary {
    final identity = user.isEmpty
        ? 'unknown user'
        : '$user (uid ${uid.isEmpty ? '?' : uid})';
    final packages = pacmanPackageCount == null
        ? 'unknown'
        : '$pacmanPackageCount';
    return '$identity · ${osName.isEmpty ? 'unknown OS' : osName} · ${architecture.isEmpty ? 'unknown arch' : architecture} · pacman ${pacmanAvailable ? 'available ($packages packages)' : 'unavailable'}';
  }

  String get providerContext =>
      '''Local Arch environment snapshot (captured ${scannedAt.toUtc().toIso8601String()}):
- Guest identity: ${user.isEmpty ? 'unknown' : user}; uid: ${uid.isEmpty ? 'unknown' : uid}; root: $isRoot.
- OS: ${osName.isEmpty ? 'unknown' : osName}; guest architecture: ${architecture.isEmpty ? 'unknown' : architecture}; host ABI: ${hostAbi.isEmpty ? 'unknown' : hostAbi}.
- pacman: ${pacmanAvailable ? 'available' : 'not found'}; installed package count: ${pacmanPackageCount?.toString() ?? 'unknown'}; pacman sandbox workaround: $pacmanSandboxDisabled.
- Arch repositories: $repositorySummary; mirror: ${repositoryMirror.isEmpty ? 'unknown' : repositoryMirror}. This probe only reads local pacman configuration and local sync databases; it does not synchronize repositories or modify packages.
- Working directory: ${workingDirectory.isEmpty ? 'unknown' : workingDirectory}; root free space: $rootFreeText.
- Shared storage bind is ${storageBound ? 'available at /sdcard' : 'not detected'}; RootFS path: ${rootfsPath.isEmpty ? 'unknown' : rootfsPath}; Android storage path: ${storagePath.isEmpty ? 'unknown' : storagePath}; PRoot ready: $prootAvailable.
Use this snapshot as current local evidence. Do not assume sudo is required when uid is 0; prefer direct commands and keep the existing approval workflow for execution.''';

  Map<String, Object?> toJson() => <String, Object?>{
    'scannedAt': scannedAt.toUtc().toIso8601String(),
    'user': user,
    'uid': uid,
    'architecture': architecture,
    'osName': osName,
    'pacmanAvailable': pacmanAvailable,
    'pacmanPackageCount': pacmanPackageCount,
    'workingDirectory': workingDirectory,
    'rootFreeKiB': rootFreeKiB,
    'storageBound': storageBound,
    'rootfsPath': rootfsPath,
    'storagePath': storagePath,
    'hostAbi': hostAbi,
    'prootAvailable': prootAvailable,
    'pacmanSandboxDisabled': pacmanSandboxDisabled,
    'repositoryConfigured': repositoryConfigured,
    'repositoryMirror': repositoryMirror,
    'repositoryNames': repositoryNames,
    'repositoryDatabaseCount': repositoryDatabaseCount,
  };

  static AiEnvironmentSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final scannedAt = DateTime.tryParse(value['scannedAt']?.toString() ?? '')
        ?.toLocal();
    if (scannedAt == null) return null;
    return AiEnvironmentSnapshot(
      scannedAt: scannedAt,
      user: _text(value['user']),
      uid: _text(value['uid']),
      architecture: _text(value['architecture']),
      osName: _text(value['osName']),
      pacmanAvailable: value['pacmanAvailable'] == true,
      pacmanPackageCount: _number(value['pacmanPackageCount']),
      workingDirectory: _text(value['workingDirectory']),
      rootFreeKiB: _number(value['rootFreeKiB']),
      storageBound: value['storageBound'] == true,
      rootfsPath: _text(value['rootfsPath']),
      storagePath: _text(value['storagePath']),
      hostAbi: _text(value['hostAbi']),
      prootAvailable: value['prootAvailable'] == true,
      pacmanSandboxDisabled: value['pacmanSandboxDisabled'] == true,
      repositoryConfigured: value['repositoryConfigured'] == true,
      repositoryMirror: _text(value['repositoryMirror']),
      repositoryNames: _text(value['repositoryNames']),
      repositoryDatabaseCount: _number(value['repositoryDatabaseCount']),
    );
  }

  static AiEnvironmentSnapshot fromProbe(
    Map<String, String> values,
    Map<String, Object?> runtimeStatus,
  ) {
    return AiEnvironmentSnapshot(
      scannedAt: DateTime.now(),
      user: _text(values['user']),
      uid: _text(values['uid']),
      architecture: _text(values['architecture']),
      osName: _text(values['os_name']),
      pacmanAvailable: values['pacman'] == 'yes',
      pacmanPackageCount: _number(values['pacman_packages']),
      workingDirectory: _text(values['pwd']),
      rootFreeKiB: _number(values['root_free_kib']),
      storageBound: values['storage_bound'] == 'yes',
      rootfsPath: _text(runtimeStatus['rootfsPath']),
      storagePath: _text(runtimeStatus['storagePath']),
      hostAbi: _text(runtimeStatus['abi']),
      prootAvailable: runtimeStatus['prootAvailable'] == true,
      pacmanSandboxDisabled: runtimeStatus['pacmanSandboxDisabled'] == true,
      repositoryConfigured: values['repo_configured'] == 'yes',
      repositoryMirror: _text(values['repo_mirror']),
      repositoryNames: _text(values['repo_names']),
      repositoryDatabaseCount: _number(values['repo_database_count']),
    );
  }

  static String _text(Object? value) {
    final cleaned = (value?.toString() ?? '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    return cleaned.length <= 240 ? cleaned : cleaned.substring(0, 240);
  }

  static int? _number(Object? value) =>
      int.tryParse(value?.toString().trim() ?? '');
}
