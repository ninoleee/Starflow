import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      await writeResponseData(
        data,
        destinationDirectory: Platform.environment['STARFLOW_PERF_OUTPUT_DIR'],
        testOutputFilename:
            Platform.environment['STARFLOW_PERF_OUTPUT_NAME'] ?? 'run',
      );
    },
    writeResponseOnFailure: true,
  );
}
