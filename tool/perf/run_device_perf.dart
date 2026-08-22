import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const _expectedScenarios = <String>[
  'startup',
  'home_first_frame',
  'detail_open',
  'player_open',
  'media_index',
];

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options.help) {
    stdout.write(_usage);
    return;
  }
  if (options.runs < 3) {
    stderr.writeln('至少需要 3 次运行才能形成有意义的分位数；建议 5–10 次。');
    exitCode = 64;
    return;
  }

  final devices = await _flutterJson(<String>['devices', '--machine']);
  final availableDevices = (devices as List).cast<Map<String, dynamic>>();
  final device = _selectDevice(availableDevices, options.deviceId);
  final deviceId = device['id'] as String;
  final timestamp =
      DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
  final outputDirectory = Directory(
    options.outputPath ?? 'build/perf/device-baseline-$timestamp',
  ).absolute;
  final runDirectory = Directory('${outputDirectory.path}/runs');
  await runDirectory.create(recursive: true);

  final flutterVersion = await _flutterJson(<String>['--version', '--machine']);
  final gitCommit = (await Process.run('git', <String>['rev-parse', 'HEAD']))
      .stdout
      .toString()
      .trim();
  final dirty = (await Process.run('git', <String>['status', '--porcelain']))
      .stdout
      .toString()
      .trim()
      .isNotEmpty;

  stdout.writeln('设备：${device['name']} ($deviceId)');
  stdout.writeln('模式：profile；重复：${options.runs} 次');
  stdout.writeln('输出：${outputDirectory.path}');

  final samples = <Map<String, dynamic>>[];
  for (var run = 1; run <= options.runs; run += 1) {
    final name = 'run_${run.toString().padLeft(2, '0')}';
    stdout.writeln('\n[$run/${options.runs}] 启动独立 profile 进程…');
    final process = await Process.start(
      'flutter',
      <String>[
        'drive',
        '--profile',
        '-d',
        deviceId,
        '--driver',
        'test_driver/performance_baseline_test.dart',
        '--target',
        'integration_test/performance_baseline_test.dart',
        '--dart-define=STARFLOW_PERF_RUN_ID=$run',
        '--dart-define=STARFLOW_PERF_FRAME_BUDGET_US=${options.frameBudgetMicros}',
      ],
      mode: ProcessStartMode.normal,
      environment: <String, String>{
        ...Platform.environment,
        'STARFLOW_PERF_OUTPUT_DIR': runDirectory.path,
        'STARFLOW_PERF_OUTPUT_NAME': name,
      },
    );
    final stdoutFuture = stdout.addStream(process.stdout);
    final stderrFuture = stderr.addStream(process.stderr);
    final result = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutFuture, stderrFuture]);
    if (result != 0) {
      throw ProcessException(
          'flutter', const <String>['drive'], '第 $run 次运行失败', result);
    }

    final file = File('${runDirectory.path}/$name.json');
    if (!await file.exists()) {
      throw StateError('运行成功但没有生成 ${file.path}');
    }
    final sample =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    _validateSample(sample, run);
    samples.add(sample);
    stdout.writeln('[$run/${options.runs}] 五个场景均已写入。');
  }

  final summary = <String, dynamic>{
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'mode': 'profile',
    'runCount': samples.length,
    'frameBudgetMs': options.frameBudgetMicros / 1000,
    'device': device,
    'flutter': flutterVersion,
    'git': <String, dynamic>{'commit': gitCommit, 'dirty': dirty},
    'scenarios': _aggregate(samples),
  };
  const encoder = JsonEncoder.withIndent('  ');
  await File('${outputDirectory.path}/summary.json')
      .writeAsString('${encoder.convert(summary)}\n');
  await File('${outputDirectory.path}/summary.md')
      .writeAsString(_markdown(summary));

  stdout.writeln('\n基线完成：');
  stdout.writeln('  ${outputDirectory.path}/summary.json');
  stdout.writeln('  ${outputDirectory.path}/summary.md');
}

Map<String, dynamic> _selectDevice(
  List<Map<String, dynamic>> devices,
  String? requestedId,
) {
  if (requestedId != null) {
    return devices.firstWhere(
      (device) => device['id'] == requestedId,
      orElse: () =>
          throw StateError('找不到设备 $requestedId。请先运行 flutter devices。'),
    );
  }
  final physical = devices.where((device) {
    return device['emulator'] == false &&
        (device['targetPlatform'] == 'ios' ||
            device['targetPlatform'] == 'android-arm64');
  }).toList(growable: false);
  if (physical.length != 1) {
    throw StateError('检测到 ${physical.length} 台可用真机；请用 --device <id> 明确指定。');
  }
  return physical.single;
}

Future<dynamic> _flutterJson(List<String> arguments) async {
  final result = await Process.run('flutter', arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
        'flutter', arguments, result.stderr.toString(), result.exitCode);
  }
  return jsonDecode(result.stdout.toString());
}

void _validateSample(Map<String, dynamic> sample, int run) {
  if (sample['mode'] != 'profile') {
    throw StateError('第 $run 次不是 profile 数据。');
  }
  final scenarios = sample['scenarios'];
  if (scenarios is! Map<String, dynamic>) {
    throw StateError('第 $run 次缺少 scenarios。');
  }
  for (final name in _expectedScenarios) {
    final value = scenarios[name];
    if (value is! Map<String, dynamic>) {
      throw StateError('第 $run 次缺少场景 $name。');
    }
    for (final metric in <String>[
      'durationMs',
      'slowFrameRate',
      'rssPeakMiB'
    ]) {
      if (value[metric] is! num) {
        throw StateError('第 $run 次场景 $name 缺少数值 $metric。');
      }
    }
    if ((value['frameCount'] as num? ?? 0) <= 0) {
      throw StateError('第 $run 次场景 $name 未捕获任何帧。');
    }
  }
}

