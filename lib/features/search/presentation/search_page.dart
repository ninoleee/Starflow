import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/section_panel.dart';
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
  String? _selectedProviderId;
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
    if (enabledProviders.isEmpty) {
      setState(() {
        _results = const [];
        _errorMessage = null;
      });
      return;
    }

    final provider = enabledProviders.firstWhere(
      (item) => item.id == _selectedProviderId,
      orElse: () => enabledProviders.first,
    );

    setState(() {
      _selectedProviderId = provider.id;
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(searchRepositoryProvider)
          .search(_controller.text, provider: provider);

      if (!mounted) {
        return;
      }

      setState(() {
        _results = result;
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
    final selectedProvider = enabledProviders.where(
      (item) => item.id == _selectedProviderId,
    );
    final activeProvider = selectedProvider.isEmpty
        ? (enabledProviders.isEmpty ? null : enabledProviders.first)
        : selectedProvider.first;

    return Scaffold(
      appBar: AppBar(title: const Text('在线搜索')),
      body: AppPageBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SectionPanel(
              title: '搜索服务',
              subtitle: '你可以在设置页替换成自己的聚合服务或站点模板',
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
                  if (enabledProviders.isEmpty)
                    const Text('还没有启用搜索服务，请先去设置页添加。')
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: enabledProviders
                          .map(
                            (provider) => ChoiceChip(
                              label: Text(provider.name),
                              selected: activeProvider?.id == provider.id,
                              onSelected: (_) {
                                setState(() {
                                  _selectedProviderId = provider.id;
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
              subtitle: activeProvider == null
                  ? '启用一个搜索服务后就可以开始搜索'
                  : '当前使用 ${activeProvider.name}，后续可以接下载器、离线缓存或收藏流程',
              child: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _errorMessage != null
                      ? Text('搜索失败：$_errorMessage')
                      : _results.isEmpty
                          ? const Text('输入关键字后开始搜索；这里会展示统一结构的资源结果。')
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
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: () => _showDetailDialog(context, result),
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
              child: Image.network(
                result.posterUrl,
                width: 82,
                height: 118,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: 82,
                    height: 118,
                    color: theme.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.link_rounded),
                  );
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
