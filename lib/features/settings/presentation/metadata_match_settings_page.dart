import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/utils/network_image_headers.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/metadata/data/imdb_rating_client.dart';
import 'package:starflow/features/metadata/data/tmdb_metadata_client.dart';
import 'package:starflow/features/metadata/data/wmdb_metadata_client.dart';
import 'package:starflow/features/metadata/domain/metadata_match_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/presentation/widgets/settings_page_scaffold.dart';

class MetadataMatchSettingsPage extends ConsumerWidget {
  const MetadataMatchSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final isTelevision = ref.watch(isTelevisionProvider).valueOrNull ?? false;

    return SettingsPageScaffold(
      children: [
        SectionPanel(
          title: '匹配策略',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MetadataToggleTile(
                title: '详情页自动匹配本地资源',
                subtitle: '开启后，进入详情页会自动尝试匹配本地资源；关闭后仅手动匹配',
                value: settings.detailAutoLibraryMatchEnabled,
                onChanged: (value) {
                  ref
                      .read(settingsControllerProvider.notifier)
                      .setDetailAutoLibraryMatchEnabled(value);
                },
              ),
              const SizedBox(height: 10),
              Text(
                '优先顺序',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              if (isTelevision)
                StarflowSelectionTile(
                  title: '优先顺序',
                  value: '${settings.metadataMatchPriority.label} 优先',
                  onPressed: () => _openPriorityPicker(
                    context,
                    ref,
                    settings.metadataMatchPriority,
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final provider in MetadataMatchProvider.values)
                      StarflowChipButton(
                        label: '${provider.label} 优先',
                        selected: provider == settings.metadataMatchPriority,
                        onPressed: () {
                          ref
                              .read(settingsControllerProvider.notifier)
                              .setMetadataMatchPriority(provider);
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SectionPanel(
          title: 'TMDB',
          child: Column(
            children: [
              _MetadataToggleTile(
                title: '启用 TMDB 自动补全影片信息',
                value: settings.tmdbMetadataMatchEnabled,
                onChanged: (value) {
                  ref
                      .read(settingsControllerProvider.notifier)
                      .setTmdbMetadataMatchEnabled(value);
                },
              ),
              const SizedBox(height: 6),
              StarflowSelectionTile(
                title: 'TMDB Read Access Token',
                value:
                    settings.tmdbReadAccessToken.trim().isEmpty ? '未配置' : '已配置',
                onPressed: () => _openTmdbTokenEditor(
                  context,
                  ref,
                  settings.tmdbReadAccessToken,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SettingsActionButton(
                    label: settings.tmdbReadAccessToken.trim().isEmpty
                        ? '填写 Token'
                        : '编辑 Token',
                    icon: Icons.key_rounded,
                    onPressed: () => _openTmdbTokenEditor(
                      context,
                      ref,
                      settings.tmdbReadAccessToken,
                    ),
                  ),
                  SettingsActionButton(
                    label: '测试 TMDB',
                    icon: Icons.science_rounded,
                    onPressed: () => _openTmdbTestDialog(context, ref),
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
              _MetadataToggleTile(
                title: '启用 WMDB 自动补全影片信息',
                value: settings.wmdbMetadataMatchEnabled,
                onChanged: (value) {
                  ref
                      .read(settingsControllerProvider.notifier)
                      .setWmdbMetadataMatchEnabled(value);
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SettingsActionButton(
                  label: '测试 WMDB',
                  icon: Icons.science_rounded,
                  onPressed: () => _openWmdbTestDialog(context, ref),
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
              _MetadataToggleTile(
                title: '启用 IMDb 自动补评分',
                value: settings.imdbRatingMatchEnabled,
                onChanged: (value) {
                  ref
                      .read(settingsControllerProvider.notifier)
                      .setImdbRatingMatchEnabled(value);
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: SettingsActionButton(
                  label: '测试 IMDb',
                  icon: Icons.science_rounded,
                  onPressed: () => _openImdbTestDialog(context, ref),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openPriorityPicker(
    BuildContext context,
    WidgetRef ref,
    MetadataMatchProvider current,
  ) async {
    final selected = await showDialog<MetadataMatchProvider>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('选择优先顺序'),
          children: [
            for (final provider in MetadataMatchProvider.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(provider),
                child: Text(
                  provider == current
                      ? '${provider.label} 优先  当前'
                      : '${provider.label} 优先',
                ),
              ),
          ],
        );
      },
    );
    if (selected == null) {
      return;
    }
    await ref
        .read(settingsControllerProvider.notifier)
        .setMetadataMatchPriority(selected);
  }

  Future<void> _openTmdbTokenEditor(
    BuildContext context,
    WidgetRef ref,
    String currentToken,
  ) async {
    final controller = TextEditingController(text: currentToken);
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final inputFocusNode = FocusNode(debugLabel: 'tmdb-token-dialog-field');
    final cancelFocusNode = FocusNode(debugLabel: 'tmdb-token-dialog-cancel');
    final clearFocusNode = FocusNode(debugLabel: 'tmdb-token-dialog-clear');
    final saveFocusNode = FocusNode(debugLabel: 'tmdb-token-dialog-save');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final dialog = AlertDialog(
          title: const Text('TMDB Read Access Token'),
          content: wrapTelevisionDialogFieldTraversal(
            enabled: isTelevision,
            child: TextField(
              controller: controller,
              focusNode: inputFocusNode,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '粘贴 TMDB 的 Read Access Token',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            StarflowButton(
              label: '取消',
              focusNode: cancelFocusNode,
              onPressed: () => Navigator.of(dialogContext).pop(false),
              variant: StarflowButtonVariant.ghost,
              compact: true,
            ),
            StarflowButton(
              label: '清空',
              focusNode: clearFocusNode,
              onPressed: () {
                controller.clear();
                Navigator.of(dialogContext).pop(true);
              },
              variant: StarflowButtonVariant.secondary,
              compact: true,
            ),
            StarflowButton(
              label: '保存',
              focusNode: saveFocusNode,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              compact: true,
            ),
          ],
        );
        return wrapTelevisionDialogBackHandling(
          enabled: isTelevision,
          dialogContext: dialogContext,
          inputFocusNodes: [inputFocusNode],
          contentFocusNodes: [inputFocusNode],
          actionFocusNodes: [saveFocusNode, clearFocusNode, cancelFocusNode],
          child: dialog,
        );
      },
    );
    controller.dispose();
    inputFocusNode.dispose();
    cancelFocusNode.dispose();
    clearFocusNode.dispose();
    saveFocusNode.dispose();
    if (saved == true) {
      await ref
          .read(settingsControllerProvider.notifier)
          .setTmdbReadAccessToken(controller.text);
    }
  }

  Future<void> _openTmdbTestDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController(text: '这个杀手不太冷');
    var preferSeries = false;
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final queryFocusNode = FocusNode(debugLabel: 'tmdb-test-query');
    final preferSeriesFocusNode = FocusNode(debugLabel: 'tmdb-test-series');
    final closeFocusNode = FocusNode(debugLabel: 'tmdb-test-close');
    final startFocusNode = FocusNode(debugLabel: 'tmdb-test-start');
    try {
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

              final dialog = FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: AlertDialog(
                  title: const Text('测试 TMDB'),
                  content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: controller,
                                focusNode: queryFocusNode,
                                autofocus: true,
                                textInputAction: TextInputAction.search,
                                decoration: const InputDecoration(
                                  labelText: '测试片名',
                                  hintText: '例如：这个杀手不太冷',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => runTest(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: StarflowCheckboxTile(
                              focusNode: preferSeriesFocusNode,
                              title: '优先按剧集匹配',
                              value: preferSeries,
                              onChanged: (value) {
                                setState(() {
                                  preferSeries = value;
                                });
                              },
                            ),
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
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: SettingsActionButton(
                        label: '关闭',
                        icon: Icons.close_rounded,
                        focusNode: closeFocusNode,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        variant: StarflowButtonVariant.ghost,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: SettingsActionButton(
                        label: '开始测试',
                        icon: Icons.play_arrow_rounded,
                        focusNode: startFocusNode,
                        onPressed: loading ? null : runTest,
                      ),
                    ),
                  ],
                ),
              );
              return wrapTelevisionDialogBackHandling(
                enabled: isTelevision,
                dialogContext: dialogContext,
                inputFocusNodes: [queryFocusNode],
                contentFocusNodes: [queryFocusNode, preferSeriesFocusNode],
                actionFocusNodes: [startFocusNode, closeFocusNode],
                child: dialog,
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
      queryFocusNode.dispose();
      preferSeriesFocusNode.dispose();
      closeFocusNode.dispose();
      startFocusNode.dispose();
    }
  }

  Future<void> _openWmdbTestDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final titleController = TextEditingController(text: '英雄本色');
    final actorController = TextEditingController(text: '周润发');
    final yearController = TextEditingController(text: '1986');
    final doubanIdController = TextEditingController(text: '');
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final doubanFocusNode = FocusNode(debugLabel: 'wmdb-test-douban');
    final titleFocusNode = FocusNode(debugLabel: 'wmdb-test-title');
    final actorFocusNode = FocusNode(debugLabel: 'wmdb-test-actor');
    final yearFocusNode = FocusNode(debugLabel: 'wmdb-test-year');
    final closeFocusNode = FocusNode(debugLabel: 'wmdb-test-close');
    final startFocusNode = FocusNode(debugLabel: 'wmdb-test-start');
    try {
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

              final dialog = FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: AlertDialog(
                  title: const Text('测试 WMDB'),
                  content: SizedBox(
                    width: 440,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: doubanIdController,
                                focusNode: doubanFocusNode,
                                autofocus: true,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Douban ID',
                                  hintText: '填了就走直查接口，例如：1297574',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: titleController,
                                focusNode: titleFocusNode,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '片名',
                                  hintText: '不填 Douban ID 时会用它搜索',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(3),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: actorController,
                                focusNode: actorFocusNode,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '主演',
                                  hintText: '可选，用于提高搜索命中率',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(4),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: yearController,
                                focusNode: yearFocusNode,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: '年份',
                                  hintText: '可选，例如：1986',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => runTest(),
                              ),
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
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
                      child: SettingsActionButton(
                        label: '关闭',
                        icon: Icons.close_rounded,
                        focusNode: closeFocusNode,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        variant: StarflowButtonVariant.ghost,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(6),
                      child: SettingsActionButton(
                        label: '开始测试',
                        icon: Icons.play_arrow_rounded,
                        focusNode: startFocusNode,
                        onPressed: loading ? null : runTest,
                      ),
                    ),
                  ],
                ),
              );
              return wrapTelevisionDialogBackHandling(
                enabled: isTelevision,
                dialogContext: dialogContext,
                inputFocusNodes: [
                  doubanFocusNode,
                  titleFocusNode,
                  actorFocusNode,
                  yearFocusNode,
                ],
                contentFocusNodes: [
                  doubanFocusNode,
                  titleFocusNode,
                  actorFocusNode,
                  yearFocusNode,
                ],
                actionFocusNodes: [startFocusNode, closeFocusNode],
                child: dialog,
              );
            },
          );
        },
      );
    } finally {
      titleController.dispose();
      actorController.dispose();
      yearController.dispose();
      doubanIdController.dispose();
      doubanFocusNode.dispose();
      titleFocusNode.dispose();
      actorFocusNode.dispose();
      yearFocusNode.dispose();
      closeFocusNode.dispose();
      startFocusNode.dispose();
    }
  }

  Future<void> _openImdbTestDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final queryController = TextEditingController(text: 'The Godfather');
    final yearController = TextEditingController(text: '1972');
    var preferSeries = false;
    final isTelevision = ref.read(isTelevisionProvider).valueOrNull ?? false;
    final queryFocusNode = FocusNode(debugLabel: 'imdb-test-query');
    final yearFocusNode = FocusNode(debugLabel: 'imdb-test-year');
    final preferSeriesFocusNode = FocusNode(debugLabel: 'imdb-test-series');
    final closeFocusNode = FocusNode(debugLabel: 'imdb-test-close');
    final startFocusNode = FocusNode(debugLabel: 'imdb-test-start');
    try {
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

              final dialog = FocusTraversalGroup(
                policy: OrderedTraversalPolicy(),
                child: AlertDialog(
                  title: const Text('测试 IMDb'),
                  content: SizedBox(
                    width: 420,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: queryController,
                                focusNode: queryFocusNode,
                                autofocus: true,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: '测试片名',
                                  hintText: '例如：The Godfather',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: wrapTelevisionDialogFieldTraversal(
                              enabled: isTelevision,
                              child: TextField(
                                controller: yearController,
                                focusNode: yearFocusNode,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: '年份',
                                  hintText: '可选，例如：1972',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => runTest(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(3),
                            child: StarflowCheckboxTile(
                              focusNode: preferSeriesFocusNode,
                              title: '优先按剧集匹配',
                              value: preferSeries,
                              onChanged: (value) {
                                setState(() {
                                  preferSeries = value;
                                });
                              },
                            ),
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
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(4),
                      child: SettingsActionButton(
                        label: '关闭',
                        icon: Icons.close_rounded,
                        focusNode: closeFocusNode,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        variant: StarflowButtonVariant.ghost,
                      ),
                    ),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(5),
                      child: SettingsActionButton(
                        label: '开始测试',
                        icon: Icons.play_arrow_rounded,
                        focusNode: startFocusNode,
                        onPressed: loading ? null : runTest,
                      ),
                    ),
                  ],
                ),
              );
              return wrapTelevisionDialogBackHandling(
                enabled: isTelevision,
                dialogContext: dialogContext,
                inputFocusNodes: [queryFocusNode, yearFocusNode],
                contentFocusNodes: [
                  queryFocusNode,
                  yearFocusNode,
                  preferSeriesFocusNode,
                ],
                actionFocusNodes: [startFocusNode, closeFocusNode],
                child: dialog,
              );
            },
          );
        },
      );
    } finally {
      queryController.dispose();
      yearController.dispose();
      queryFocusNode.dispose();
      yearFocusNode.dispose();
      preferSeriesFocusNode.dispose();
      closeFocusNode.dispose();
      startFocusNode.dispose();
    }
  }
}

class _MetadataToggleTile extends StatelessWidget {
  const _MetadataToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle = '',
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return StarflowToggleTile(
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
    );
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
