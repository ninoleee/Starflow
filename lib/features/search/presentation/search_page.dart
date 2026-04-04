import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/utils/network_image_headers.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/data/smart_strm_webhook_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:url_launcher/url_launcher.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _controller;
  List<SearchResult> _results = const [];
  bool _isSearching = false;
  Set<String> _selectedTargetIds = const {_SearchTarget.allId};
  String? _errorMessage;
  int _activeSearchRequestId = 0;
  int _totalSearchTaskCount = 0;
  int _completedSearchTaskCount = 0;
  int _filteredResultCount = 0;
  final Set<String> _savingResultIds = <String>{};

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if ((widget.initialQuery ?? '').trim().isNotEmpty) {
        _performSearch();
      }
    });
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery &&
        (widget.initialQuery ?? '').trim().isNotEmpty) {
      _controller.text = widget.initialQuery!;
      _performSearch();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final settings = ref.read(appSettingsProvider);
    final enabledProviders =
        settings.searchProviders.where((item) => item.enabled).toList();
    final enabledSources =
        settings.mediaSources.where((item) => item.enabled).toList();
    final targets = _buildTargets(
      sources: enabledSources,
      providers: enabledProviders,
    );
    if (targets.length == 1) {
      setState(() {
        _results = const [];
        _errorMessage = null;
      });
      return;
    }

    final selectedTargets = _resolveSelectedTargets(targets);

    setState(() {
      _selectedTargetIds = selectedTargets.map((item) => item.id).toSet();
      _isSearching = true;
      _results = const [];
      _errorMessage = null;
      _totalSearchTaskCount = 0;
      _completedSearchTaskCount = 0;
      _filteredResultCount = 0;
    });

    final repository = ref.read(searchRepositoryProvider);
    final keyword = _controller.text.trim();
    final requestId = ++_activeSearchRequestId;
    final operations = _buildSearchOperations(
      repository: repository,
      keyword: keyword,
      targets: selectedTargets,
      enabledSources: enabledSources,
      enabledProviders: enabledProviders,
    );

    if (operations.isEmpty) {
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      setState(() {
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _totalSearchTaskCount = operations.length;
      _completedSearchTaskCount = 0;
    });

    final aggregated = <SearchResult>[];
    final seenResourceKeys = <String>{};
    final errors = <String>[];
    var completed = 0;
    var filteredCount = 0;

    for (final operation in operations) {
      unawaited(
        _runSearchOperation(
          requestId: requestId,
          operation: operation,
          aggregated: aggregated,
          errors: errors,
          totalCount: operations.length,
          seenResourceKeys: seenResourceKeys,
          onCompleted: () => completed += 1,
          getCompleted: () => completed,
          onFiltered: (count) => filteredCount += count,
          getFiltered: () => filteredCount,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final enabledProviders =
        settings.searchProviders.where((item) => item.enabled).toList();
    final enabledSources =
        settings.mediaSources.where((item) => item.enabled).toList();
    final targets = _buildTargets(
      sources: enabledSources,
      providers: enabledProviders,
    );

    return Scaffold(
      body: AppPageBackground(
        contentPadding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top,
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kAppPageHorizontalPadding,
                0,
                kAppPageHorizontalPadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _performSearch(),
                    decoration: InputDecoration(
                      hintText: '搜索电影、剧集或番剧资源',
                      suffixIcon: IconButton(
                        onPressed: _performSearch,
                        icon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (targets.length == 1)
                    const Text('还没有启用可搜索的来源，请先去设置页添加媒体源或搜索服务。')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: targets
                          .map(
                            (target) => FilterChip(
                              label: Text(target.label),
                              selected: _selectedTargetIds.contains(target.id),
                              onSelected: (_) {
                                _toggleTargetSelection(target, targets);
                                if (_controller.text.trim().isNotEmpty) {
                                  _performSearch();
                                }
                              },
                            ),
                          )
                          .toList(),
                    ),
                  const SizedBox(height: 12),
                  if (_isSearching) ...[
                    LinearProgressIndicator(
                      value: _totalSearchTaskCount > 0
                          ? _completedSearchTaskCount / _totalSearchTaskCount
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _results.isEmpty
                          ? '正在搜索...'
                          : '正在继续搜索 $_completedSearchTaskCount/$_totalSearchTaskCount',
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_controller.text.trim().isNotEmpty &&
                      (_results.isNotEmpty || _filteredResultCount > 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '结果 ${_results.length} 条 · 过滤 $_filteredResultCount 条',
                      ),
                    ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('搜索失败：$_errorMessage'),
                    )
                  else if (_results.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _controller.text.trim().isEmpty
                            ? '输入关键字后开始搜索。'
                            : _filteredResultCount > 0
                                ? '没有可用结果，已过滤 $_filteredResultCount 条结果。'
                                : '没有找到结果。',
                      ),
                    ),
                ],
              ),
            ),
            if (_results.isNotEmpty)
              ..._results.map(
                (item) => _SearchResultCard(
                  result: item,
                  isSaving: _savingResultIds.contains(item.id),
                  showSaveAction: _canSaveResultToQuark(
                    result: item,
                    settings: settings,
                  ),
                  onSave: () => _saveResultToQuark(
                    result: item,
                    settings: settings,
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  List<_SearchOperation> _buildSearchOperations({
    required SearchRepository repository,
    required String keyword,
    required List<_SearchTarget> targets,
    required List<MediaSourceConfig> enabledSources,
    required List<SearchProviderConfig> enabledProviders,
  }) {
    final operations = <_SearchOperation>[];
    for (final target in targets) {
      switch (target.kind) {
        case _SearchTargetKind.all:
          operations.addAll([
            ...enabledSources.map(
              (source) => _SearchOperation(
                label: source.name,
                run: () => repository.searchLocal(
                  keyword,
                  sourceId: source.id,
                  limit: 80,
                ),
              ),
            ),
            ...enabledProviders.map(
              (provider) => _SearchOperation(
                label: provider.name,
                run: () => repository.searchOnline(
                  keyword,
                  provider: provider,
                ),
              ),
            ),
          ]);
          break;
        case _SearchTargetKind.mediaSource:
          operations.add(
            _SearchOperation(
              label: target.mediaSource!.name,
              run: () => repository.searchLocal(
                keyword,
                sourceId: target.mediaSource!.id,
                limit: 80,
              ),
            ),
          );
          break;
        case _SearchTargetKind.provider:
          operations.add(
            _SearchOperation(
              label: target.provider!.name,
              run: () => repository.searchOnline(
                keyword,
                provider: target.provider!,
              ),
            ),
          );
          break;
      }
    }
    return operations;
  }

  Future<void> _runSearchOperation({
    required int requestId,
    required _SearchOperation operation,
    required List<SearchResult> aggregated,
    required List<String> errors,
    required int totalCount,
    required Set<String> seenResourceKeys,
    required VoidCallback onCompleted,
    required int Function() getCompleted,
    required ValueChanged<int> onFiltered,
    required int Function() getFiltered,
  }) async {
    try {
      final result = await operation.run();
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      var duplicateCount = 0;
      for (final item in result.items) {
        final key = normalizeSearchResourceUrl(item.resourceUrl).isEmpty
            ? item.id
            : normalizeSearchResourceUrl(item.resourceUrl);
        if (!seenResourceKeys.add(key)) {
          duplicateCount += 1;
          continue;
        }
        aggregated.add(item);
      }
      onFiltered(result.filteredCount + duplicateCount);
    } catch (error) {
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      errors.add('${operation.label}: $error');
    } finally {
      if (mounted && requestId == _activeSearchRequestId) {
        onCompleted();
        final completed = getCompleted();
        final hasFinished = completed >= totalCount;
        setState(() {
          _completedSearchTaskCount = completed;
          _filteredResultCount = getFiltered();
          _results = _sortResults(aggregated);
          _isSearching = !hasFinished;
          _errorMessage = aggregated.isEmpty && errors.isNotEmpty && hasFinished
              ? errors.join('\n')
              : null;
        });
      }
    }
  }

  List<_SearchTarget> _buildTargets({
    required List<MediaSourceConfig> sources,
    required List<SearchProviderConfig> providers,
  }) {
    return [
      const _SearchTarget.all(),
      ...sources.map(_SearchTarget.mediaSource),
      ...providers.map(_SearchTarget.provider),
    ];
  }

  List<_SearchTarget> _resolveSelectedTargets(List<_SearchTarget> targets) {
    if (targets.isEmpty) {
      return const [];
    }

    if (_selectedTargetIds.contains(_SearchTarget.allId)) {
      return [targets.first];
    }

    final selected = targets
        .where((item) => _selectedTargetIds.contains(item.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      return [targets.first];
    }
    return selected;
  }

  void _toggleTargetSelection(
    _SearchTarget target,
    List<_SearchTarget> targets,
  ) {
    final next = {..._selectedTargetIds};
    if (target.id == _SearchTarget.allId) {
      setState(() {
        _selectedTargetIds = {_SearchTarget.allId};
      });
      return;
    }

    next.remove(_SearchTarget.allId);
    if (next.contains(target.id)) {
      next.remove(target.id);
    } else {
      next.add(target.id);
    }

    setState(() {
      _selectedTargetIds = next.isEmpty ? {_SearchTarget.allId} : next;
    });
  }

  List<SearchResult> _sortResults(List<SearchResult> items) {
    final sorted = [...items];
    sorted.sort((left, right) {
      final localBoost = (right.detailTarget != null ? 1 : 0) -
          (left.detailTarget != null ? 1 : 0);
      if (localBoost != 0) {
        return localBoost;
      }
      return left.title.compareTo(right.title);
    });
    return sorted;
  }

  bool _canSaveResultToQuark({
    required SearchResult result,
    required AppSettings settings,
  }) {
    if (result.detailTarget != null) {
      return false;
    }
    final cloudType = detectSearchCloudTypeFromUrl(result.resourceUrl);
    if (cloudType != SearchCloudType.quark) {
      return false;
    }
    return settings.networkStorage.quarkCookie.trim().isNotEmpty;
  }

  Future<void> _saveResultToQuark({
    required SearchResult result,
    required AppSettings settings,
  }) async {
    final storage = settings.networkStorage;
    final cookie = storage.quarkCookie.trim();
    if (cookie.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在搜索设置里填写夸克 Cookie')),
      );
      return;
    }

    setState(() {
      _savingResultIds.add(result.id);
    });

    try {
      final response = await ref.read(quarkSaveClientProvider).saveShareLink(
            shareUrl: result.resourceUrl,
            cookie: cookie,
            toPdirFid: storage.quarkSaveFolderId,
          );
      var triggeredTask = false;
      if (storage.smartStrmWebhookUrl.trim().isNotEmpty &&
          storage.smartStrmTaskName.trim().isNotEmpty) {
        await ref.read(smartStrmWebhookClientProvider).triggerTask(
              webhookUrl: storage.smartStrmWebhookUrl,
              taskName: storage.smartStrmTaskName,
              storagePath: storage.quarkSaveFolderPath == '/'
                  ? ''
                  : storage.quarkSaveFolderPath,
            );
        triggeredTask = true;
      }
      if (!mounted) {
        return;
      }
      final message = response.taskId.isEmpty
          ? '已提交到夸克，保存 ${response.savedCount} 个文件'
          : '已提交到夸克，任务 ${response.taskId}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            triggeredTask ? '$message，已触发 STRM 任务' : message,
          ),
        ),
      );
    } on QuarkSaveException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } on SmartStrmWebhookException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('夸克保存成功，但 STRM 触发失败：${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _savingResultIds.remove(result.id);
        });
      }
    }
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.isSaving,
    required this.showSaveAction,
    required this.onSave,
  });

  final SearchResult result;
  final bool isSaving;
  final bool showSaveAction;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posterUrl = result.posterUrl.trim();
    final resourceUri = _parseLaunchUri(result.resourceUrl);
    return InkWell(
      onTap: () {
        if (result.detailTarget != null) {
          context.pushNamed('detail', extra: result.detailTarget);
          return;
        }
        if (resourceUri != null) {
          _openResourceUrl(context, resourceUri);
          return;
        }
        _showDetailDialog(context, result);
      },
      onLongPress: () => _showDetailDialog(context, result),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: posterUrl.isEmpty
                      ? _SearchPosterPlaceholder(theme: theme)
                      : Image.network(
                          posterUrl,
                          headers: networkImageHeadersForUrl(posterUrl),
                          width: 72,
                          height: 102,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _SearchPosterPlaceholder(theme: theme);
                          },
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              result.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (showSaveAction)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: '保存到夸克',
                                  onPressed: isSaving ? null : onSave,
                                  icon: isSaving
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.bookmark_add_rounded,
                                          size: 18,
                                        ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        result.summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MetaChip(label: result.providerName),
                          _MetaChip(label: result.quality),
                          _MetaChip(label: result.sizeLabel),
                          if (result.seeders > 0)
                            _MetaChip(label: '${result.seeders} seeders'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(
              height: 1,
              thickness: 0.5,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDetailDialog(BuildContext context, SearchResult result) {
    final resourceUri = _parseLaunchUri(result.resourceUrl);
    final detailLines = <String>[
      'Provider: ${result.providerName}',
      'Type: ${result.quality}',
      'Source: ${result.source.isEmpty ? '未知来源' : result.source}',
      'Password: ${result.password.isEmpty ? '无' : result.password}',
      if (result.publishedAt.isNotEmpty) 'Published At: ${result.publishedAt}',
      if (result.seeders > 0) 'Seeders: ${result.seeders}',
      if (result.summary.trim().isNotEmpty) '',
      if (result.summary.trim().isNotEmpty) result.summary,
    ];

    return showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text(
            result.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(detailLines.join('\n')),
                if (result.resourceUrl.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Resource URL:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: resourceUri == null
                        ? null
                        : () => _openResourceUrl(context, resourceUri),
                    child: Text(
                      result.resourceUrl,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: resourceUri == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.primary,
                        decoration: resourceUri == null
                            ? TextDecoration.none
                            : TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (resourceUri != null)
              TextButton(
                onPressed: () => _openResourceUrl(context, resourceUri),
                child: const Text('打开链接'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Uri? _parseLaunchUri(String rawUrl) {
    final trimmed = sanitizeSearchResourceUrl(rawUrl);
    if (trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return null;
    }
    return uri;
  }

  Future<void> _openResourceUrl(BuildContext context, Uri uri) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || launched) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开链接')),
    );
  }
}

class _SearchPosterPlaceholder extends StatelessWidget {
  const _SearchPosterPlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 102,
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Icon(Icons.link_rounded),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .secondaryContainer
            .withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

enum _SearchTargetKind {
  all,
  mediaSource,
  provider,
}

class _SearchTarget {
  const _SearchTarget.all()
      : id = allId,
        label = '全部',
        kind = _SearchTargetKind.all,
        mediaSource = null,
        provider = null;

  _SearchTarget.mediaSource(this.mediaSource)
      : id = 'source:${mediaSource!.id}',
        label = mediaSource.name,
        kind = _SearchTargetKind.mediaSource,
        provider = null;

  _SearchTarget.provider(this.provider)
      : id = 'provider:${provider!.id}',
        label = provider.name,
        kind = _SearchTargetKind.provider,
        mediaSource = null;

  static const allId = 'all';

  final String id;
  final String label;
  final _SearchTargetKind kind;
  final MediaSourceConfig? mediaSource;
  final SearchProviderConfig? provider;
}

class _SearchOperation {
  const _SearchOperation({
    required this.label,
    required this.run,
  });

  final String label;
  final Future<SearchFetchResult> Function() run;
}
