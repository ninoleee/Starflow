import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'app_settings.dart';

enum CloudAccountDrive { quark, cloud115, aliyun }

String credentialFingerprint(String value) => value.trim().isEmpty
    ? ''
    : sha256.convert(utf8.encode(value.trim())).toString();

class CloudAccount {
  const CloudAccount(
      {this.id = '',
      this.fingerprint = '',
      this.verified = false,
      this.directoryPending = false,
      this.invalid = false});
  final String id;
  final String fingerprint;
  final bool verified;
  final bool directoryPending;
  final bool invalid;

  String status(String credential) => credential.trim().isEmpty
      ? '未配置'
      : verified && fingerprint == credentialFingerprint(credential)
          ? '可用'
          : invalid && fingerprint == credentialFingerprint(credential)
              ? '已失效'
              : '待验证';

  CloudAccount withDirectoryConfirmed() => CloudAccount(
      id: id, fingerprint: fingerprint, verified: verified, invalid: invalid);
  Map<String, Object> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'verified': verified,
        'directoryPending': directoryPending,
        'invalid': invalid
      };
  factory CloudAccount.fromJson(Map<String, dynamic> json) => CloudAccount(
      id: json['id'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      verified: json['verified'] == true,
      invalid: json['invalid'] == true,
      directoryPending: json['directoryPending'] == true);
}

extension CloudAccountSettings on NetworkStorageConfig {
  String credential(CloudAccountDrive drive) => switch (drive) {
        CloudAccountDrive.aliyun => activeAliyunRefreshToken,
        CloudAccountDrive.cloud115 => cloud115Cookie,
        CloudAccountDrive.quark => quarkCookie,
      };
  CloudAccount account(CloudAccountDrive drive) =>
      CloudAccount.fromJson(localCloudAccounts[drive.name] ?? {});
  NetworkStorageConfig withAccount(
          CloudAccountDrive drive, CloudAccount value) =>
      copyWith(localCloudAccounts: {
        ...localCloudAccounts,
        drive.name: value.toJson()
      });
  NetworkStorageConfig withCredential(CloudAccountDrive drive, String value) =>
      switch (drive) {
        CloudAccountDrive.aliyun => aliyunAuthMode == AliyunAuthMode.open
            ? copyWith(aliyunOpenRefreshToken: value)
            : copyWith(aliyunRefreshToken: value),
        CloudAccountDrive.cloud115 => copyWith(cloud115Cookie: value),
        CloudAccountDrive.quark => copyWith(quarkCookie: value),
      };
  NetworkStorageConfig invalidateDirectory(CloudAccountDrive drive) =>
      switch (drive) {
        CloudAccountDrive.aliyun => copyWith(
            aliyunSaveFolderId: '',
            aliyunSaveFolderPath: '待重新选择',
            syncDeleteAliyunEnabled: false,
            syncDeleteAliyunWebDavDirectories: []),
        CloudAccountDrive.cloud115 => copyWith(
            cloud115SaveFolderId: '',
            cloud115SaveFolderPath: '待重新选择',
            syncDelete115Enabled: false,
            syncDelete115WebDavDirectories: []),
        CloudAccountDrive.quark => copyWith(
            quarkSaveFolderId: '',
            quarkSaveFolderPath: '待重新选择',
            syncDeleteQuarkEnabled: false,
            syncDeleteQuarkWebDavDirectories: []),
      };
}
