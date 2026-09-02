import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/network/network_proxy_config.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/settings_auto_save_coordinator.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_text_input_field.dart';

class NetworkProxySettingsPage extends ConsumerStatefulWidget {
  const NetworkProxySettingsPage({super.key});

  @override
  ConsumerState<NetworkProxySettingsPage> createState() =>
      _NetworkProxySettingsPageState();
}

class _NetworkProxySettingsPageState
    extends ConsumerState<NetworkProxySettingsPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late bool _enabled;
  late bool _bypassLocalAddresses;
  bool _testing = false;
  final SettingsAutoSaveCoordinator _autoSave = SettingsAutoSaveCoordinator();

  List<TextEditingController> get _textControllers => <TextEditingController>[
        _hostController,
        _portController,
        _usernameController,
        _passwordController,
      ];

  @override
  void initState() {
    super.initState();
    final config = ref.read(appSettingsProvider).networkProxy;
    _hostController = TextEditingController(text: config.host);
    _portController = TextEditingController(text: config.port.toString());
    _usernameController = TextEditingController(text: config.username);
    _passwordController = TextEditingController(text: config.password);
    _enabled = config.enabled;
    _bypassLocalAddresses = config.bypassLocalAddresses;
    for (final controller in _textControllers) {
      controller.addListener(_scheduleAutoSave);
    }
    _autoSave.markCurrentAsSaved(_fingerprint(config));
  }

  @override
  void dispose() {
    for (final controller in _textControllers) {
      controller.removeListener(_scheduleAutoSave);
      controller.dispose();
    }
    _autoSave.dispose();
    super.dispose();
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleAutoSave();
  }

  NetworkProxyConfig _buildDraft() {
    return NetworkProxyConfig(
      enabled: _enabled,
      host: _hostController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 0,
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      bypassLocalAddresses: _bypassLocalAddresses,
    );
  }

  String _fingerprint(NetworkProxyConfig config) => jsonEncode(config.toJson());

  void _scheduleAutoSave() {
    if (!mounted || kIsWeb) {
      return;
    }
    final draft = _buildDraft();
    _autoSave.schedule(
      fingerprint: _fingerprint(draft),
      save: () =>
          ref.read(settingsControllerProvider.notifier).saveNetworkProxy(draft),
    );
  }

  void _flushAutoSave() {
    if (!mounted || kIsWeb) {
      return;
    }
    final draft = _buildDraft();
    _autoSave.flush(
      fingerprint: _fingerprint(draft),
      save: () =>
          ref.read(settingsControllerProvider.notifier).saveNetworkProxy(draft),
    );
  }

  void _closePage() {
    _flushAutoSave();
    Navigator.of(context).pop();
  }

  void _setEnabled(bool value) {
    if (value && !_buildDraft().isValid) {
      _showMessage('请先填写有效的代理服务器和端口');
      return;
    }
    setState(() => _enabled = value);
  }

  Future<void> _testConnection() async {
    final draft = _buildDraft();
    if (!draft.isActive) {
      _showMessage('请先启用并填写有效的代理配置');
      return;
    }
    _flushAutoSave();
    setState(() => _testing = true);
    try {
      await _autoSave.drain();
      final response = await ref
          .read(starflowHttpClientProvider)
          .get(Uri.parse('https://api.themoviedb.org/3/configuration'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 ||
          response.statusCode >= 500 ||
          response.statusCode == 407) {
        throw StateError('HTTP ${response.statusCode}');
      }
      _showMessage('代理连接成功');
    } catch (error) {
      _showMessage('代理连接失败：$error');
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = !kIsWeb;
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsToggleTile(
          title: '启用 HTTP 代理',
          subtitle: '用于应用接口、元数据、搜索、在线字幕、图片和内置 MPV 的 HTTP / HTTPS 请求。',
          value: _enabled && controlsEnabled,
          autofocus: true,
          focusId: 'settings:network-proxy:enabled',
          onChanged: controlsEnabled ? _setEnabled : null,
        ),
        const SettingsSectionTitle(label: '服务器'),
        SettingsTextInputField(
          controller: _hostController,
          labelText: '代理服务器',
          hintText: '例如 192.168.1.2',
          textInputAction: TextInputAction.next,
          autocorrect: false,
          focusId: 'settings:network-proxy:host',
        ),
        const SizedBox(height: 12),
        SettingsTextInputField(
          controller: _portController,
          labelText: '端口',
          hintText: '7890',
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          focusId: 'settings:network-proxy:port',
        ),
        const SettingsSectionTitle(label: '认证（可选）'),
        SettingsTextInputField(
          controller: _usernameController,
          labelText: '用户名',
          textInputAction: TextInputAction.next,
          autocorrect: false,
          focusId: 'settings:network-proxy:username',
        ),
        const SizedBox(height: 12),
        SettingsTextInputField(
          controller: _passwordController,
          labelText: '密码',
          obscureText: true,
          autocorrect: false,
          focusId: 'settings:network-proxy:password',
        ),
        const SettingsSectionTitle(label: '路由'),
        SettingsToggleTile(
          title: '局域网地址直连',
          subtitle:
              'localhost、私有 IP 和 .local 地址不经过代理，避免 NAS、Emby 与 TV 手机传输被转发到外网。',
          value: _bypassLocalAddresses,
          onChanged: controlsEnabled
              ? (value) => setState(() => _bypassLocalAddresses = value)
              : null,
          focusId: 'settings:network-proxy:bypass-local',
        ),
        const SizedBox(height: 18),
        SettingsActionButton(
          label: _testing ? '正在测试…' : '测试代理连接',
          icon: Icons.network_check_rounded,
          onPressed: controlsEnabled && !_testing ? _testConnection : null,
          loading: _testing,
          compact: false,
          focusId: 'settings:network-proxy:test',
        ),
      ],
    );

    return PopScope<void>(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _flushAutoSave();
        }
      },
      child: SettingsPageScaffold(
        onBack: _closePage,
        children: [
          Text('网络代理', style: Theme.of(context).textTheme.headlineSmall),
          if (kIsWeb) ...[
            const SizedBox(height: 18),
            const SettingsInfoCard(
              title: 'Web 端由浏览器管理代理',
              description:
                  '浏览器不允许网页单独指定 HTTP 代理。Web 开发环境继续使用 STARFLOW_WEB_PROXY_BASE 和仓库内的启动脚本。',
            ),
          ],
          const SizedBox(height: 8),
          IgnorePointer(
            ignoring: !controlsEnabled,
            child: Opacity(
              opacity: controlsEnabled ? 1 : 0.55,
              child: form,
            ),
          ),
          const SizedBox(height: 18),
          const SettingsInfoCard(
            title: '代理类型',
            description:
                '支持标准 HTTP 代理及 HTTPS CONNECT，可选 Basic 认证。当前不支持 SOCKS 或 PAC 地址；外部系统播放器使用自身的网络设置。',
          ),
        ],
      ),
    );
  }
}
