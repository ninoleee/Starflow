import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/library/application/webdav_scrape_progress.dart';

void main() {
  test('throttles repeated progress updates until the interval elapses',
      () async {
    final controller = WebDavScrapeProgressController(
      normalModeMinUpdateInterval: const Duration(milliseconds: 20),
      playbackModeMinUpdateInterval: const Duration(milliseconds: 40),
    );
    addTearDown(controller.dispose);

    controller.startScanning(
      sourceId: 'nas-main',
      sourceName: 'NAS',
      totalCollections: 10,
    );
    controller.updateScanning(
      sourceId: 'nas-main',
      current: 1,
      total: 10,
      detail: 'Season 1',
    );

    expect(controller.state['nas-main']?.current, 0);

    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.state['nas-main']?.current, 1);
    expect(controller.state['nas-main']?.detail, 'Season 1');
  });

  test('flushes completion progress immediately inside the throttle window',
      () async {
    final controller = WebDavScrapeProgressController(
      normalModeMinUpdateInterval: const Duration(milliseconds: 20),
      playbackModeMinUpdateInterval: const Duration(milliseconds: 40),
    );
    addTearDown(controller.dispose);

    controller.startScanning(
      sourceId: 'nas-main',
      sourceName: 'NAS',
      totalCollections: 1,
    );
    controller.startIndexing(
      sourceId: 'nas-main',
      totalItems: 10,
    );
    controller.updateIndexing(
      sourceId: 'nas-main',
      current: 1,
      total: 10,
      detail: 'episode-01.mkv',
    );

    expect(controller.state['nas-main']?.current, 0);

    controller.updateIndexing(
      sourceId: 'nas-main',
      current: 10,
      total: 10,
      detail: 'done',
    );

    expect(controller.state['nas-main']?.current, 10);
    expect(controller.state['nas-main']?.detail, 'done');
  });
}
