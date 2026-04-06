import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';

class QuarkFolderPickerPage extends ConsumerStatefulWidget {
  const QuarkFolderPickerPage({
    super.key,
    required this.cookie,
    this.initialFid = '0',
    this.initialPath = '/',
  });

  final String cookie;
  final String initialFid;
  final String initialPath;

  @override
  ConsumerState<QuarkFolderPickerPage> createState() =>
      _QuarkFolderPickerPageState();
}

class _QuarkFolderPickerPageState extends ConsumerState<QuarkFolderPickerPage> {
  late List<QuarkDirectoryEntry> _breadcrumbs;
  bool _isLoading = true;
  String? _errorMessage;
  List<QuarkDirectoryEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _breadcrumbs = [
      QuarkDirectoryEntry(
        fid: widget.initialFid.trim().isEmpty ? '0' : widget.initialFid.trim(),
        name: '根目录',
        path:
            widget.initialPath.trim().isEmpty ? '/' : widget.initialPath.trim(),
      ),
    ];
    _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final current = _breadcrumbs.last;
      final entries = await ref.read(quarkSaveClientProvider).listDirectories(
            cookie: widget.cookie,
            parentFid: current.fid,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = entries;
      });
    } on QuarkSaveException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _selectCurrent() {
    Navigator.of(context).pop(_breadcrumbs.last);
  }

  void _goToEntry(QuarkDirectoryEntry entry) {
    setState(() {
      _breadcrumbs = [..._breadcrumbs, entry];
    });
    _loadCurrent();
  }

  void _goBackTo(int index) {
    setState(() {
      _breadcrumbs = _breadcrumbs.take(index + 1).toList(growable: false);
    });
    _loadCurrent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          ListView(
            padding: overlayToolbarPagePadding(context),
            children: [
              const Text(
                '选择保存文件夹',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _breadcrumbs.length; index++)
                    StarflowChipButton(
                      label: _breadcrumbs[index].path,
                      selected: index == _breadcrumbs.length - 1,
                      onPressed: index == _breadcrumbs.length - 1
                          ? null
                          : () => _goBackTo(index),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_errorMessage != null)
                Text(_errorMessage!)
              else if (_entries.isEmpty)
                const Text('当前目录下没有子文件夹')
              else
                ..._entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: StarflowSelectionTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: entry.name,
                      subtitle: entry.path,
                      onPressed: () => _goToEntry(entry),
                    ),
                  ),
                ),
              const SizedBox(height: kBottomReservedSpacing),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: OverlayToolbar(
              trailing: StarflowButton(
                label: '选择',
                onPressed: _selectCurrent,
                variant: StarflowButtonVariant.ghost,
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
