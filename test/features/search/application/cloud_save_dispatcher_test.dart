import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/application/cloud115_save_workflow_service.dart';
import 'package:starflow/features/search/application/cloud_save_dispatcher.dart';
import 'package:starflow/features/search/application/quark_save_workflow_service.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/cloud_save_feedback.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

const _config = NetworkStorageConfig(
  cloud115Cookie: '115-cookie',
  quarkCookie: 'quark-cookie',
  cloud115SaveFolderPath: '/115',
  quarkSaveFolderPath: '/quark',
);

SearchResult _share(CloudSaveDrive drive,
        {String query = '', String password = 'abcd'}) =>
    SearchResult(
      id: 'share',
      title: 'Share',
      posterUrl: '',
      providerId: 'p',
      providerName: 'P',
      quality: '',
      sizeLabel: '',
      seeders: 0,
      summary: '',
      resourceUrl:
          'https://${drive == CloudSaveDrive.cloud115 ? '115cdn.com' : 'pan.quark.cn'}/s/share$query',
      password: password,
    );

void main() {
  late _Cloud115 cloud115;
  late _Quark quark;
  late CloudSaveDispatcher dispatcher;
  setUp(() {
    cloud115 = _Cloud115();
    quark = _Quark();
    dispatcher = CloudSaveDispatcher(cloud115: cloud115, quark: quark);
  });

  for (final drive in CloudSaveDrive.values) {
    test('${drive.name} prepares credentials and forwards only its workflow',
        () async {
      final progress = <CloudSaveProgress>[];
      final failures = <String>[];
      final outcome = await dispatcher.save(
        result: _share(drive),
        networkStorage: _config,
        saveFolderName: 'Show',
        onProgress: progress.add,
        onBackgroundRefreshFailure: failures.add,
      );
      expect(outcome.isSuccess, isTrue);
      expect(outcome.drive, drive);
      final url = drive == CloudSaveDrive.cloud115 ? cloud115.url! : quark.url!;
      final parameter = drive == CloudSaveDrive.cloud115 ? 'password' : 'pwd';
      expect(Uri.parse(url).queryParameters[parameter], 'abcd');
      expect(drive == CloudSaveDrive.cloud115 ? cloud115.password : 'abcd',
          'abcd');
      expect(drive == CloudSaveDrive.cloud115 ? cloud115.folder : quark.folder,
          'Show');
      expect(
          identical(
              drive == CloudSaveDrive.cloud115 ? cloud115.config : quark.config,
              _config),
          isTrue);
      expect(
          drive == CloudSaveDrive.cloud115 ? quark.url : cloud115.url, isNull);
      expect(progress.single.drive, drive);
      final background = drive == CloudSaveDrive.cloud115
          ? cloud115.background!
          : quark.background!;
      background('refresh warning');
      expect(failures, ['refresh warning']);
      expect(
          outcome.message,
          drive == CloudSaveDrive.cloud115
              ? '115 workflow summary'
              : '已提交到夸克，保存 0 个，略过 2 个');
    });

    test('${drive.name} keeps URL password precedence', () async {
      final parameter = drive == CloudSaveDrive.cloud115 ? 'password' : 'pwd';
      await dispatcher.save(
          result: _share(drive, query: '?$parameter=url-code'),
          networkStorage: _config,
          saveFolderName: 'Show');
      final url = drive == CloudSaveDrive.cloud115 ? cloud115.url! : quark.url!;
      expect(Uri.parse(url).queryParameters[parameter], 'url-code');
      if (drive == CloudSaveDrive.cloud115) {
        expect(cloud115.password, 'url-code');
      }
    });

    test('${drive.name} never falls back to the other account', () async {
      final config = drive == CloudSaveDrive.cloud115
          ? _config.copyWith(cloud115Cookie: '')
          : _config.copyWith(quarkCookie: '');
      final outcome = await dispatcher.save(
          result: _share(drive),
          networkStorage: config,
          saveFolderName: 'Show');
      expect(outcome.failureKind, CloudSaveFailureKind.credentials);
      expect(outcome.message, contains('${drive.label} Cookie'));
      expect(CloudSaveDispatcher.canSave(_share(drive), config), isFalse);
      expect(cloud115.url, isNull);
      expect(quark.url, isNull);
    });

    test(
        '${drive.name} maps protocol and unexpected failures without losing cause',
        () async {
      final protocolError =
          const QuarkSaveException('batch unconfirmed; inspect drive');
      cloud115.error = quark.error = protocolError;
      var outcome = await dispatcher.save(
          result: _share(drive),
          networkStorage: _config,
          saveFolderName: 'Show');
      expect(outcome.failureKind, CloudSaveFailureKind.save);
      expect(outcome.message, protocolError.message);
      expect(outcome.error, same(protocolError));
      expect(outcome.stackTrace, isNotNull);

      final error = StateError('transport');
      cloud115.error = quark.error = error;
      outcome = await dispatcher.save(
          result: _share(drive),
          networkStorage: _config,
          saveFolderName: 'Show');
      expect(outcome.isSuccess, isFalse);
      expect(outcome.failureKind, CloudSaveFailureKind.unexpected);
      expect(
          outcome.message,
          drive == CloudSaveDrive.cloud115
              ? '115 保存未确认，请检查网盘后再重试'
              : '保存失败：$error');
      expect(outcome.error, same(error));
    });

    test('${drive.name} maps downstream errors as partial success wording',
        () async {
      cloud115.error = quark.error = const SmartStrmWebhookException('offline');
      final outcome = await dispatcher.save(
          result: _share(drive),
          networkStorage: _config,
          saveFolderName: 'Show');
      expect(outcome.failureKind, CloudSaveFailureKind.smartStrm);
      expect(outcome.message, drive.smartStrmFailureMessage('offline'));
    });
  }

  test('unsupported links never dispatch a save', () async {
    final outcome = await dispatcher.save(
        result: _share(CloudSaveDrive.quark)
            .copyWith(resourceUrl: 'https://unknown.test/s/share'),
        networkStorage: _config,
        saveFolderName: 'Show');
    expect(outcome.failureKind, CloudSaveFailureKind.unsupported);
    expect(cloud115.url, isNull);
    expect(quark.url, isNull);
  });
}

