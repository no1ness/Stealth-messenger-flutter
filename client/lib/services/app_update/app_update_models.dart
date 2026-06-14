enum AppUpdateStatusKind {
  upToDate,
  optionalUpdateAvailable,
  mandatoryUpdateAvailable,
  unsupportedPlatform,
  notConfigured,
  checkFailed,
}

enum AppUpdateInstallPhase {
  idle,
  downloading,
  verifying,
  readyToInstall,
  handingOffToInstaller,
  completed,
  failed,
}

class AppUpdateVersion implements Comparable<AppUpdateVersion> {
  AppUpdateVersion({required this.version, required this.buildNumber})
      : segments = _parseSegments(version);

  final String version;
  final int buildNumber;
  final List<int> segments;

  String get display => '$version+$buildNumber';

  static AppUpdateVersion fromValues({
    required Object? version,
    required Object? buildNumber,
    String fieldPrefix = 'version',
  }) {
    return AppUpdateVersion(
      version: _readString(version, '$fieldPrefix.version'),
      buildNumber: _readInt(buildNumber, '$fieldPrefix.buildNumber'),
    );
  }

  @override
  int compareTo(AppUpdateVersion other) {
    final maxLength = segments.length > other.segments.length
        ? segments.length
        : other.segments.length;
    for (var i = 0; i < maxLength; i += 1) {
      final left = i < segments.length ? segments[i] : 0;
      final right = i < other.segments.length ? other.segments[i] : 0;
      if (left != right) return left.compareTo(right);
    }
    return buildNumber.compareTo(other.buildNumber);
  }

  bool operator >(AppUpdateVersion other) => compareTo(other) > 0;
  bool operator >=(AppUpdateVersion other) => compareTo(other) >= 0;
  bool operator <(AppUpdateVersion other) => compareTo(other) < 0;
  bool operator <=(AppUpdateVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppUpdateVersion &&
      other.version == version &&
      other.buildNumber == buildNumber;

  @override
  int get hashCode => Object.hash(version, buildNumber);

  @override
  String toString() => display;
}

class AppUpdateManifest {
  AppUpdateManifest({
    required this.latestVersion,
    required this.apkUrl,
    required this.sha256,
    required this.mandatory,
    required this.releaseNotes,
  });

  final AppUpdateVersion latestVersion;
  final Uri apkUrl;
  final String sha256;
  final bool mandatory;
  final String releaseNotes;

  factory AppUpdateManifest.fromJson(Map<String, Object?> json) {
    return AppUpdateManifest(
      latestVersion: AppUpdateVersion.fromValues(
        version: json['version'],
        buildNumber: json['buildNumber'],
        fieldPrefix: 'manifest',
      ),
      apkUrl: _readHttpsUri(json['apkUrl'], 'manifest.apkUrl'),
      sha256: _readSha256(json['sha256'], 'manifest.sha256'),
      mandatory: _readBool(json['mandatory'], 'manifest.mandatory'),
      releaseNotes: _readString(json['releaseNotes'], 'manifest.releaseNotes'),
    );
  }
}

class AppUpdateStatus {
  const AppUpdateStatus({
    required this.kind,
    required this.currentVersion,
    this.manifest,
    this.detail,
  });

  final AppUpdateStatusKind kind;
  final AppUpdateVersion? currentVersion;
  final AppUpdateManifest? manifest;
  final String? detail;

  bool get isUpdateAvailable =>
      kind == AppUpdateStatusKind.optionalUpdateAvailable ||
      kind == AppUpdateStatusKind.mandatoryUpdateAvailable;

  bool get isMandatory => kind == AppUpdateStatusKind.mandatoryUpdateAvailable;

  static AppUpdateStatus resolve({
    required AppUpdateVersion currentVersion,
    required AppUpdateManifest manifest,
    required bool platformSupported,
  }) {
    if (!platformSupported) {
      return AppUpdateStatus.unsupportedPlatform(
        currentVersion: currentVersion,
        manifest: manifest,
      );
    }
    if (manifest.latestVersion <= currentVersion) {
      return AppUpdateStatus(
        kind: AppUpdateStatusKind.upToDate,
        currentVersion: currentVersion,
        manifest: manifest,
      );
    }
    return AppUpdateStatus(
      kind: manifest.mandatory
          ? AppUpdateStatusKind.mandatoryUpdateAvailable
          : AppUpdateStatusKind.optionalUpdateAvailable,
      currentVersion: currentVersion,
      manifest: manifest,
    );
  }

  static AppUpdateStatus notConfigured({AppUpdateVersion? currentVersion}) {
    return AppUpdateStatus(
      kind: AppUpdateStatusKind.notConfigured,
      currentVersion: currentVersion,
      detail: 'APP_UPDATE_MANIFEST_URL is not configured.',
    );
  }

  static AppUpdateStatus unsupportedPlatform({
    AppUpdateVersion? currentVersion,
    AppUpdateManifest? manifest,
  }) {
    return AppUpdateStatus(
      kind: AppUpdateStatusKind.unsupportedPlatform,
      currentVersion: currentVersion,
      manifest: manifest,
      detail: 'Current platform cannot install APK updates.',
    );
  }

  static AppUpdateStatus checkFailed({
    AppUpdateVersion? currentVersion,
    required String detail,
  }) {
    return AppUpdateStatus(
      kind: AppUpdateStatusKind.checkFailed,
      currentVersion: currentVersion,
      detail: detail,
    );
  }
}

class AppUpdateInstallState {
  const AppUpdateInstallState({
    required this.phase,
    this.receivedBytes,
    this.totalBytes,
    this.detail,
  });

  final AppUpdateInstallPhase phase;
  final int? receivedBytes;
  final int? totalBytes;
  final String? detail;

  double? get progress {
    final received = receivedBytes;
    final total = totalBytes;
    if (received == null || total == null || total <= 0) {
      return null;
    }
    return (received / total).clamp(0, 1).toDouble();
  }
}

List<int> _parseSegments(String version) {
  final normalized = version.trim().split(RegExp(r'[-+]')).first;
  if (normalized.isEmpty) {
    throw const FormatException('version must not be empty');
  }
  return normalized.split('.').map((part) {
    if (part.isEmpty || !RegExp(r'^\d+$').hasMatch(part)) {
      throw FormatException('invalid version segment "$part" in "$version"');
    }
    return int.parse(part);
  }).toList();
}

String _readString(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('$field must be a non-empty string');
}

int _readInt(Object? value, String field) {
  if (value is int && value >= 0) {
    return value;
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
  }
  throw FormatException('$field must be a non-negative integer');
}

bool _readBool(Object? value, String field) {
  if (value is bool) {
    return value;
  }
  throw FormatException('$field must be a boolean');
}

Uri _readHttpsUri(Object? value, String field) {
  final raw = _readString(value, field);
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.scheme == 'https' && uri.host.isNotEmpty) return uri;
  throw FormatException('$field must be an absolute HTTPS URL');
}

String _readSha256(Object? value, String field) {
  final raw = _readString(value, field).toLowerCase();
  if (RegExp(r'^[a-f0-9]{64}$').hasMatch(raw)) return raw;
  throw FormatException('$field must be a 64-character hex SHA-256 digest');
}
