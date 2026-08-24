part of 'media_source_editor_page.dart';

class _EmbySourceConnectionForm extends StatelessWidget {
  const _EmbySourceConnectionForm({
    required this.endpointController,
    required this.usernameController,
    required this.passwordController,
    required this.tokenController,
    required this.advancedExpanded,
    required this.onAdvancedChanged,
  });

  final TextEditingController endpointController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController tokenController;
  final bool advancedExpanded;
  final ValueChanged<bool> onAdvancedChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...buildSettingsTileGroup([
          SettingsTextInputField(
            controller: endpointController,
            labelText: 'Endpoint',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            hintText: 'https://emby.example.com',
          ),
          _SourceCredentialsForm(
            usernameController: usernameController,
            passwordController: passwordController,
            usernameLabel: 'Emby 用户名',
            passwordLabel: 'Emby 密码',
          ),
        ], spacing: 12),
        const SizedBox(height: 8),
        SettingsExpandableSection(
          title: '高级（可选）',
          subtitle: '手动粘贴 Access Token / API Key',
          expanded: advancedExpanded,
          onChanged: onAdvancedChanged,
          children: [
            SettingsTextInputField(
              controller: tokenController,
              labelText: 'Access Token / API Key',
              minLines: 1,
              maxLines: 4,
              alignLabelWithHint: true,
              summaryBuilder: _secretSummary,
            ),
          ],
        ),
      ],
    );
  }
}

class _WebDavSourceConnectionForm extends StatelessWidget {
  const _WebDavSourceConnectionForm({
    required this.endpointController,
    required this.usernameController,
    required this.passwordController,
    required this.selectedPath,
    required this.onPickPath,
  });

  final TextEditingController endpointController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String selectedPath;
  final VoidCallback? onPickPath;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...buildSettingsTileGroup([
          SettingsTextInputField(
            controller: endpointController,
            labelText: 'WebDAV Endpoint',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            hintText: 'https://nas.example.com/dav',
          ),
          SettingsSelectionTile(
            title: '当前路径',
            value: selectedPath.trim().isEmpty ? '根目录' : selectedPath,
            onPressed: onPickPath,
          ),
          _SourceCredentialsForm(
            usernameController: usernameController,
            passwordController: passwordController,
            usernameLabel: '用户名',
            passwordLabel: 'WebDAV 密码',
          ),
        ], spacing: 12),
        const SizedBox(height: 12),
        Text(
          '可直接填写 WebDAV 地址、用户名和密码。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _QuarkSourceConnectionForm extends StatelessWidget {
  const _QuarkSourceConnectionForm({
    required this.cookieConfigured,
    required this.selectedPath,
    required this.onPickFolder,
  });

  final bool cookieConfigured;
  final String selectedPath;
  final VoidCallback? onPickFolder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSelectionTile(
          title: '当前目录',
          value: selectedPath.trim().isEmpty ? '未选择' : selectedPath,
          subtitle: cookieConfigured
              ? '复用「夸克云盘」里的全局 Cookie'
              : '请先在「夸克云盘」中填写夸克 Cookie',
          onPressed: onPickFolder,
        ),
        const SizedBox(height: 12),
        Text(
          cookieConfigured
              ? '夸克媒体源会复用全局 Cookie，只需选择目录并测试连接。'
              : '请先到「夸克云盘」填写夸克 Cookie，再回来选择目录。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SourceCredentialsForm extends StatelessWidget {
  const _SourceCredentialsForm({
    required this.usernameController,
    required this.passwordController,
    required this.usernameLabel,
    required this.passwordLabel,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final String usernameLabel;
  final String passwordLabel;

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Column(
        children: buildSettingsTileGroup([
          SettingsTextInputField(
            controller: usernameController,
            labelText: usernameLabel,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username],
          ),
          SettingsTextInputField(
            controller: passwordController,
            labelText: passwordLabel,
            obscureText: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            summaryBuilder: _secretSummary,
          ),
        ], spacing: 12),
      ),
    );
  }
}

String _secretSummary(String value) => value.isEmpty ? '未填写' : '已填写';
