import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/utils/network_image_headers.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';

class MetadataMatchSettingsPage extends ConsumerWidget {
  const MetadataMatchSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return Scaffold(
      body: AppPageBackground(
        contentPadding: appPageContentPadding(context),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            SectionPanel(
              title: '匹配策略',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '优先顺序',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<MetadataMatchProvider>(
                    showSelectedIcon: false,
                    segments: [
                      for (final provider in MetadataMatchProvider.values)
                        ButtonSegment<MetadataMatchProvider>(
                          value: provider,
                          label: Text('${provider.label} 优先'),
                        ),
                    ],
                    selected: {settings.metadataMatchPriority},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) {
                        return;
                      }
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setMetadataMatchPriority(selection.first);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: 'TMDB',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 TMDB 自动补全影片信息'),
                    value: settings.tmdbMetadataMatchEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setTmdbMetadataMatchEnabled(value);
                    },
                  ),
                  const SizedBox(height: 6),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('TMDB Read Access Token'),
                    trailing: Text(
                      settings.tmdbReadAccessToken.trim().isEmpty
                          ? '未配置'
                          : '已配置',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton(
                        onPressed: () => _openTmdbTokenEditor(
                          context,
                          ref,
                          settings.tmdbReadAccessToken,
                        ),
                        child: Text(
                          settings.tmdbReadAccessToken.trim().isEmpty
                              ? '填写 Token'
                              : '编辑 Token',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: () => _openTmdbTestDialog(context, ref),
                        child: const Text('测试 TMDB'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: 'WMDB',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 WMDB 自动补全影片信息'),
                    value: settings.wmdbMetadataMatchEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setWmdbMetadataMatchEnabled(value);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () => _openWmdbTestDialog(context, ref),
                      child: const Text('测试 WMDB'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SectionPanel(
              title: '评分',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用 IMDb 自动补评分'),
                    value: settings.imdbRatingMatchEnabled,
                    onChanged: (value) {
                      ref
                          .read(settingsControllerProvider.notifier)
                          .setImdbRatingMatchEnabled(value);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () => _openImdbTestDialog(context, ref),
                      child: const Text('测试 IMDb'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTmdbTokenEditor(
    BuildContext context,
    WidgetRef ref,
    String currentToken,
  ) async {
    final controller = TextEditingController(text: currentToken);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('TMDB Read Access Token'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: '粘贴 TMDB 的 Read Access Token',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                controller.clear();
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('清空'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
    if (saved == true) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setTmdbReadAccessToken(controller.text);
    }
    controller.dispose();
  }

  Future<void> _openTmdbTestDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController(text: '这个杀手不太冷');
    var preferSeries = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var loading = false;
        String message = '';
        TmdbMetadataMatch? result;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> runTest() async {
              final token =
                  ref.read(appSettingsProvider).tmdbReadAccessToken.trim();
              final query = controller.text.trim();
              if (token.isEmpty) {
                setState(() {
                  message = '请先填写 TMDB Read Access Token。';
                  result = null;
                });
                return;
              }
              if (query.isEmpty) {
                setState(() {
                  message = '请先输入要测试的片名。';
                  result = null;
                });
                return;
              }

              setState(() {
                loading = true;
                message = '';
                result = null;
              });

              try {
                final match =
                    await ref.read(tmdbMetadataClientProvider).matchTitle(
                          query: query,
                          readAccessToken: token,
                          preferSeries: preferSeries,
                        );
                setState(() {
                  loading = false;
                  result = match;
                  message = match == null ? '没有匹配到结果。' : '匹配成功。';
                });
              } catch (error) {
                setState(() {
                  loading = false;
                  result = null;
                  message = '$error';
                });
              }
            }

            return AlertDialog(
              title: const Text('测试 TMDB'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        decoration: const InputDecoration(
                          labelText: '测试片名',
                          hintText: '例如：这个杀手不太冷',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => runTest(),
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: preferSeries,
                        onChanged: (value) {
                          setState(() {
                            preferSeries = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('优先按剧集匹配'),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 6),
                        const LinearProgressIndicator(),
                      ],
                      if (message.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          style: TextStyle(
                            color: result == null
                                ? const Color(0xFFE79A9A)
                                : const Color(0xFF9FD6B3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (result != null) ...[
                        const SizedBox(height: 12),
                        _TestResultCard(
                          title: result!.title,
                          imageUrl: result!.posterUrl,
                          lines: [
                            '年份：${result!.year > 0 ? result!.year : '未知'}',
                            '海报：${result!.posterUrl.trim().isEmpty ? '无' : '有'}',
                            'IMDb ID：${result!.imdbId.trim().isEmpty ? '无' : result!.imdbId}',
                          ],
                          overview: result!.overview,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: loading ? null : runTest,
                  child: const Text('开始测试'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _openWmdbTestDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController(text: '英雄本色');
    final actorController = TextEditingController(text: '周润发');
    final yearController = TextEditingController(text: '1986');
    final doubanIdController = TextEditingController(text: '');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var loading = false;
        String message = '';
        MetadataMatchResult? result;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> runTest() async {
              final title = titleController.text.trim();
              final actor = actorController.text.trim();
              final year = int.tryParse(yearController.text.trim()) ?? 0;
              final doubanId = doubanIdController.text.trim();
              if (doubanId.isEmpty && title.isEmpty && actor.isEmpty) {
                setState(() {
                  message = '请至少填写 Douban ID、片名或主演。';
                  result = null;
                });
                return;
              }

              setState(() {
                loading = true;
                message = '';
                result = null;
              });

              try {
                final client = ref.read(wmdbMetadataClientProvider);
                final match = doubanId.isNotEmpty
                    ? await client.matchByDoubanId(doubanId: doubanId)
                    : await client.matchTitle(
                        query: title,
                        year: year,
                        actors: actor.isEmpty ? const [] : [actor],
                      );
                setState(() {
                  loading = false;
                  result = match;
                  message = match == null ? '没有匹配到结果。' : '匹配成功。';
                });
              } catch (error) {
                setState(() {
                  loading = false;
                  result = null;
                  message = '$error';
                });
              }
            }

            return AlertDialog(
              title: const Text('测试 WMDB'),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: doubanIdController,
                        decoration: const InputDecoration(
                          labelText: 'Douban ID',
                          hintText: '填了就走直查接口，例如：1297574',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: titleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '片名',
                          hintText: '不填 Douban ID 时会用它搜索',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: actorController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '主演',
                          hintText: '可选，用于提高搜索命中率',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: yearController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '年份',
                          hintText: '可选，例如：1986',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                      ],
                      if (message.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          style: TextStyle(
                            color: result == null
                                ? const Color(0xFFE79A9A)
                                : const Color(0xFF9FD6B3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (result != null) ...[
                        const SizedBox(height: 12),
                        _TestResultCard(
                          title: result!.title,
                          imageUrl: result!.posterUrl,
                          lines: [
                            '来源：${result!.provider.label}',
                            '年份：${result!.year > 0 ? result!.year : '未知'}',
                            '海报：${result!.posterUrl.trim().isEmpty ? '无' : '有'}',
                            '豆瓣 ID：${result!.doubanId.trim().isEmpty ? '无' : result!.doubanId}',
                            'IMDb ID：${result!.imdbId.trim().isEmpty ? '无' : result!.imdbId}',
                            if (result!.ratingLabels.isNotEmpty)
                              '评分：${result!.ratingLabels.join(' · ')}',
                          ],
                          overview: result!.overview,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: loading ? null : runTest,
                  child: const Text('开始测试'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    actorController.dispose();
    yearController.dispose();
    doubanIdController.dispose();
  }

  Future<void> _openImdbTestDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final queryController = TextEditingController(text: 'The Godfather');
    final yearController = TextEditingController(text: '1972');
    var preferSeries = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var loading = false;
        String message = '';
        ImdbRatingPreview? result;

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> runTest() async {
              final query = queryController.text.trim();
              final year = int.tryParse(yearController.text.trim()) ?? 0;
              if (query.isEmpty) {
                setState(() {
                  message = '请先输入要测试的片名。';
                  result = null;
                });
                return;
              }

              setState(() {
                loading = true;
                message = '';
                result = null;
              });

              try {
                final match =
                    await ref.read(imdbRatingClientProvider).previewMatch(
                          query: query,
                          year: year,
                          preferSeries: preferSeries,
                        );
                setState(() {
                  loading = false;
                  result = match;
                  message = match == null ? '没有匹配到结果。' : '匹配成功。';
                });
              } catch (error) {
                setState(() {
                  loading = false;
                  result = null;
                  message = '$error';
                });
              }
            }

            return AlertDialog(
              title: const Text('测试 IMDb'),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: queryController,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '测试片名',
                          hintText: '例如：The Godfather',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: yearController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: '年份',
                          hintText: '可选，例如：1972',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => runTest(),
                      ),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: preferSeries,
                        onChanged: (value) {
                          setState(() {
                            preferSeries = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('优先按剧集匹配'),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 6),
                        const LinearProgressIndicator(),
                      ],
                      if (message.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          message,
                          style: TextStyle(
                            color: result == null
                                ? const Color(0xFFE79A9A)
                                : const Color(0xFF9FD6B3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      if (result != null) ...[
                        const SizedBox(height: 12),
                        _TestResultCard(
                          title: result!.title,
                          imageUrl: result!.posterUrl,
                          lines: [
                            '年份：${result!.year > 0 ? result!.year : '未知'}',
                            '类型：${result!.typeLabel.trim().isEmpty ? '未知' : result!.typeLabel}',
                            '海报：${result!.posterUrl.trim().isEmpty ? '无' : '有'}',
                            'IMDb ID：${result!.imdbId}',
                            '评分：${result!.ratingLabel.trim().isEmpty ? '无' : result!.ratingLabel}',
                            if (result!.voteCount > 0)
                              '票数：${result!.voteCount}',
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('关闭'),
                ),
                FilledButton(
                  onPressed: loading ? null : runTest,
                  child: const Text('开始测试'),
                ),
              ],
            );
          },
        );
      },
    );

    queryController.dispose();
    yearController.dispose();
  }
}

class _TestResultCard extends StatelessWidget {
  const _TestResultCard({
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl.trim().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                headers: networkImageHeadersForUrl(imageUrl),
                width: 86,
                height: 124,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _TestPosterPlaceholder(title: title);
                },
                loadingBuilder: (context, child, progress) {
                  if (progress == null) {
                    return child;
                  }
                  return const SizedBox(
                    width: 86,
                    height: 124,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  );
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
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final line in lines) Text(line),
                if (overview.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    overview,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
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

class _TestPosterPlaceholder extends StatelessWidget {
  const _TestPosterPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final trimmed = title.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    return Container(
      width: 86,
      height: 124,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        letter.toUpperCase(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
