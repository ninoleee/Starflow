import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:starflow/core/logging/app_logger.dart';

abstract interface class CloudCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureCloudCredentialStore implements CloudCredentialStore {
  static const _storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
      mOptions: MacOsOptions(useDataProtectionKeyChain: false),
      iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device));
  static const _legacyMacStorage = FlutterSecureStorage(
      mOptions: MacOsOptions(useDataProtectionKeyChain: true));
  static const _key = 'starflow.cloud-credentials.v2';
  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    if (value != null || !Platform.isMacOS) return value;

    String? legacyValue;
    try {
      legacyValue = await _legacyMacStorage.read(key: _key);
    } on PlatformException catch (error) {
      final isMissingLegacyEntitlement = error.details == -34018 ||
          error.message?.contains('Code: -34018') == true;
      if (!isMissingLegacyEntitlement) rethrow;
      appLogWarning(
        'settings.credentials',
        'Legacy macOS credential is inaccessible; keeping it untouched',
        fields: const <String, Object?>{'status': -34018},
      );
      return null;
    }
    if (legacyValue == null) return null;
    await _storage.write(key: _key, value: legacyValue);
    if (await _storage.read(key: _key) != legacyValue) {
      throw StateError('Legacy credential migration verification failed');
    }
    return legacyValue;
  }

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
