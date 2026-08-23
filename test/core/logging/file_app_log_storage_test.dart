import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger_impl_io.dart';

void main() {
  test('file log storage rotates within its configured capacity', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'starflow-log-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final storage = FileAppLogStorage(temporaryDirectory);

    for (var index = 0; index < 8; index++) {
      await storage.append(
        'entry-$index-${List<String>.filled(60, 'x').join()}\n',
        maxBytes: 240,
      );
    }

    final summary = await storage.inspect();
    expect(summary.supported, isTrue);
    expect(summary.fileCount, inInclusiveRange(1, 2));
    expect(summary.totalBytes, lessThanOrEqualTo(240));

    await storage.clear();
    final cleared = await storage.inspect();
    expect(cleared.fileCount, 0);
    expect(cleared.totalBytes, 0);
  });

  test('file log storage enforces a smaller updated capacity', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'starflow-log-limit-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final storage = FileAppLogStorage(temporaryDirectory);

    await storage.append(
      '${List<String>.filled(180, 'a').join()}\n',
      maxBytes: 400,
    );
    await storage.append(
      '${List<String>.filled(180, 'b').join()}\n',
      maxBytes: 400,
    );
    await storage.enforceLimit(100);

    final summary = await storage.inspect();
    expect(summary.fileCount, inInclusiveRange(1, 2));
    expect(summary.totalBytes, lessThanOrEqualTo(100));
  });

  test('file log storage reads the latest structured entries', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'starflow-log-read-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final storage = FileAppLogStorage(temporaryDirectory);

    for (var index = 0; index < 5; index++) {
      await storage.append(
        AppLogFormatter.format(
          level: index.isEven ? AppLogLevel.info : AppLogLevel.error,
          category: 'test',
          message: 'entry-$index',
        ),
        maxBytes: 4096,
      );
    }

    final entries = await storage.read(limit: 3);
    expect(entries.map((entry) => entry.message), [
      'entry-2',
      'entry-3',
      'entry-4',
    ]);
    expect(entries.last.level, AppLogLevel.info);
  });

  test('file log storage exports previous and active files in order', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'starflow-log-export-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final storage = FileAppLogStorage(temporaryDirectory);

    await storage.previousFile.writeAsString('previous-entry\n');
    await storage.activeFile.writeAsString('active-entry\n');

    final exported = await storage.export();
    expect(exported.fileCount, 2);
    expect(
        String.fromCharCodes(exported.bytes), 'previous-entry\nactive-entry\n');
  });

  test('file log storage merges native entries in timestamp order', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'starflow-native-log-read-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final storage = FileAppLogStorage(temporaryDirectory);

    await storage.nativeFile.writeAsString(
      AppLogFormatter.format(
        level: AppLogLevel.error,
        category: 'native.uncaught',
        message: 'native-crash',
        timestamp: DateTime.utc(2026, 8, 23, 9),
      ),
    );
    await storage.activeFile.writeAsString(
      AppLogFormatter.format(
        level: AppLogLevel.info,
        category: 'app.lifecycle',
        message: 'next-start',
        timestamp: DateTime.utc(2026, 8, 23, 10),
      ),
    );

    final summary = await storage.inspect();
    final entries = await storage.read();
    expect(summary.fileCount, 2);
    expect(entries.map((entry) => entry.message), [
      'native-crash',
      'next-start',
    ]);
  });

  test('native logging configuration survives clearing log files', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'starflow-native-log-config-test-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final logsDirectory = Directory('${temporaryDirectory.path}/logs');
    final storage = FileAppLogStorage(logsDirectory);

    await storage.writeNativeConfig(
      enabled: true,
      maxBytes: 12 * 1024 * 1024,
      recordedLevels: const <AppLogLevel>{
        AppLogLevel.warning,
        AppLogLevel.error,
      },
    );
    await logsDirectory.create(recursive: true);
    await storage.nativeFile.writeAsString('native-entry\n');
    await storage.clear();

    expect(await storage.nativeConfigFile.exists(), isTrue);
    expect(await storage.nativeConfigFile.readAsString(), contains('warning'));
    expect(await storage.nativeConfigFile.readAsString(), contains('error'));
    expect(await logsDirectory.exists(), isFalse);
  });
}