class _Cloud115 implements Cloud115SaveWorkflowService {
  String? url;
  String? password;
  String? folder;
  NetworkStorageConfig? config;
  Object? error;
  void Function(String)? background;

  @override
  Future<String> save(
      {required String shareUrl,
      required NetworkStorageConfig config,
      String password = '',
      String saveFolderName = '',
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    url = shareUrl;
    this.password = password;
    folder = saveFolderName;
    this.config = config;
    background = onBackgroundRefreshFailure;
    if (error != null) throw error!;
    onProgress?.call(const CloudSaveProgress.saving(CloudSaveDrive.cloud115));
    return '115 workflow summary';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Quark implements QuarkSaveWorkflowService {
  String? url;
  String? folder;
  NetworkStorageConfig? config;
  Object? error;
  void Function(String)? background;

  @override
  Future<QuarkSaveWorkflowResult> saveToQuark(
      {required String shareUrl,
      required String saveFolderName,
      required NetworkStorageConfig networkStorage,
      CloudSaveProgressCallback? onProgress,
      void Function(String)? onBackgroundRefreshFailure}) async {
    url = shareUrl;
    folder = saveFolderName;
    config = networkStorage;
    background = onBackgroundRefreshFailure;
    if (error != null) throw error!;
    onProgress?.call(const CloudSaveProgress.saving(CloudSaveDrive.quark));
    return const QuarkSaveWorkflowResult(
      saveResult: QuarkSaveResult(
          savedCount: 0,
          skippedCount: 2,
          taskId: '',
          targetFolderPath: '/quark'),
      triggeredSmartStrm: false,
      smartStrmResult: null,
      refreshSourceIds: [],
      refreshDelaySeconds: 0,
      smartStrmDelaySeconds: 0,
    );
  }
}
