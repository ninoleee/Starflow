import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/playback/data/online_subtitle_repository.dart';
import 'package:starflow/features/playback/data/subtitle_search_host_bridge.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

class SubtitleSearchPage extends ConsumerStatefulWidget {
  const SubtitleSearchPage({
    super.key,
    required this.request,
  });

  final SubtitleSearchRequest request;

  @override
  ConsumerState<SubtitleSearchPage> createState() => _SubtitleSearchPageState();
}

class _SubtitleSearchPageState extends ConsumerState<SubtitleSearchPage> {
  late final TextEditingController _controller;
  final TvFocusMemoryController _focusMemoryController =
      TvFocusMemoryController();
  List<SubtitleSearchResult> _results = const [];
  bool _isSearching = false;
  String? _errorMessage;
  String? _busyResultId;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.request.query);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_performSearch());
    });
  }

  @override
  void dispose() {
    _focusMemoryController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<bool> _handleClose() async {
    if (!widget.request.standalone) {
      return true;
    }
    final handled = await SubtitleSearchHostBridge.cancel();
    return !handled;
  }

  Future<void> _performSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
        _isSearching = false;
        _errorMessage = '请先输入要搜索的字幕关键词';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final results = await ref.read(onlineSubtitleRepositoryProvider).search(
            query,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _isSearching = false;
        _errorMessage = results.isEmpty ? '没有找到可用字幕结果' : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _results = const [];
        _isSearching = false;
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _handleDownload(SubtitleSearchResult result) async {
    if (_busyResultId != null) {
      return;
    }
    if (widget.request.applyMode ==
            SubtitleSearchApplyMode.downloadAndApply &&
        !result.canAutoLoad) {
      _showMessage('当前先支持自动加载 ZIP / SRT / ASS / SSA / VTT 字幕');
      return;
    }

    setState(() {
      _busyResultId = result.id;
    });
    try {
      final downloadResult = await ref
          .read(onlineSubtitleRepositoryProvider)
          .download(result);
      final selection = SubtitleSearchSelection(
        cachedPath: downloadResult.cachedPath,
        displayName: downloadResult.displayName,
        subtitleFilePath: downloadResult.subtitleFilePath,
      );
      if (widget.request.applyMode ==
              SubtitleSearchApplyMode.downloadAndApply &&
          !selection.canApply) {
        _showMessage('字幕已缓存，但当前结果暂不能直接挂载播放');
        return;
      }

      if (!mounted) {
        return;
      }
      if (widget.request.standalone) {
        final handled =
            await SubtitleSearchHostBridge.finishSelection(selection);
        if (!handled && mounted) {
          Navigator.of(context).pop(selection);
        }
        return;
      }
      Navigator.of(context).pop(selection);
    } catch (error) {
      _showMessage('$error');
    } finally {
      if (mounted) {
        setState(() {
          _busyResultId = null;
        });
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
    final request = widget.request;
    final applyMode = request.applyMode;
    final title = request.title.trim().isEmpty ? '在线字幕' : request.title.trim();

    return WillPopScope(
      onWillPop: _handleClose,
      child: Scaffold(
        appBar: AppBar(
          title: Text(applyMode == SubtitleSearchApplyMode.downloadOnly
              ? '下载字幕'
              : '搜索并加载字幕'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _handleClose() && mounted) {
                Navigator.of(context).maybePop();
              }
            },
          ),
        ),
        body: AppPageBackground(
          child: SafeArea(
            child: TvFocusMemoryScope(
              controller: _focusMemoryController,
              scopeId: 'subtitle-search',
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: _SearchHeader(
                      controller: _controller,
                      title: title,
                      applyMode: applyMode,
                      onSearch: _performSearch,
                      isBusy: _isSearching || _busyResultId != null,
                    ),
                  ),
                  Expanded(
                    child: _buildBody(applyMode),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(SubtitleSearchApplyMode applyMode) {
    if (_isSearching && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null && _results.isEmpty) {
      return _SubtitleSearchEmptyState(message: _errorMessage!);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SubtitleResultTile(
          result: result,
          applyMode: applyMode,
          isBusy: _busyResultId == result.id,
          onPressed: () => _handleDownload(result),
        );
      },
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemCount: _results.length,
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.controller,
    required this.title,
    required this.applyMode,
    required this.onSearch,
    required this.isBusy,
  });

  final TextEditingController controller;
  final String title;
  final SubtitleSearchApplyMode applyMode;
  final Future<void> Function() onSearch;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            applyMode == SubtitleSearchApplyMode.downloadOnly
                ? '在应用内搜索字幕并下载到本地缓存。'
                : '在应用内搜索字幕，下载后直接挂到当前播放器。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => unawaited(onSearch()),
            decoration: InputDecoration(
              labelText: '字幕关键词',
              hintText: '片名、剧名、S01E01、年份等',
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search_rounded),
                onPressed: isBusy ? null : () => unawaited(onSearch()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubtitleResultTile extends StatelessWidget {
  const _SubtitleResultTile({
    required this.result,
    required this.applyMode,
    required this.isBusy,
    required this.onPressed,
  });

  final SubtitleSearchResult result;
  final SubtitleSearchApplyMode applyMode;
  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = result.canDownload &&
        (applyMode == SubtitleSearchApplyMode.downloadOnly ||
            result.canAutoLoad);
    final buttonLabel = applyMode == SubtitleSearchApplyMode.downloadOnly
        ? '下载到缓存'
        : enabled
            ? '下载并加载'
            : '暂不支持';

    return TvFocusableAction(
      onPressed: enabled && !isBusy ? onPressed : null,
      borderRadius: BorderRadius.circular(24),
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (result.detailLine.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            result.detailLine,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _SubtitleKindBadge(
                    label: result.packageKind.label,
                    enabled: enabled,
                  ),
                ],
              ),
              if (result.summaryLine.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  result.summaryLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (result.packageName.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  result.packageName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary.withValues(alpha: 0.88),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: StarflowButton(
                  label: isBusy ? '处理中...' : buttonLabel,
                  onPressed: enabled && !isBusy ? onPressed : null,
                  variant: enabled
                      ? StarflowButtonVariant.secondary
                      : StarflowButtonVariant.ghost,
                  compact: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleKindBadge extends StatelessWidget {
  const _SubtitleKindBadge({
    required this.label,
    required this.enabled,
  });

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: enabled
            ? theme.colorScheme.primary.withValues(alpha: 0.16)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: enabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SubtitleSearchEmptyState extends StatelessWidget {
  const _SubtitleSearchEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
