import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:starflow/core/utils/seed_data.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/data/app_settings_repository.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/network_storage_settings_page.dart';

const _warning = '115 同步删除未就绪：未选择 WebDAV 删除监听目录';
const _source = MediaSourceConfig(
  id: 'nas-115',
  name: 'NAS',
  kind: MediaSourceKind.nas,
  endpoint: 'https://nas.test/dav/strm/115/',
  libraryPath: 'https://nas.test/dav/strm/115/',
  enabled: true,
);
const _quarkScope = NetworkStorageWebDavDirectory(
  sourceId: 'nas-quark',
  directoryId: 'https://nas.test/dav/strm/quark/',
);

void main() {
  testWidgets(
      '115 scope selection persists independently and updates readiness',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _MemorySettingsRepository(
      SeedData.defaultSettings.copyWith(
        mediaSources: const [_source],
        networkStorage: const NetworkStorageConfig(
          cloud115Cookie: 'test',
          syncDelete115Enabled: true,
          syncDeleteQuarkEnabled: true,
          syncDeleteQuarkWebDavDirectories: [_quarkScope],
        ),
      ),
    );
    final container = ProviderContainer(overrides: [
      appSettingsRepositoryProvider.overrideWithValue(repository),
      webDavNasClientProvider.overrideWithValue(_EmptyWebDavNasClient()),
    ]);
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => NetworkStorageEditorPage(
                    initial: container.read(appSettingsProvider).networkStorage,
                    section: NetworkStorageEditorSection.cloud115,
                  ),
                ),
              ),
              child: const Text('打开 115 设置'),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('打开 115 设置'));
    await tester.pumpAndSettle();
    expect(find.text(_warning), findsOneWidget);

    await tester.ensureVisible(find.text('添加 NAS'));
    await tester.tap(find.text('添加 NAS'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选这里'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(_warning), findsNothing);
    final selected = repository.settings.networkStorage;
    expect(selected.syncDelete115Enabled, isTrue);
    expect(selected.syncDelete115WebDavDirectories.single.sourceId, _source.id);
    expect(selected.syncDelete115WebDavDirectories.single.directoryId,
        _source.libraryPath);
    expect(selected.syncDeleteQuarkEnabled, isTrue);
    expect(selected.syncDeleteQuarkWebDavDirectories.single.toJson(),
        _quarkScope.toJson());

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开 115 设置'));
    await tester.pumpAndSettle();
    expect(find.text(_warning), findsNothing);
    expect(find.text('监听中'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('移除'));
    await tester.tap(find.byTooltip('移除'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_warning), findsOneWidget);
    expect(repository.settings.networkStorage.syncDelete115WebDavDirectories,
        isEmpty);
    expect(
        repository
            .settings.networkStorage.syncDeleteQuarkWebDavDirectories.single
            .toJson(),
        _quarkScope.toJson());

    await tester.ensureVisible(find.text('同步删除115目录'));
    await tester.tap(find.text('同步删除115目录'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(_warning), findsNothing);
    expect(repository.settings.networkStorage.syncDelete115Enabled, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _EmptyWebDavNasClient extends WebDavNasClient {
  _EmptyWebDavNasClient()
      : super(MockClient((_) async => fail('No HTTP requests expected')));

  @override
  Future<List<MediaCollection>> fetchCollections(
    MediaSourceConfig source, {
    String? directoryId,
  }) async =>
      const [];
}

class _MemorySettingsRepository implements AppSettingsRepository {
  _MemorySettingsRepository(this.settings);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings settings) async {
    this.settings = AppSettings.fromJson(settings.toJson());
  }
}
