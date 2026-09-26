import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/update/application/update_controller.dart';
import 'package:starflow/features/update/domain/app_update.dart';

class UpdateSettingsPage extends ConsumerWidget {
  const UpdateSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(updateControllerProvider);
    final state = controller.state;
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final supported = controller.isAndroid;
    final enabled = supported && controller.configured;
    final busy = controller.busy ||
        switch (state.phase) {
          UpdatePhase.checking ||
          UpdatePhase.downloading ||
          UpdatePhase.verifying ||
          UpdatePhase.installing =>
            true,
          _ => false,
        };
    final permissionRequired = supported &&
        state.phase == UpdatePhase.failed &&
        state.failure?.code == 'installPermissionRequired';
    final canInstall = state.packagePath != null &&
        (state.phase == UpdatePhase.readyToInstall ||
            state.phase == UpdatePhase.failed);
    final canDownload = state.artifact != null &&
        (state.phase == UpdatePhase.available ||
            state.phase == UpdatePhase.failed);
    final theme = Theme.of(context);

    return TvPageFocusScope(
      isTelevision: isTelevision,
      child: SettingsPageScaffold(
        enableUpdateNavigation: false,
        children: [
          Text('应用更新', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 18),
          Text('当前版本', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(state.currentVersion.isEmpty
              ? '尚未读取'
              : '${state.currentVersion} (${state.currentVersionCode})'),
          const SizedBox(height: 18),
          Semantics(
            liveRegion: true,
            child: Text(
              !supported
                  ? '此平台暂不支持应用内更新'
                  : !controller.configured
                      ? '未配置网络同步'
                      : _statusLabel(state.phase),
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (state.phase == UpdatePhase.failed && state.failure != null) ...[
            const SizedBox(height: 8),
            Text(
              state.failure!.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (state.phase == UpdatePhase.downloading ||
              state.phase == UpdatePhase.verifying) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.phase == UpdatePhase.downloading &&
                      (state.artifact?.size ?? 0) > 0
                  ? (state.receivedBytes / state.artifact!.size).clamp(0.0, 1.0)
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatBytes(state.receivedBytes)} / '
              '${_formatBytes(state.artifact?.size ?? 0)}',
            ),
          ],
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SettingsActionButton(
                focusId: 'update:check',
                autofocus: isTelevision,
                focusableWhenDisabled: true,
                label: state.phase == UpdatePhase.checking
                    ? '正在检查'
                    : state.phase == UpdatePhase.failed &&
                            !canInstall &&
                            !canDownload
                        ? '重试检查'
                        : '检查更新',
                icon: Icons.refresh_rounded,
                loading: state.phase == UpdatePhase.checking,
                onPressed: enabled && !busy ? controller.check : null,
              ),
              if (permissionRequired)
                SettingsActionButton(
                  focusId: 'update:permission',
                  label: '允许安装应用',
                  icon: Icons.settings_rounded,
                  onPressed:
                      busy ? null : controller.openInstallPermissionSettings,
                ),
              if (canInstall && supported)
                SettingsActionButton(
                  focusId: 'update:install',
                  label: state.phase == UpdatePhase.failed ? '重试安装' : '安装更新',
                  icon: Icons.install_mobile_rounded,
                  focusableWhenDisabled: true,
                  onPressed: busy ? null : controller.install,
                )
              else if (canDownload && enabled)
                SettingsActionButton(
                  focusId: 'update:download',
                  label: state.phase == UpdatePhase.failed ? '重试下载' : '下载更新',
                  icon: Icons.download_rounded,
                  focusableWhenDisabled: true,
                  onPressed: busy ? null : controller.download,
                ),
              if (state.phase == UpdatePhase.downloading ||
                  state.phase == UpdatePhase.verifying)
                SettingsActionButton(
                  focusId: 'update:cancel',
                  label: '取消下载',
                  icon: Icons.close_rounded,
                  onPressed: controller.cancel,
                ),
            ],
          ),
          if (state.update case final update?) ...[
            const SettingsSectionTitle(label: '目标版本'),
            Text('${update.version} (${update.versionCode})'),
            if (state.artifact case final artifact?) ...[
              const SizedBox(height: 8),
              Text('安装包大小：${_formatBytes(artifact.size)}'),
            ],
            const SettingsSectionTitle(label: '更新内容'),
            if (update.releaseNotes.isEmpty)
              const Text('暂无更新说明')
            else
              for (final note in update.releaseNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(note),
                ),
          ],
        ],
      ),
    );
  }
}

String _statusLabel(UpdatePhase phase) => switch (phase) {
      UpdatePhase.idle => '尚未检查更新',
      UpdatePhase.checking => '正在检查更新',
      UpdatePhase.unconfigured => '未配置网络同步',
      UpdatePhase.upToDate => '当前已是最新版本',
      UpdatePhase.available => '发现新版本',
      UpdatePhase.downloading => '正在下载安装包',
      UpdatePhase.verifying => '正在校验安装包',
      UpdatePhase.readyToInstall => '安装包已就绪',
      UpdatePhase.installing => '系统安装界面已打开，下次启动确认版本',
      UpdatePhase.failed => '更新失败',
    };

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes < 0 ? 0 : bytes} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
