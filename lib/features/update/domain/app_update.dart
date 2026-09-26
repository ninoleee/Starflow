// IO-free models are also used by the release manifest generator.
class UpdateArtifact {
  const UpdateArtifact(
      {required this.platform,
      required this.variant,
      required this.url,
      required this.fileName,
      required this.size,
      required this.sha256,
      required this.minSdk,
      required this.certificateSha256});
  final String platform;
  final String variant;
  final Uri url;
  final String fileName;
  final int size;
  final String sha256;
  final int minSdk;
  final String certificateSha256;
}

class AppUpdate {
  const AppUpdate(
      {required this.appId,
      required this.channel,
      required this.version,
      required this.versionCode,
      required this.publishedAt,
      required this.releaseNotes,
      required this.artifacts});
  final String appId;
  final String channel;
  final String version;
  final int versionCode;
  final DateTime publishedAt;
  final List<String> releaseNotes;
  final List<UpdateArtifact> artifacts;
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

enum UpdatePhase {
  idle,
  checking,
  unconfigured,
  upToDate,
  available,
  downloading,
  verifying,
  readyToInstall,
  installing,
  failed,
}

class UpdateState {
  const UpdateState(
      {this.phase = UpdatePhase.idle,
      this.update,
      this.artifact,
      this.receivedBytes = 0,
      this.packagePath,
      this.failure,
      this.currentVersion = '',
      this.currentVersionCode = 0});
  final UpdatePhase phase;
  final AppUpdate? update;
  final UpdateArtifact? artifact;
  final int receivedBytes;
  final String? packagePath;
  final UpdateFailure? failure;
  final String currentVersion;
  final int currentVersionCode;
}
