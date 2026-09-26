import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/features/search/application/aliyun_to115_workflow.dart';
import 'package:starflow/features/search/data/aliyun_transfer_journal.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/aliyun_transfer_tasks_page.dart';

class _Journal extends Fake implements AliyunTransferJournal {
  final rows = <Map<String, dynamic>>[
    {
      'id': 'task',
      'saveName': '电影',
      'stage': '待恢复',
      'stagingName': 'Starflow-transfer-test',
      'files': <String, dynamic>{}
    }
  ];
  @override
  Future<List<Map<String, dynamic>>> list() async => rows;
  @override
  Future<void> remove(String id) async {
    rows.clear();
  }
}

class _Workflow extends Fake implements AliyunTo115Workflow {
  final operations = <bool>[];
  @override
  bool get isRunning => false;
  @override
  Future<String> resume(String id, NetworkStorageConfig current,
      {bool cleanupOnly = false}) async {
    operations.add(cleanupOnly);
    return '已完成';
  }
}

void main() {
  for (final tv in [false, true]) {
    testWidgets('task history resume and confirmed cleanup tv=$tv',
        (tester) async {
      tester.view.physicalSize =
          tv ? const Size(1920, 1080) : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final journal = _Journal();
      final workflow = _Workflow();
      await tester.pumpWidget(ProviderScope(overrides: [
        aliyunTransferJournalProvider.overrideWithValue(journal),
        aliyunTo115WorkflowProvider.overrideWithValue(workflow),
        isTelevisionProvider.overrideWith((ref) => tv),
      ], child: const MaterialApp(home: AliyunTransferTasksPage())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续任务'));
      await tester.pumpAndSettle();
      expect(workflow.operations, [false]);
      await tester.tap(find.text('核验并清理副本'));
      await tester.pumpAndSettle();
      expect(workflow.operations, [false]);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('核验并清理副本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('核验并清理'));
      await tester.pumpAndSettle();
      expect(workflow.operations, [false, true]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
