import 'dart:async';

import 'package:starflow/features/settings/domain/app_settings.dart';

typedef SettingsLanTransferLoadSettings = FutureOr<AppSettings> Function();
typedef SettingsLanTransferImportSettings = Future<void> Function(
  AppSettings settings,
);

class SettingsLanTransferEvent {
  const SettingsLanTransferEvent({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

class SettingsLanTransferSession {
  const SettingsLanTransferSession({
    this.accessCode = '',
    this.port = 0,
    this.urls = const [],
  });

  final String accessCode;
  final int port;
  final List<String> urls;

  Stream<SettingsLanTransferEvent> get events =>
      const Stream<SettingsLanTransferEvent>.empty();

  Future<void> close() async {}
}

class SettingsLanTransferService {
  const SettingsLanTransferService._();

  static Future<SettingsLanTransferSession> start({
    required SettingsLanTransferLoadSettings loadSettings,
    required SettingsLanTransferImportSettings importSettings,
  }) {
    throw UnsupportedError('当前平台不支持局域网配置传输。');
  }
}
