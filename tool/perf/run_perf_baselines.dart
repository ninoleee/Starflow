import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

class _PerfScenario {
  const _PerfScenario({
    required this.id,
    required this.description,
    required this.command,
  });

  final String id;
  final String description;
  final List<String> command;
}

class _PerfRunResult {
  const _PerfRunResult({
    required this.id,
    required this.description,
    required this.runs,
    required this.p50Ms,
    required this.p95Ms,
  });

  final String id;
  final String description;
  final List<int> runs;
  final int p50Ms;
  final int p95Ms;

  Map<String, Object> toJson() {
    return <String, Object>{
      'id': id,
      'description': description,
      'runsMs': runs,
      'p50Ms': p50Ms,
      'p95Ms': p95Ms,
    };
  }
}

Future<void> main(List<String> args) async {
  final repoRoot = Directory.current.path;
  final runs = _parseRuns(args);
  final scenarioFilter = _parseScenarioFilter(args);
  final outputPath = _parseOutputPath(args) ??
      '$repoRoot\\tool\\perf\\perf_baselines.json';

  final scenarios = <_PerfScenario>[
    const _PerfScenario(
      id: 'startup',
      description: '启动 smoke',
      command: <String>[
        'flutter',
        'test',
        'test/perf/bootstrap_smoke_test.dart',
      ],
    ),
    const _PerfScenario(
      id: 'home_first_screen',
      description: '首页首屏/装配 smoke',
      command: <String>[
        'flutter',
        'test',
        'test/home_controller_test.dart',
      ],
    ),
    const _PerfScenario(
      id: 'detail_first_screen',
      description: '详情首屏 enrichment smoke',
      command: <String>[
        'flutter',
        'test',
        'test/media_detail_enrichment_test.dart',
      ],
    ),
    const _PerfScenario(
      id: 'player_open',
      description: '播放器打开准备与路由 smoke',
      command: <String>[
        'flutter',
        'test',
        'test/features/playback/application/playback_startup_preparation_test.dart',
        'test/features/playback/application/playback_startup_routing_test.dart',
        'test/perf/player_open_smoke_test.dart',
      ],
    ),
    const _PerfScenario(
      id: 'index_refresh',
      description: '索引刷新 smoke',
      command: <String>[
        'flutter',
        'test',
        'test/media_repository_quark_source_test.dart',
      ],
    ),
  ].where((scenario) {
    if (scenarioFilter == null || scenarioFilter.isEmpty) {
      return true;
    }
    return scenarioFilter.contains(scenario.id);
  }).toList(growable: false);

  if (scenarios.isEmpty) {
    stderr.writeln('No scenarios selected.');
    exitCode = 1;
    return;
  }

  final results = <_PerfRunResult>[];
  for (final scenario in scenarios) {
    stdout.writeln('Running ${scenario.id} (${scenario.description})...');
    final runDurations = <int>[];
    for (var index = 0; index < runs; index += 1) {
      final stopwatch = Stopwatch()..start();
      final process = await Process.start(
        scenario.command.first,
        scenario.command.skip(1).toList(growable: false),
        workingDirectory: repoRoot,
        runInShell: true,
      );
      await stdout.addStream(process.stdout);
      await stderr.addStream(process.stderr);
      final processExitCode = await process.exitCode;
      stopwatch.stop();
      if (processExitCode != 0) {
        stderr.writeln(
          'Scenario ${scenario.id} failed on run ${index + 1} with exit code $processExitCode.',
        );
        exitCode = processExitCode;
        return;
      }
      runDurations.add(stopwatch.elapsedMilliseconds);
    }
    results.add(
      _PerfRunResult(
        id: scenario.id,
        description: scenario.description,
        runs: runDurations,
        p50Ms: _percentile(runDurations, 0.5),
        p95Ms: _percentile(runDurations, 0.95),
      ),
    );
  }

  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(
      <String, Object>{
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'runsPerScenario': runs,
        'results': results.map((result) => result.toJson()).toList(),
      },
    ),
  );

  stdout.writeln('Wrote baseline report to $outputPath');
}

int _parseRuns(List<String> args) {
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--runs' && index + 1 < args.length) {
      final parsed = int.tryParse(args[index + 1]);
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }
  }
  return 5;
}

Set<String>? _parseScenarioFilter(List<String> args) {
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--scenario' && index + 1 < args.length) {
      return args[index + 1]
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet();
    }
  }
  return null;
}

String? _parseOutputPath(List<String> args) {
  for (var index = 0; index < args.length; index += 1) {
    final arg = args[index];
    if (arg == '--output' && index + 1 < args.length) {
      final value = args[index + 1].trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  return null;
}

int _percentile(List<int> values, double percentile) {
  if (values.isEmpty) {
    return 0;
  }
  final sorted = values.toList(growable: false)..sort();
  final targetIndex = math.max(0, (sorted.length * percentile).ceil() - 1);
  final boundedIndex = targetIndex.clamp(0, sorted.length - 1);
  return sorted[boundedIndex];
}
