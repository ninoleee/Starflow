import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/search/application/quark_save_workflow_service.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  group('QuarkSaveWorkflowService', () {
    test('throws when quark cookie is missing', () async {
      var saveCalled = false;
      final service = QuarkSaveWorkflowService(
        saveShareLink: ({
          required String shareUrl,
          required String cookie,
          String toPdirFid = '0',
          String toPdirPath = '/',
          String saveFolderName = '',
        }) async {
          saveCalled = true;
          return const QuarkSaveResult(
            taskId: '',
            savedCount: 0,
            targetFolderPath: '/',
          );
        },
        triggerSmartStrm: ({
          required String webhookUrl,
          required String taskName,
          String storagePath = '',
          int delay = 0,
        }) async {
          return const SmartStrmTriggerResult(
            message: '',
            addedCount: null,
            rawPayload: {},
          );
        },
        resolveRefreshSourceIds: ({
          required NetworkStorageConfig networkStorage,
          required bool includeConfiguredSources,
        }) {
          return const <String>[];
        },
        refreshSelectedSources: ({
          required List<String> sourceIds,
          required int delaySeconds,
        }) async {},
      );

      await expectLater(
        () => service.saveToQuark(
          shareUrl: 'https://pan.quark.cn/s/test',
          saveFolderName: '三体',
          networkStorage: const NetworkStorageConfig(),
        ),
        throwsA(
          isA<QuarkSaveException>().having(
            (error) => error.message,
            'message',
            '请先在搜索设置里填写夸克 Cookie',
          ),
        ),
      );
      expect(saveCalled, isFalse);
    });

    test('runs shared save chain and returns composed success message',
        () async {
      Map<String, Object?>? saveCall;
      Map<String, Object?>? triggerCall;
      Map<String, Object?>? refreshCall;
      var resolveIncludeConfiguredSources = false;
      final service = QuarkSaveWorkflowService(
        saveShareLink: ({
          required String shareUrl,
          required String cookie,
          String toPdirFid = '0',
          String toPdirPath = '/',
          String saveFolderName = '',
        }) async {
          saveCall = {
            'shareUrl': shareUrl,
            'cookie': cookie,
            'toPdirFid': toPdirFid,
            'toPdirPath': toPdirPath,
            'saveFolderName': saveFolderName,
          };
          return const QuarkSaveResult(
            taskId: 'task-1',
            savedCount: 3,
            skippedCount: 1,
            targetFolderPath: '/影视/三体',
          );
        },
        triggerSmartStrm: ({
          required String webhookUrl,
          required String taskName,
          String storagePath = '',
          int delay = 0,
        }) async {
          triggerCall = {
            'webhookUrl': webhookUrl,
            'taskName': taskName,
            'storagePath': storagePath,
            'delay': delay,
          };
          return const SmartStrmTriggerResult(
            message: 'ok',
            addedCount: 8,
            rawPayload: {'message': 'ok'},
          );
        },
        resolveRefreshSourceIds: ({
          required NetworkStorageConfig networkStorage,
          required bool includeConfiguredSources,
        }) {
          resolveIncludeConfiguredSources = includeConfiguredSources;
          return const ['quark-main', 'nas-main'];
        },
        refreshSelectedSources: ({
          required List<String> sourceIds,
          required int delaySeconds,
        }) async {
          refreshCall = {
            'sourceIds': sourceIds,
            'delaySeconds': delaySeconds,
          };
        },
      );
      const storage = NetworkStorageConfig(
        quarkCookie: 'kps=test',
        quarkSaveFolderId: 'folder-id',
        quarkSaveFolderPath: '/影视',
        smartStrmWebhookUrl: 'https://strm.example.com/hook',
        smartStrmTaskName: 'quark-sync',
        refreshMediaSourceIds: ['nas-main'],
        refreshDelaySeconds: 6,
        smartStrmDelaySeconds: 4,
      );

      final result = await service.saveToQuark(
        shareUrl: 'https://pan.quark.cn/s/abc123',
        saveFolderName: '三体',
        networkStorage: storage,
      );

      expect(
        saveCall,
        {
          'shareUrl': 'https://pan.quark.cn/s/abc123',
          'cookie': 'kps=test',
          'toPdirFid': 'folder-id',
          'toPdirPath': '/影视',
          'saveFolderName': '三体',
        },
      );
      expect(
        triggerCall,
        {
          'webhookUrl': 'https://strm.example.com/hook',
          'taskName': 'quark-sync',
          'storagePath': '/影视',
          'delay': 4,
        },
      );
      expect(resolveIncludeConfiguredSources, isTrue);
      expect(
        refreshCall,
        {
          'sourceIds': ['quark-main', 'nas-main'],
          'delaySeconds': 6,
        },
      );
      expect(result.saveResult.targetFolderPath, '/影视/三体');
      expect(
        result.buildSuccessMessage(),
        '已提交到夸克，任务 task-1，保存 3 个，略过 1 个，STRM 已延迟 4 秒触发，6 秒后刷新媒体源',
      );
    });

    test('skips smart strm when only duplicate files were found', () async {
      var triggerCalled = false;
      Map<String, Object?>? refreshCall;
      var resolveIncludeConfiguredSources = true;
      final service = QuarkSaveWorkflowService(
        saveShareLink: ({
          required String shareUrl,
          required String cookie,
          String toPdirFid = '0',
          String toPdirPath = '/',
          String saveFolderName = '',
        }) async {
          return const QuarkSaveResult(
            taskId: '',
            savedCount: 0,
            skippedCount: 5,
            targetFolderPath: '/影视/乘风破浪',
          );
        },
        triggerSmartStrm: ({
          required String webhookUrl,
          required String taskName,
          String storagePath = '',
          int delay = 0,
        }) async {
          triggerCalled = true;
          return const SmartStrmTriggerResult(
            message: '',
            addedCount: null,
            rawPayload: {},
          );
        },
        resolveRefreshSourceIds: ({
          required NetworkStorageConfig networkStorage,
          required bool includeConfiguredSources,
        }) {
          resolveIncludeConfiguredSources = includeConfiguredSources;
          return const ['quark-main'];
        },
        refreshSelectedSources: ({
          required List<String> sourceIds,
          required int delaySeconds,
        }) async {
          refreshCall = {
            'sourceIds': sourceIds,
            'delaySeconds': delaySeconds,
          };
        },
      );
      const storage = NetworkStorageConfig(
        quarkCookie: 'kps=test',
        smartStrmWebhookUrl: 'https://strm.example.com/hook',
        smartStrmTaskName: 'quark-sync',
        refreshDelaySeconds: 0,
      );

      final result = await service.saveToQuark(
        shareUrl: 'https://pan.quark.cn/s/def456',
        saveFolderName: '乘风破浪',
        networkStorage: storage,
      );

      expect(triggerCalled, isFalse);
      expect(resolveIncludeConfiguredSources, isFalse);
      expect(
        refreshCall,
        {
          'sourceIds': ['quark-main'],
          'delaySeconds': 1,
        },
      );
      expect(
        result.buildSuccessMessage(),
        '已提交到夸克，保存 0 个，略过 5 个，1 秒后刷新媒体源',
      );
    });
  });
}
