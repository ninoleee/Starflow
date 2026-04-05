import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/widgets/app_network_image.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/home/application/home_controller.dart';
import 'package:starflow/features/library/data/nas_media_index_models.dart';
import 'package:starflow/features/library/data/nas_media_indexer.dart';
import 'package:starflow/features/library/presentation/library_collection_page.dart';
import 'package:starflow/features/library/presentation/library_page.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/storage/data/local_storage_cache_repository.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class MetadataIndexManagementPage extends ConsumerStatefulWidget {
  const MetadataIndexManagementPage({
    super.key,
    required this.target,
  });

  final MediaDetailTarget target;

  @override
  ConsumerState<MetadataIndexManagementPage> createState() =>
      _MetadataIndexManagementPageState();
}

class _MetadataIndexManagementPageState
    extends ConsumerState<MetadataIndexManagementPage> {
  late final TextEditingController _queryController;
  late final TextEditingController _yearController;
  late bool _preferSeries;
  late Future<NasMediaIndexRecord?> _recordFuture;

  bool _isSearching = false;
  bool _isApplying = false;
  MetadataMatchResult? _wmdbResult;
  MetadataMatchResult? _tmdbResult;
  ImdbRatingPreview? _imdbPreview;
  String _wmdbMessage = '';
  String _tmdbMessage = '';
  String _imdbMessage = '';

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: widget.target.searchQuery.trim().isNotEmpty
          ? widget.target.searchQuery.trim()
          : widget.target.title.trim(),
    );
    _yearController = TextEditingController(
      text: widget.target.year > 0 ? '${widget.target.year}' : '',
    );
    _preferSeries = widget.target.isSeries;
    _recordFuture = _loadRecord();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<NasMediaIndexRecord?> _loadRecord() {
    return ref.read(nasMediaIndexerProvider).loadRecord(
          sourceId: widget.target.sourceId,
          resourceId: widget.target.itemId,
        );
  }

  Future<void> _runSearch() async {
    final query = _queryController.text.trim();
    final year = int.tryParse(_yearController.text.trim()) ?? 0;
    if (query.isEmpty) {
      _showSnackBar('请先输入要搜索的片名');
      return;
    }

    setState(() {
      _isSearching = true;
      _wmdbResult = null;
      _tmdbResult = null;
      _imdbPreview = null;
      _wmdbMessage = '';
      _tmdbMessage = '';
      _imdbMessage = '';
    });

    final settings = ref.read(appSettingsProvider);

    final Future<(MetadataMatchResult?, String)> wmdbFuture = () async {
      try {
        final result = await ref.read(wmdbMetadataClientProvider).matchTitle(
              query: query,
              year: year,
              preferSeries: _preferSeries,
              actors: widget.target.actors,
            );
        return (result, result == null ? '没有匹配到 WMDB 结果。' : '');
      } catch (error) {
        return (null, '$error');
      }
    }();

    final Future<(MetadataMatchResult?, String)> tmdbFuture = () async {
      final token = settings.tmdbReadAccessToken.trim();
      if (token.isEmpty) {
        return (null, '未配置 TMDB Read Access Token。');
      }
      try {
        final result = await ref.read(tmdbMetadataClientProvider).matchTitle(
              query: query,
              readAccessToken: token,
              year: year,
              preferSeries: _preferSeries,
            );
        return (
          result == null ? null : _tmdbToMetadataMatch(result),
          result == null ? '没有匹配到 TMDB 结果。' : '',
        );
      } catch (error) {
        return (null, '$error');
      }
    }();

    final Future<(ImdbRatingPreview?, String)> imdbFuture = () async {
      try {
        final result = await ref.read(imdbRatingClientProvider).previewMatch(
              query: query,
              year: year,
              preferSeries: _preferSeries,
            );
        return (result, result == null ? '没有匹配到 IMDb 评分。' : '');
      } catch (error) {
        return (null, '$error');
      }
    }();

    final wmdbResolved = await wmdbFuture;
    final tmdbResolved = await tmdbFuture;
    final imdbResolved = await imdbFuture;
    if (!mounted) {
      return;
    }

    setState(() {
      _isSearching = false;
      _wmdbResult = wmdbResolved.$1;
      _wmdbMessage = wmdbResolved.$2;
      _tmdbResult = tmdbResolved.$1;
      _tmdbMessage = tmdbResolved.$2;
      _imdbPreview = imdbResolved.$1;
      _imdbMessage = imdbResolved.$2;
    });
  }

  MetadataMatchResult _tmdbToMetadataMatch(TmdbMetadataMatch match) {
    return MetadataMatchResult(
      provider: MetadataMatchProvider.tmdb,
      title: match.title,
      originalTitle: match.originalTitle,
      posterUrl: match.posterUrl,
      overview: match.overview,
      year: match.year,
      durationLabel: match.durationLabel,
      genres: match.genres,
      directors: match.directors,
      actors: match.actors,
      actorProfiles: match.actorProfiles
          .map(
            (item) => MetadataPersonProfile(
              name: item.name,
              avatarUrl: item.avatarUrl,
            ),
          )
          .toList(growable: false),
      imdbId: match.imdbId,
    );
  }

  Future<void> _applyMetadataMatch(MetadataMatchResult match) async {
    if (_isApplying) {
      return;
    }
    setState(() {
      _isApplying = true;
    });

    try {
      final updatedTarget =
          await ref.read(nasMediaIndexerProvider).applyManualMetadata(
                target: widget.target,
                searchQuery: _queryController.text.trim(),
                metadataMatch: match,
                imdbRatingMatch: _resolvedImdbMatch(match.imdbId),
              );
      if (updatedTarget == null) {
        _showSnackBar('没有找到可写回的索引记录');
        return;
      }
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: updatedTarget,
          );
      _invalidateReaders();
      if (!mounted) {
        return;
      }
      context.pop(updatedTarget);
    } catch (error) {
      _showSnackBar('写入索引失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  Future<void> _applyImdbPreview() async {
    final imdbMatch = _resolvedImdbMatch('');
    if (imdbMatch == null || _isApplying) {
      return;
    }
    setState(() {
      _isApplying = true;
    });

    try {
      final updatedTarget =
          await ref.read(nasMediaIndexerProvider).applyManualMetadata(
                target: widget.target,
                searchQuery: _queryController.text.trim(),
                imdbRatingMatch: imdbMatch,
              );
      if (updatedTarget == null) {
        _showSnackBar('没有找到可写回的索引记录');
        return;
      }
      await ref.read(localStorageCacheRepositoryProvider).saveDetailTarget(
            seedTarget: widget.target,
            resolvedTarget: updatedTarget,
          );
      _invalidateReaders();
      if (!mounted) {
        return;
      }
      context.pop(updatedTarget);
    } catch (error) {
      _showSnackBar('写入评分失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _isApplying = false;
        });
      }
    }
  }

  ImdbRatingMatch? _resolvedImdbMatch(String preferredImdbId) {
    final preview = _imdbPreview;
    if (preview == null || preview.ratingLabel.trim().isEmpty) {
      return null;
    }
    final normalizedPreferredId = preferredImdbId.trim().toLowerCase();
    if (normalizedPreferredId.isNotEmpty &&
        preview.imdbId.trim().toLowerCase() != normalizedPreferredId) {
      return null;
    }
    return ImdbRatingMatch(
      imdbId: preview.imdbId,
      ratingLabel: preview.ratingLabel,
      voteCount: preview.voteCount,
    );
  }

  void _invalidateReaders() {
    ref.invalidate(libraryItemsProvider(LibraryFilter.all));
    ref.invalidate(libraryItemsProvider(LibraryFilter.nas));
    ref.invalidate(libraryCollectionItemsProvider);
    ref.invalidate(homeRecentItemsProvider);
    ref.invalidate(homeCarouselItemsProvider);
    ref.invalidate(homeSectionProvider);
    ref.invalidate(homeSectionsProvider);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppPageBackground(
        contentPadding: appPageContentPadding(context),
        child: Stack(
          children: [
            FutureBuilder<NasMediaIndexRecord?>(
              future: _recordFuture,
              builder: (context, snapshot) {
                return ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    SizedBox(
                      height: MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          12,
                    ),
                    _SectionPanel(
                      title: '索引管理',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.target.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '为当前 WebDAV 资源手动搜索 WMDB / TMDB / IMDb，并把结果写回本地索引。',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _SectionPanel(
                      title: '当前索引',
                      child: snapshot.connectionState == ConnectionState.waiting
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: LinearProgressIndicator(),
                            )
                          : snapshot.hasError
                              ? Text('读取索引失败：${snapshot.error}')
                              : _CurrentIndexCard(record: snapshot.data),
                    ),
                    const SizedBox(height: 16),
                    _SectionPanel(
                      title: '手动搜索',
                      child: Column(
                        children: [
                          TextField(
                            controller: _queryController,
                            textInputAction: TextInputAction.search,
                            decoration: const InputDecoration(
                              labelText: '片名 / 搜索词',
                              hintText: '输入要手动匹配的片名',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _runSearch(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _yearController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: '年份',
                                    hintText: '可选',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: SwitchListTile(
                                  value: _preferSeries,
                                  onChanged: (value) {
                                    setState(() {
                                      _preferSeries = value;
                                    });
                                  },
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('按剧集优先匹配'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FilledButton.icon(
                              onPressed: _isSearching ? null : _runSearch,
                              icon: _isSearching
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.manage_search_rounded),
                              label: Text(_isSearching ? '搜索中...' : '开始搜索'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ProviderResultCard(
                      title: 'WMDB',
                      result: _wmdbResult,
                      message: _wmdbMessage,
                      actionLabel: '应用 WMDB 结果',
                      isApplying: _isApplying,
                      onApply: _wmdbResult == null
                          ? null
                          : () => _applyMetadataMatch(_wmdbResult!),
                    ),
                    const SizedBox(height: 12),
                    _ProviderResultCard(
                      title: 'TMDB',
                      result: _tmdbResult,
                      message: _tmdbMessage,
                      actionLabel: '应用 TMDB 结果',
                      isApplying: _isApplying,
                      onApply: _tmdbResult == null
                          ? null
                          : () => _applyMetadataMatch(_tmdbResult!),
                    ),
                    const SizedBox(height: 12),
                    _ImdbResultCard(
                      preview: _imdbPreview,
                      message: _imdbMessage,
                      isApplying: _isApplying,
                      onApply: _imdbPreview == null ? null : _applyImdbPreview,
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
            OverlayToolbar(
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  const _SectionPanel({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CurrentIndexCard extends StatelessWidget {
  const _CurrentIndexCard({
    required this.record,
  });

  final NasMediaIndexRecord? record;

  @override
  Widget build(BuildContext context) {
    if (record == null) {
      return Text(
        '没有找到当前资源的本地索引记录。可以先回媒体库页执行重建索引，再回来手动匹配。',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );
    }

    final lines = <String>[
      '当前标题：${record!.item.title}',
      '搜索词：${record!.searchQuery.trim().isEmpty ? '无' : record!.searchQuery}',
      '识别标题：${record!.recognizedTitle.trim().isEmpty ? '无' : record!.recognizedTitle}',
      '资源路径：${record!.resourcePath}',
      '命中来源：${_matchFlags(record!)}',
      '上次刮削：${_formatTime(record!.scrapedAt)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(line),
          ),
      ],
    );
  }

  String _matchFlags(NasMediaIndexRecord record) {
    final flags = <String>[
      if (record.sidecarMatched) 'Sidecar',
      if (record.wmdbMatched) 'WMDB',
      if (record.tmdbMatched) 'TMDB',
      if (record.imdbMatched) 'IMDb',
    ];
    return flags.isEmpty ? '无' : flags.join(' / ');
  }
}

class _ProviderResultCard extends StatelessWidget {
  const _ProviderResultCard({
    required this.title,
    required this.result,
    required this.message,
    required this.actionLabel,
    required this.isApplying,
    required this.onApply,
  });

  final String title;
  final MetadataMatchResult? result;
  final String message;
  final String actionLabel;
  final bool isApplying;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: title,
      child: result == null
          ? Text(
              message.trim().isEmpty ? '还没有搜索结果。' : message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MatchPreviewCard(
                  title: result!.title,
                  imageUrl: result!.posterUrl,
                  lines: [
                    '年份：${result!.year > 0 ? result!.year : '未知'}',
                    if (result!.doubanId.trim().isNotEmpty)
                      '豆瓣 ID：${result!.doubanId}',
                    if (result!.imdbId.trim().isNotEmpty)
                      'IMDb ID：${result!.imdbId}',
                    if (result!.ratingLabels.isNotEmpty)
                      '评分：${result!.ratingLabels.join(' · ')}',
                  ],
                  overview: result!.overview,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: isApplying ? null : onApply,
                  icon: isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(actionLabel),
                ),
              ],
            ),
    );
  }
}

class _ImdbResultCard extends StatelessWidget {
  const _ImdbResultCard({
    required this.preview,
    required this.message,
    required this.isApplying,
    required this.onApply,
  });

  final ImdbRatingPreview? preview;
  final String message;
  final bool isApplying;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'IMDb',
      child: preview == null
          ? Text(
              message.trim().isEmpty ? '还没有搜索结果。' : message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _MatchPreviewCard(
                  title: preview!.title,
                  imageUrl: preview!.posterUrl,
                  lines: [
                    '年份：${preview!.year > 0 ? preview!.year : '未知'}',
                    if (preview!.typeLabel.trim().isNotEmpty)
                      '类型：${preview!.typeLabel}',
                    'IMDb ID：${preview!.imdbId}',
                    '评分：${preview!.ratingLabel.trim().isEmpty ? '无' : preview!.ratingLabel}',
                    if (preview!.voteCount > 0) '票数：${preview!.voteCount}',
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: isApplying ? null : onApply,
                  icon: isApplying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.star_rounded),
                  label: const Text('仅写入 IMDb 评分'),
                ),
              ],
            ),
    );
  }
}

class _MatchPreviewCard extends StatelessWidget {
  const _MatchPreviewCard({
    required this.title,
    required this.lines,
    this.imageUrl = '',
    this.overview = '',
  });

  final String title;
  final List<String> lines;
  final String imageUrl;
  final String overview;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AppNetworkImage(
                imageUrl,
                width: 88,
                height: 128,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _PosterPlaceholder(title: title);
                },
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(line),
                  ),
                if (overview.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    overview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final firstLetter =
        title.trim().isEmpty ? '?' : title.trim().substring(0, 1);
    return Container(
      width: 88,
      height: 128,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        firstLetter.toUpperCase(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}
