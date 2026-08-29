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

part 'logging_settings_widgets.part.dart';

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
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final summaryAsync = ref.watch(appLogSummaryProvider);
    final entriesAsync = ref.watch(appLogEntriesProvider);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;

    return SettingsPageScaffold(
      onBack: () => Navigator.of(context).pop(),
      children: [
        Text('日志', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 18),
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
                autofocus: true,
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
              SettingsActionButton(
                label: '导出日志',
                icon: Icons.ios_share_rounded,
                onPressed: !appLogger.isSupported ? null : _openLogExport,
                focusId: 'settings:logging:export',
                compact: false,
              ),
              const SizedBox(height: 12),
              SettingsActionButton(
                label: _updating ? '正在处理…' : '清理全部日志',
                icon: Icons.delete_sweep_rounded,
                onPressed:
                    _updating || !appLogger.isSupported ? null : _confirmClear,
                variant: StarflowButtonVariant.danger,
                focusId: 'settings:logging:clear',
                compact: false,
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
      SettingsMaterialPageRoute<void>(
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
