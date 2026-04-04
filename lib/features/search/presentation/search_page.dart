import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/utils/network_image_headers.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/search/data/mock_search_repository.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

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
  String _selectedTargetId = _SearchTarget.allId;
  String? _errorMessage;

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

    final target = targets.firstWhere(
      (item) => item.id == _selectedTargetId,
      orElse: () => targets.first,
    );

    setState(() {
      _selectedTargetId = target.id;
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final repository = ref.read(searchRepositoryProvider);
      final keyword = _controller.text.trim();
      late final List<SearchResult> result;
      switch (target.kind) {
        case _SearchTargetKind.all:
          final groups = await Future.wait([
            repository.searchLocal(keyword, limit: 80),
            ...enabledProviders.map(
              (provider) => repository.searchOnline(
                keyword,
                provider: provider,
              ),
            ),
          ]);
          result = groups.expand((items) => items).toList(growable: false);
          break;
        case _SearchTargetKind.mediaSource:
          result = await repository.searchLocal(
            keyword,
            sourceId: target.mediaSource!.id,
            limit: 80,
          );
          break;
        case _SearchTargetKind.provider:
          result = await repository.searchOnline(
            keyword,
            provider: target.provider!,
          );
          break;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _results = _sortResults(result);
        _isSearching = false;
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
    final activeTarget = targets.firstWhere(
      (item) => item.id == _selectedTargetId,
      orElse: () => targets.first,
    );

    return Scaffold(
      body: AppPageBackground(
        contentPadding: appPageContentPadding(
          context,
          includeBottomNavigationBar: true,
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SectionPanel(
              title: '搜索',
              subtitle: '可选全部、指定 Emby/WebDAV 来源，或指定在线搜索服务',
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
                  const SizedBox(height: 14),
                  if (targets.length == 1)
                    const Text('还没有启用可搜索的来源，请先去设置页添加媒体源或搜索服务。')
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: targets
                          .map(
                            (target) => ChoiceChip(
                              label: Text(target.label),
                              selected: activeTarget.id == target.id,
                              onSelected: (_) {
                                setState(() {
                                  _selectedTargetId = target.id;
                                });
                                if (_controller.text.trim().isNotEmpty) {
                                  _performSearch();
                                }
                              },
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: '搜索结果',
              subtitle: targets.length == 1
                  ? '启用来源后就可以开始搜索'
                  : '当前范围：${activeTarget.label}',
              child: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _errorMessage != null
                      ? Text('搜索失败：$_errorMessage')
                      : _results.isEmpty
                          ? const Text('输入关键字后开始搜索。')
                          : Column(
                              children: _results
                                  .map(
                                    (item) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _SearchResultCard(result: item),
                                    ),
                                  )
                                  .toList(),
                            ),
            ),
          ],
        ),
      ),
    );
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
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final posterUrl = result.posterUrl.trim();
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () {
        if (result.detailTarget != null) {
          context.pushNamed('detail', extra: result.detailTarget);
          return;
        }
        _showDetailDialog(context, result);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: posterUrl.isEmpty
                  ? _SearchPosterPlaceholder(theme: theme)
                  : Image.network(
                      posterUrl,
                      headers: networkImageHeadersForUrl(posterUrl),
                      width: 82,
                      height: 118,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _SearchPosterPlaceholder(theme: theme);
                      },
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.summary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
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
      ),
    );
  }

  Future<void> _showDetailDialog(BuildContext context, SearchResult result) {
    final detailLines = <String>[
      'Provider: ${result.providerName}',
      'Type: ${result.quality}',
      'Source: ${result.source.isEmpty ? '未知来源' : result.source}',
      'Password: ${result.password.isEmpty ? '无' : result.password}',
      if (result.publishedAt.isNotEmpty) 'Published At: ${result.publishedAt}',
      if (result.seeders > 0) 'Seeders: ${result.seeders}',
      '',
      result.summary,
      '',
      'Resource URL:',
      result.resourceUrl,
    ];

    return showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(result.title),
          content: SelectableText(detailLines.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}

class _SearchPosterPlaceholder extends StatelessWidget {
  const _SearchPosterPlaceholder({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 118,
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
