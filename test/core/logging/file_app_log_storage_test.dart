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
}