Map<String, dynamic> _aggregate(List<Map<String, dynamic>> samples) {
  final result = <String, dynamic>{};
  for (final scenarioName in _expectedScenarios) {
    final rows = samples.map((sample) {
      return (sample['scenarios'] as Map<String, dynamic>)[scenarioName]
          as Map<String, dynamic>;
    }).toList(growable: false);
    result[scenarioName] = <String, dynamic>{
      'durationMs': _statistics(rows, 'durationMs'),
      'slowFrameRate': _statistics(rows, 'slowFrameRate'),
      'rssPeakMiB': _statistics(rows, 'rssPeakMiB'),
      'rssDeltaMiB': _statistics(rows, 'rssDeltaMiB'),
      'frameCount': _statistics(rows, 'frameCount'),
    };
  }
  return result;
}

Map<String, dynamic> _statistics(List<Map<String, dynamic>> rows, String key) {
  final values = rows.map((row) => (row[key] as num).toDouble()).toList()
    ..sort();
  return <String, dynamic>{
    'p50': _round(_percentile(values, 0.50)),
    'p95': _round(_percentile(values, 0.95)),
    'min': _round(values.first),
    'max': _round(values.last),
    'samples': values.map(_round).toList(growable: false),
  };
}

double _percentile(List<double> sorted, double percentile) {
  final rank = math.max(0, (sorted.length * percentile).ceil() - 1);
  return sorted[rank];
}

double _round(num value) => double.parse(value.toStringAsFixed(3));

String _markdown(Map<String, dynamic> summary) {
  final buffer = StringBuffer()
    ..writeln('# Starflow 真机性能基线')
    ..writeln()
    ..writeln('- 生成时间（UTC）：${summary['generatedAt']}')
    ..writeln('- 模式：profile')
    ..writeln(
        '- 设备：${(summary['device'] as Map)['name']} (${(summary['device'] as Map)['id']})')
    ..writeln('- 样本数：${summary['runCount']}')
    ..writeln('- 慢帧阈值：${summary['frameBudgetMs']} ms')
    ..writeln()
    ..writeln(
        '| 场景 | 时长 p50 / p95 (ms) | 慢帧率 p50 / p95 | 峰值 RSS p50 / p95 (MiB) | RSS 增量 p50 / p95 (MiB) |')
    ..writeln('|---|---:|---:|---:|---:|');
  final scenarios = summary['scenarios'] as Map<String, dynamic>;
  for (final name in _expectedScenarios) {
    final row = scenarios[name] as Map<String, dynamic>;
    final duration = row['durationMs'] as Map<String, dynamic>;
    final slow = row['slowFrameRate'] as Map<String, dynamic>;
    final peak = row['rssPeakMiB'] as Map<String, dynamic>;
    final delta = row['rssDeltaMiB'] as Map<String, dynamic>;
    buffer.writeln(
      '| $name | ${duration['p50']} / ${duration['p95']} | '
      '${_percent(slow['p50'])} / ${_percent(slow['p95'])} | '
      '${peak['p50']} / ${peak['p95']} | ${delta['p50']} / ${delta['p95']} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('原始逐次数据位于 `runs/`，机器可读聚合数据位于 `summary.json`。');
  return buffer.toString();
}

String _percent(Object? value) {
  return '${(((value as num?) ?? 0) * 100).toStringAsFixed(2)}%';
}

class _Options {
  const _Options({
    required this.runs,
    required this.frameBudgetMicros,
    required this.help,
    this.deviceId,
    this.outputPath,
  });

  final String? deviceId;
  final int runs;
  final String? outputPath;
  final int frameBudgetMicros;
  final bool help;

  factory _Options.parse(List<String> arguments) {
    String? deviceId;
    String? outputPath;
    var runs = 5;
    var frameBudgetMicros = 16667;
    var help = false;
    for (var index = 0; index < arguments.length; index += 1) {
      final argument = arguments[index];
      String nextValue() {
        if (index + 1 >= arguments.length) {
          throw FormatException('$argument 缺少值。');
        }
        index += 1;
        return arguments[index];
      }

      switch (argument) {
        case '--device':
          deviceId = nextValue();
        case '--runs':
          runs = int.parse(nextValue());
        case '--output':
          outputPath = nextValue();
        case '--frame-budget-ms':
          frameBudgetMicros = (double.parse(nextValue()) * 1000).round();
        case '--help':
        case '-h':
          help = true;
        default:
          throw FormatException('未知参数：$argument\n$_usage');
      }
    }
    return _Options(
      deviceId: deviceId,
      runs: runs,
      outputPath: outputPath,
      frameBudgetMicros: frameBudgetMicros,
      help: help,
    );
  }
}

const _usage = '''
Starflow 真机 profile 性能基线

用法：
  dart run tool/perf/run_device_perf.dart [选项]

选项：
  --device <id>             指定 flutter devices 中的真机；只有一台真机时可省略
  --runs <n>                独立进程重复次数，默认 5，最少 3
  --output <directory>      输出目录，默认 build/perf/device-baseline-<timestamp>
  --frame-budget-ms <ms>    慢帧阈值，默认 16.667
  -h, --help                显示帮助
''';
