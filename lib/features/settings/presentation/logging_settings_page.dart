import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_log_api.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/starflow_action_dialog.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/log_export_page.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

final appLogSummaryProvider =
    FutureProvider.autoDispose<AppLogSummary>((ref) => appLogger.inspect());
final appLogEntriesProvider = FutureProvider.autoDispose<List<AppLogEntry>>(
  (ref) => appLogger.read(limit: 300),
);

const double _logPreviewHeight = 560;

class LoggingSettingsPage extends ConsumerStatefulWidget {
  const LoggingSettingsPage({super.key});

  @override
  ConsumerState<LoggingSettingsPage> createState() =>
      _LoggingSettingsPageState();
}

class _LoggingSettingsPageState extends ConsumerState<LoggingSettingsPage> {
  late final FocusNode _exportFocusNode;
  late final FocusNode _clearFocusNode;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _exportFocusNode = FocusNode(debugLabel: 'settings:logging:export');
    _clearFocusNode = FocusNode(debugLabel: 'settings:logging:clear');
  }

  @override
  void dispose() {
    _exportFocusNode.dispose();
    _clearFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final summaryAsync = ref.watch(appLogSummaryProvider);
    final entriesAsync = ref.watch(appLogEntriesProvider);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;

    return SettingsPageScaffold(
      primary: true,
      children: [
        SectionPanel(
          title: '日志设置',
          subtitle: '日志只保存在当前设备，并自动隐藏常见的 Cookie、Token、密码和授权信息。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsToggleTile(
                title: '保存本地日志',
                subtitle: appLogger.isSupported
                    ? '记录应用错误、播放、字幕和元数据处理过程，便于排查问题。'
                    : '当前平台不支持写入本地日志文件。',
                value: settings.localLoggingEnabled && appLogger.isSupported,
                onChanged: _updating || !appLogger.isSupported
                    ? null
                    : _setLoggingEnabled,
                focusId: 'settings:logging:enabled',
              ),
              const SizedBox(height: 14),
              SettingsSelectionTile(
                title: '最大保存大小',
                subtitle: '达到上限后自动覆盖最早的日志。',
                value: '${settings.localLogMaxSizeMb} MB',
                onPressed: _updating || !appLogger.isSupported
                    ? null
                    : () => _selectMaxSize(settings.localLogMaxSizeMb),
                focusId: 'settings:logging:max-size',
              ),
              const SettingsSectionTitle(label: '记录级别'),
              Text(
                '只把选中的级别写入本地文件。关闭某个级别不会删除已有日志。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              _LogLevelSelector(
                selectedLevels: settings.localLogRecordedLevels,
                enabled: !_updating &&
                    settings.localLoggingEnabled &&
                    appLogger.isSupported,
                focusPrefix: 'settings:logging:record',
                onToggle: (level) => _toggleRecordedLevel(
                  level,
                  settings.localLogRecordedLevels,
                ),
              ),
              const SettingsSectionTitle(label: '预览展示级别'),
              Text(
                '只影响下方预览，不改变实际写入的日志。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 10),
              _LogLevelSelector(
                selectedLevels: settings.localLogVisibleLevels,
                enabled: !_updating && appLogger.isSupported,
                focusPrefix: 'settings:logging:visible',
                onMoveDown:
                    isTelevision ? () => _exportFocusNode.requestFocus() : null,
                onToggle: (level) => _toggleVisibleLevel(
                  level,
                  settings.localLogVisibleLevels,
                ),
              ),
              const SizedBox(height: 18),
              summaryAsync.when(
                data: (summary) => _LogUsageCard(
                  summary: summary,
                  isTelevision: isTelevision,
                ),
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Text('读取日志占用失败：$error'),
              ),
              const SizedBox(height: 16),
              TvDirectionalActionPanel(
                enabled: isTelevision,
                onMoveDown: () => _clearFocusNode.requestFocus(),
                child: SettingsActionButton(
                  label: '导出日志',
                  icon: Icons.ios_share_rounded,
                  onPressed: !appLogger.isSupported ? null : _openLogExport,
                  focusNode: _exportFocusNode,
                  focusId: 'settings:logging:export',
                  compact: false,
                ),
              ),
              const SizedBox(height: 12),
              TvDirectionalActionPanel(
                enabled: isTelevision,
                onMoveUp: () => _exportFocusNode.requestFocus(),
                child: SettingsActionButton(
                  label: _updating ? '正在处理…' : '清理全部日志',
                  icon: Icons.delete_sweep_rounded,
                  onPressed: _updating || !appLogger.isSupported
                      ? null
                      : _confirmClear,
                  variant: StarflowButtonVariant.danger,
                  focusNode: _clearFocusNode,
                  focusId: 'settings:logging:clear',
                  compact: false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionPanel(
          title: '日志预览',
          subtitle: '读取最近 300 条，并展示筛选后的最新 100 条。',
          actionLabel: '刷新',
          onActionPressed: () => ref.invalidate(appLogEntriesProvider),
          child: entriesAsync.when(
            data: (entries) => _LogPreview(
              entries: entries,
              visibleLevels: settings.localLogVisibleLevels,
              isTelevision: isTelevision,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (error, _) => Text('读取日志失败：$error'),
          ),
        ),
      ],
    );
  }

  Future<void> _setLoggingEnabled(bool enabled) async {
    setState(() => _updating = true);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setLocalLoggingEnabled(enabled);
      ref.invalidate(appLogSummaryProvider);
      ref.invalidate(appLogEntriesProvider);
      _showMessage(enabled ? '本地日志已开启' : '本地日志已关闭');
    } catch (error) {
      _showMessage('更新日志设置失败：$error');
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _selectMaxSize(int currentValue) async {
    final selected = await showSettingsOptionDialog<int>(
      context: context,
      title: '最大日志保存大小',
      options: kLocalLogMaxSizeOptionsMb,
      labelBuilder: (value) => '$value MB',
      currentValue: currentValue,
    );
    if (selected == null || selected == currentValue || !mounted) {
      return;
    }
    setState(() => _updating = true);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setLocalLogMaxSizeMb(selected);
      ref.invalidate(appLogSummaryProvider);
      ref.invalidate(appLogEntriesProvider);
      _showMessage('最大日志保存大小已设为 $selected MB');
    } catch (error) {
      _showMessage('更新日志容量失败：$error');
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _toggleRecordedLevel(
    AppLogLevel level,
    Set<AppLogLevel> currentLevels,
  ) async {
    final next = Set<AppLogLevel>.from(currentLevels);
    next.contains(level) ? next.remove(level) : next.add(level);
    setState(() => _updating = true);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setLocalLogRecordedLevels(next);
      ref.invalidate(appLogEntriesProvider);
    } catch (error) {
      _showMessage('更新记录级别失败：$error');
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _toggleVisibleLevel(
    AppLogLevel level,
    Set<AppLogLevel> currentLevels,
  ) async {
    final next = Set<AppLogLevel>.from(currentLevels);
    next.contains(level) ? next.remove(level) : next.add(level);
    setState(() => _updating = true);
    try {
      await ref
          .read(settingsControllerProvider.notifier)
          .setLocalLogVisibleLevels(next);
    } catch (error) {
      _showMessage('更新预览级别失败：$error');
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showStarflowActionDialog<bool>(
      context: context,
      title: '清理全部日志？',
      message: '当前设备上的日志文件会被删除，此操作不会影响应用设置和媒体数据。',
      actions: const [
        StarflowDialogAction<bool>(label: '取消', value: false),
        StarflowDialogAction<bool>(
          label: '清理',
          value: true,
          icon: Icons.delete_sweep_rounded,
          variant: StarflowButtonVariant.danger,
          autofocus: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _updating = true);
    try {
      await appLogger.clear();
      ref.invalidate(appLogSummaryProvider);
      ref.invalidate(appLogEntriesProvider);
      _showMessage('日志已清理');
    } catch (error) {
      _showMessage('清理日志失败：$error');
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  Future<void> _openLogExport() {
    return Navigator.of(context, rootNavigator: true).push<void>(
      NoAnimationMaterialPageRoute<void>(
        builder: (context) => const LogExportPage(),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _LogLevelSelector extends StatelessWidget {
  const _LogLevelSelector({
    required this.selectedLevels,
    required this.enabled,
    required this.focusPrefix,
    required this.onToggle,
    this.onMoveDown,
  });

  final Set<AppLogLevel> selectedLevels;
  final bool enabled;
  final String focusPrefix;
  final ValueChanged<AppLogLevel> onToggle;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final level in AppLogLevel.values)
          StarflowChipButton(
            label: _levelLabel(level),
            icon: _levelIcon(level),
            selected: selectedLevels.contains(level),
            onPressed: enabled ? () => onToggle(level) : null,
            focusId: '$focusPrefix:${level.name}',
            accentColor: _levelColor(Theme.of(context).colorScheme, level),
            onMoveDown: onMoveDown,
          ),
      ],
    );
  }
}

class _LogPreview extends StatefulWidget {
  const _LogPreview({
    required this.entries,
    required this.visibleLevels,
    required this.isTelevision,
  });

  final List<AppLogEntry> entries;
  final Set<AppLogLevel> visibleLevels;
  final bool isTelevision;

  @override
  State<_LogPreview> createState() => _LogPreviewState();
}

class _LogPreviewState extends State<_LogPreview> {
  late final ScrollController _scrollController;
  final GlobalKey _viewportKey = GlobalKey(
    debugLabel: 'settings:logging:preview-viewport',
  );
  List<FocusNode> _focusNodes = const <FocusNode>[];
  List<String> _entryKeys = const <String>[];

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      debugLabel: 'settings:logging:preview',
    );
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant _LogPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
  }

  @override
  void dispose() {
    _disposeFocusNodes();
    _scrollController.dispose();
    super.dispose();
  }

  List<AppLogEntry> get _visibleEntries => widget.entries
      .where((entry) => widget.visibleLevels.contains(entry.level))
      .toList(growable: false)
      .reversed
      .take(100)
      .toList(growable: false);

  void _syncFocusNodes() {
    if (!widget.isTelevision) {
      _disposeFocusNodes();
      _entryKeys = const <String>[];
      return;
    }
    final entries = _visibleEntries;
    final nextKeys = <String>[
      for (var index = 0; index < entries.length; index++)
        '${entries[index].timestamp.microsecondsSinceEpoch}:'
            '${entries[index].level.name}:${entries[index].category}:'
            '${entries[index].message}:$index',
    ];
    if (_sameStringList(_entryKeys, nextKeys)) {
      return;
    }
    _disposeFocusNodes();
    _entryKeys = nextKeys;
    _focusNodes = <FocusNode>[
      for (var index = 0; index < nextKeys.length; index++)
        FocusNode(debugLabel: 'settings:logging:entry:$index'),
    ];
  }

  void _disposeFocusNodes() {
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    _focusNodes = const <FocusNode>[];
  }

  void _moveFocus(int index, int delta) {
    final targetIndex = index + delta;
    if (targetIndex < 0 || targetIndex >= _focusNodes.length) {
      return;
    }
    _focusNodes[targetIndex].requestFocus();
  }

  void _ensurePreviewEntryVisible(BuildContext entryContext) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final renderObject = entryContext.findRenderObject();
      if (renderObject == null) {
        return;
      }
      _scrollController.position.ensureVisible(
        renderObject,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      final viewportContext = _viewportKey.currentContext;
      if (viewportContext != null) {
        _ensureWidgetVisible(viewportContext);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _visibleEntries;
    final theme = Theme.of(context);
    final emptyMessage = widget.visibleLevels.isEmpty
        ? '尚未选择要展示的日志级别。'
        : visibleEntries.isEmpty
            ? '当前没有符合展示级别的日志。'
            : null;
    final content = emptyMessage != null
        ? Center(
            child: Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              key: const ValueKey<String>('logging-preview-scroll'),
              controller: _scrollController,
              primary: false,
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  for (var index = 0;
                      index < visibleEntries.length;
                      index++) ...[
                    _LogEntryCard(
                      entry: visibleEntries[index],
                      isTelevision: widget.isTelevision,
                      focusNode:
                          widget.isTelevision ? _focusNodes[index] : null,
                      onFocused: widget.isTelevision
                          ? _ensurePreviewEntryVisible
                          : null,
                      onMoveUp: widget.isTelevision && index > 0
                          ? () => _moveFocus(index, -1)
                          : null,
                      onMoveDown: widget.isTelevision &&
                              index < visibleEntries.length - 1
                          ? () => _moveFocus(index, 1)
                          : null,
                    ),
                    if (index != visibleEntries.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          );
    return KeyedSubtree(
      key: const ValueKey<String>('logging-preview-viewport'),
      child: SizedBox(
        key: _viewportKey,
        height: _logPreviewHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest.withValues(
              alpha: 0.72,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.92),
              width: 1.5,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({
    required this.entry,
    required this.isTelevision,
    this.focusNode,
    this.onFocused,
    this.onMoveUp,
    this.onMoveDown,
  });

  final AppLogEntry entry;
  final bool isTelevision;
  final FocusNode? focusNode;
  final ValueChanged<BuildContext>? onFocused;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _levelColor(theme.colorScheme, entry.level);
    final details = <String>[
      if (entry.fields.isNotEmpty) jsonEncode(entry.fields),
      if (entry.error.trim().isNotEmpty) entry.error,
      if (entry.stackTrace.trim().isNotEmpty)
        _truncate(entry.stackTrace.trim(), 1200),
    ];
    Widget previewText(String value, {TextStyle? style}) {
      return isTelevision
          ? Text(value, style: style)
          : SelectableText(value, style: style);
    }

    Widget buildCard(bool focused) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: focused
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.34)
              : theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: focused
                ? (theme.brightness == Brightness.dark
                    ? Colors.white
                    : theme.colorScheme.primary)
                : color.withValues(alpha: 0.72),
            width: focused ? 3 : 1.5,
          ),
          boxShadow: focused
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.30),
                    blurRadius: 22,
                    spreadRadius: 1,
                  ),
                ]
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: color.withValues(alpha: 0.52),
                    ),
                  ),
                  child: Text(
                    _levelLabel(entry.level),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  _formatTimestamp(entry.timestamp),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (entry.category.isNotEmpty)
                  Text(
                    entry.category,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            previewText(
              entry.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.64,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: previewText(
                  details.join('\n'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final card = focusNode == null
        ? buildCard(false)
        : AnimatedBuilder(
            animation: focusNode!,
            builder: (context, child) => buildCard(focusNode!.hasFocus),
          );
    if (!isTelevision || focusNode == null) {
      return card;
    }
    return TvDirectionalActionPanel(
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      child: TvFocusableAction(
        onPressed: () {},
        onFocused: () => onFocused?.call(context),
        focusNode: focusNode,
        focusId: focusNode!.debugLabel,
        borderRadius: BorderRadius.circular(16),
        visualStyle: TvFocusVisualStyle.none,
        focusScale: 1.012,
        child: card,
      ),
    );
  }
}

class _LogUsageCard extends StatelessWidget {
  const _LogUsageCard({
    required this.summary,
    required this.isTelevision,
  });

  final AppLogSummary summary;
  final bool isTelevision;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final path = summary.directoryPath.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前占用 ${_formatBytes(summary.totalBytes)} · ${summary.fileCount} 个文件',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (path.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (isTelevision)
              Text(
                path,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            else
              SelectableText(
                path,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    return '${kilobytes.toStringAsFixed(1)} KB';
  }
  return '${(kilobytes / 1024).toStringAsFixed(1)} MB';
}

String _levelLabel(AppLogLevel level) {
  return switch (level) {
    AppLogLevel.trace => '调试 TRACE',
    AppLogLevel.info => '信息 INFO',
    AppLogLevel.warning => '警告 WARNING',
    AppLogLevel.error => '错误 ERROR',
  };
}

IconData _levelIcon(AppLogLevel level) {
  return switch (level) {
    AppLogLevel.trace => Icons.bug_report_outlined,
    AppLogLevel.info => Icons.info_outline_rounded,
    AppLogLevel.warning => Icons.warning_amber_rounded,
    AppLogLevel.error => Icons.error_outline_rounded,
  };
}

Color _levelColor(ColorScheme colorScheme, AppLogLevel level) {
  return switch (level) {
    AppLogLevel.trace => colorScheme.onSurfaceVariant,
    AppLogLevel.info => colorScheme.primary,
    AppLogLevel.warning => const Color(0xFFE59A23),
    AppLogLevel.error => colorScheme.error,
  };
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final date =
      '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
  final time = '${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}';
  return '$date $time';
}

String _truncate(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}…';
}

bool _sameStringList(List<String> first, List<String> second) {
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

void _ensureWidgetVisible(BuildContext context) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) {
      return;
    }
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  });
}
