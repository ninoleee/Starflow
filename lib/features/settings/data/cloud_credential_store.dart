import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CloudCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureCloudCredentialStore implements CloudCredentialStore {
  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device));
  static const _key = 'starflow.cloud-credentials.v2';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) async {
    await _storage.write(key: _key, value: value);
    if (await read() != value) {
      throw StateError('Credential storage verification failed');
    }
  }
}

class MemoryCloudCredentialStore implements CloudCredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}
