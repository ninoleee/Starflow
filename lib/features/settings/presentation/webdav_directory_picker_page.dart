import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/library/data/webdav_nas_client.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class WebDavDirectoryPickerPage extends ConsumerStatefulWidget {
  const WebDavDirectoryPickerPage({
    super.key,
    required this.source,
    this.initialPath = '',
  });

  final MediaSourceConfig source;
  final String initialPath;

  @override
  ConsumerState<WebDavDirectoryPickerPage> createState() =>
      _WebDavDirectoryPickerPageState();
}

class _WebDavDirectoryPickerPageState
    extends ConsumerState<WebDavDirectoryPickerPage> {
  late String _currentPath;
  late String _rootPath;
  bool _skipAutoSaveOnPop = false;

  @override
  void initState() {
    super.initState();
    _rootPath = widget.source.endpoint.trim();
    final preferredInitialPath = widget.initialPath.trim();
    final sourceLibraryPath = widget.source.libraryPath.trim();
    _currentPath = preferredInitialPath.isNotEmpty
        ? preferredInitialPath
        : sourceLibraryPath.isNotEmpty
            ? sourceLibraryPath
            : _rootPath;
  }

  Future<List<MediaCollection>> _loadFolders() {
    return ref.read(webDavNasClientProvider).fetchCollections(
          widget.source,
          directoryId: _currentPath,
        );
  }

  String _pathLabel(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return raw;
    }
    final path = uri.path.isEmpty ? '/' : uri.path;
    return '${uri.host}$path';
  }

  String? _parentPath(String raw) {
    final uri = Uri.tryParse(raw);
    final rootUri = Uri.tryParse(_rootPath);
    if (uri == null) {
      return null;
    }
    if (rootUri != null &&
        _normalizeDirectoryUri(uri) == _normalizeDirectoryUri(rootUri)) {
      return null;
    }
    final segments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty) {
      return null;
    }
    final parentSegments = segments.take(segments.length - 1).toList();
    final parentPath =
        parentSegments.isEmpty ? '/' : '/${parentSegments.join('/')}/';
    final parent =
        uri.replace(path: parentPath, query: null, fragment: null).toString();
    if (rootUri == null) {
      return parent;
    }
    final normalizedParent = _normalizeDirectoryUri(Uri.parse(parent));
    final normalizedRoot = _normalizeDirectoryUri(rootUri);
    if (!normalizedParent.path.startsWith(normalizedRoot.path)) {
      return null;
    }
    return parent;
  }

  Uri _normalizeDirectoryUri(Uri uri) {
    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: normalizedPath, query: null, fragment: null);
  }

  @override
  Widget build(BuildContext context) {
    final parentPath = _parentPath(_currentPath);
    return PopScope<String>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _skipAutoSaveOnPop) {
          return;
        }
        _skipAutoSaveOnPop = true;
        Navigator.of(context).pop(_currentPath);
      },
      child: SettingsPageScaffold(
        onBack: () {
          _skipAutoSaveOnPop = true;
          Navigator.of(context).pop(_currentPath);
        },
        trailing: SettingsToolbarButton(
          label: '选这里',
          icon: Icons.check_rounded,
          onPressed: () {
            _skipAutoSaveOnPop = true;
            Navigator.of(context).pop(_currentPath);
          },
        ),
        children: [
          const SettingsSectionTitle(label: '当前路径'),
          SelectableText(
            _pathLabel(_currentPath),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (parentPath != null) ...[
            const SizedBox(height: 16),
            SettingsActionButton(
              label: '返回上一级目录',
              icon: Icons.arrow_upward_rounded,
              onPressed: () {
                setState(() {
                  _currentPath = parentPath;
                });
              },
            ),
          ],
          const SettingsSectionTitle(label: '子文件夹'),
          FutureBuilder<List<MediaCollection>>(
            future: _loadFolders(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('读取路径失败：${snapshot.error}'),
                );
              }
              final folders = snapshot.data ?? const <MediaCollection>[];
              if (folders.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('当前路径下没有子文件夹，可以直接选择这里。'),
                );
              }
              return Column(
                children: [
                  for (final folder in folders)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SettingsSelectionTile(
                        title: folder.title,
                        subtitle: folder.id,
                        value: '进入',
                        leading: const Icon(Icons.folder_open_rounded),
                        onPressed: () {
                          setState(() {
                            _currentPath = folder.id;
                          });
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
