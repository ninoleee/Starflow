import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:starflow/app/shell_layout.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/app_page_background.dart';
import 'package:starflow/core/widgets/no_animation_page_route.dart';
import 'package:starflow/core/widgets/overlay_toolbar.dart';
import 'package:starflow/core/widgets/section_panel.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/domain/douban_models.dart';
import 'package:starflow/features/library/data/mock_media_repository.dart';
import 'package:starflow/features/library/domain/media_models.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/presentation/douban_account_editor_page.dart';
import 'package:starflow/features/home/application/home_settings_slices.dart';
import 'package:starflow/features/home/application/home_metadata_auto_refresh.dart';

final homeEditorCollectionsProvider = FutureProvider<List<MediaCollection>>((
  ref,
) {
  ref.watch(homeMediaSourcesProvider);
  return ref.read(mediaRepositoryProvider).fetchCollections();
});

const _kCustomDoubanListPresetValue = '__custom__';

bool _homeEditorIsHeroModule(HomeModuleConfig module) {
  return module.type == HomeModuleType.hero ||
      module.id == HomeModuleConfig.heroModuleId;
}

HomeModuleConfig? _homeEditorHeroModule(List<HomeModuleConfig> modules) {
  for (final module in modules) {
    if (_homeEditorIsHeroModule(module)) {
      return module;
    }
  }
  return null;
}

List<HomeModuleConfig> _homeEditorSortableModules(
  List<HomeModuleConfig> modules,
) {
  return modules
      .where((module) => !_homeEditorIsHeroModule(module))
      .toList(growable: false);
}

class _HomeModuleCard extends StatelessWidget {
  const _HomeModuleCard({
    super.key,
    required this.module,
    required this.leading,
    required this.onToggle,
    this.toggleFocusNode,
    this.onEdit,
    this.onRemove,
  });

  final HomeModuleConfig module;
  final Widget leading;
  final VoidCallback onToggle;
  final FocusNode? toggleFocusNode;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isHero = _homeEditorIsHeroModule(module);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(module.title),
                  if (isHero) ...[
                    const SizedBox(height: 2),
                    Text(
                      '开启后固定显示在首页最上方',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else if (module.supportsDisplayStyle) ...[
                    const SizedBox(height: 2),
                    Text(
                      module.displayStyle.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onEdit != null) ...[
              StarflowIconButton(
                icon: Icons.edit_outlined,
                tooltip: '编辑',
                variant: StarflowButtonVariant.secondary,
                onPressed: onEdit,
              ),
              const SizedBox(width: 8),
            ],
            if (onRemove != null) ...[
              StarflowIconButton(
                icon: Icons.close_rounded,
                tooltip: '删除',
                variant: StarflowButtonVariant.danger,
                onPressed: onRemove,
              ),
              const SizedBox(width: 8),
            ],
            StarflowButton(
              label: module.enabled ? '开启' : '关闭',
              icon: module.enabled
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_outlined,
              iconColor: module.enabled
                  ? null
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              onPressed: onToggle,
              focusNode: toggleFocusNode,
              focusId: 'home-editor:${module.id}:toggle',
              variant: module.enabled
                  ? StarflowButtonVariant.primary
                  : StarflowButtonVariant.secondary,
              compact: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// 二级选择底部弹层：四周留白 + 列表过长时可滚动。
class _HomeEditorSecondarySheetBody extends StatelessWidget {
  const _HomeEditorSecondarySheetBody({
    required this.title,
    required this.tiles,
  });

  final String title;
  final List<Widget> tiles;

  static const _edgePadding = 20.0;

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.sizeOf(context).height * 0.72;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(_edgePadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: ListView(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                children: tiles,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _defaultDoubanListPresets = <_DoubanListPreset>[
  _DoubanListPreset(
    title: '豆瓣热门电影',
    url: 'https://m.douban.com/subject_collection/movie_hot_gaia',
  ),
  _DoubanListPreset(
    title: '热播新剧',
    url: 'https://m.douban.com/subject_collection/tv_hot',
  ),
  _DoubanListPreset(
    title: '热播综艺',
    url: 'https://m.douban.com/subject_collection/show_hot',
  ),
  _DoubanListPreset(
    title: '热播动漫',
    url: 'https://m.douban.com/subject_collection/tv_animation',
  ),
  _DoubanListPreset(
    title: '影院热映',
    url: 'https://m.douban.com/subject_collection/movie_showing',
  ),
  _DoubanListPreset(
    title: '实时热门电影',
    url: 'https://m.douban.com/subject_collection/movie_real_time_hotest',
  ),
  _DoubanListPreset(
    title: '实时热门电视',
    url: 'https://m.douban.com/subject_collection/tv_real_time_hotest',
  ),
  _DoubanListPreset(
    title: '豆瓣 Top 250',
    url: 'https://m.douban.com/subject_collection/movie_top250',
  ),
  _DoubanListPreset(
    title: '一周电影口碑榜',
    url: 'https://m.douban.com/subject_collection/movie_weekly_best',
  ),
  _DoubanListPreset(
    title: '华语口碑剧集榜',
    url: 'https://m.douban.com/subject_collection/tv_chinese_best_weekly',
  ),
  _DoubanListPreset(
    title: '全球口碑剧集榜',
    url: 'https://m.douban.com/subject_collection/tv_global_best_weekly',
  ),
  _DoubanListPreset(
    title: '国内综艺口碑榜',
    url: 'https://m.douban.com/subject_collection/show_chinese_best_weekly',
  ),
  _DoubanListPreset(
    title: '全球综艺口碑榜',
    url: 'https://m.douban.com/subject_collection/show_global_best_weekly',
  ),
  _DoubanListPreset(
    title: '第97届奥斯卡',
    url: 'https://m.douban.com/subject_collection/EC7I7ZDRA?type=rank',
  ),
  _DoubanListPreset(
    title: 'IMDB MOVIE TOP 250',
    url: 'https://m.douban.com/doulist/1518184',
  ),
  _DoubanListPreset(
    title: 'IMDB TV TOP 250',
    url: 'https://m.douban.com/doulist/41573512',
  ),
];

class HomeEditorPage extends ConsumerStatefulWidget {
  const HomeEditorPage({super.key});

  @override
  ConsumerState<HomeEditorPage> createState() => _HomeEditorPageState();
}

class _HomeEditorPageState extends ConsumerState<HomeEditorPage> {
  final Map<String, FocusNode> _moduleToggleFocusNodes = <String, FocusNode>{};
  final Map<String, FocusNode> _sourceFocusNodes = <String, FocusNode>{};
  List<String> _observedModuleIds = const <String>[];
  List<String> _observedSourceIds = const <String>[];
  FocusNode? _preferredFocusNode;
  bool _focusRecoveryScheduled = false;
  bool _focusNodePruneScheduled = false;
  Set<String> _pendingModuleFocusNodeIds = const <String>{};
  bool _sourceFocusNodePruneScheduled = false;
  Set<String> _pendingSourceFocusNodeIds = const <String>{};
  FocusNode? _forcedRecoveryFocusNode;
  ({String moduleId, bool moveUp, FocusNode focusNode})? _focusedMoveAction;

  FocusNode _focusNodeForModule(String moduleId) {
    return _moduleToggleFocusNodes.putIfAbsent(
      moduleId,
      () => FocusNode(debugLabel: 'home-editor-toggle:$moduleId'),
    );
  }

  FocusNode _focusNodeForSource(String sourceId) {
    return _sourceFocusNodes.putIfAbsent(
      sourceId,
      () => FocusNode(debugLabel: 'home-editor-source:$sourceId'),
    );
  }

  void _syncEditorFocus({
    required bool isTelevision,
    required List<HomeModuleConfig> modules,
    required HomeModuleConfig? heroModule,
    required List<HomeModuleConfig> sortableModules,
    required List<String> sourceIds,
  }) {
    if (!isTelevision) {
      return;
    }
    final moduleIds =
        modules.map((module) => module.id).toList(growable: false);
    _scheduleModuleFocusNodePrune(moduleIds.toSet());
    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusedMoveAction = _focusedMoveAction;
    if (focusedMoveAction != null &&
        identical(primaryFocus, focusedMoveAction.focusNode)) {
      final focusedModuleIndex = sortableModules.indexWhere(
        (module) => module.id == focusedMoveAction.moduleId,
      );
      if (focusedModuleIndex >= 0 &&
          ((focusedMoveAction.moveUp && focusedModuleIndex == 0) ||
              (!focusedMoveAction.moveUp &&
                  focusedModuleIndex == sortableModules.length - 1))) {
        _forcedRecoveryFocusNode =
            _focusNodeForModule(focusedMoveAction.moduleId);
      }
    } else {
      _focusedMoveAction = null;
    }
    final requiresForcedRecovery = _forcedRecoveryFocusNode != null;
    _preferredFocusNode = heroModule != null
        ? _focusNodeForModule(heroModule.id)
        : sortableModules.isNotEmpty
            ? _focusNodeForModule(sortableModules.first.id)
            : _focusNodeForSource('builtin');
    final sourcesChanged = !listEquals(sourceIds, _observedSourceIds);
    _observedSourceIds = sourceIds;
    _scheduleSourceFocusNodePrune(sourceIds.toSet());
    if (listEquals(moduleIds, _observedModuleIds) &&
        !sourcesChanged &&
        !requiresForcedRecovery &&
        FocusManager.instance.primaryFocus != null) {
      return;
    }
    _observedModuleIds = moduleIds;
    _scheduleEditorFocusRecovery();
  }

  void _scheduleSourceFocusNodePrune(Set<String> validSourceIds) {
    _pendingSourceFocusNodeIds = <String>{
      'builtin',
      'douban',
      ...validSourceIds,
    };
    if (_sourceFocusNodePruneScheduled) {
      return;
    }
    _sourceFocusNodePruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sourceFocusNodePruneScheduled = false;
      if (!mounted) {
        return;
      }
      final retainedIds = _pendingSourceFocusNodeIds;
      final obsoleteIds = _sourceFocusNodes.keys
          .where((sourceId) => !retainedIds.contains(sourceId))
          .toList(growable: false);
      for (final sourceId in obsoleteIds) {
        _sourceFocusNodes.remove(sourceId)?.dispose();
      }
    });
  }

  void _scheduleModuleFocusNodePrune(Set<String> validModuleIds) {
    _pendingModuleFocusNodeIds = Set<String>.from(validModuleIds);
    if (_focusNodePruneScheduled) {
      return;
    }
    _focusNodePruneScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodePruneScheduled = false;
      if (!mounted) {
        return;
      }
      final retainedIds = _pendingModuleFocusNodeIds;
      final obsoleteIds = _moduleToggleFocusNodes.keys
          .where((moduleId) => !retainedIds.contains(moduleId))
          .toList(growable: false);
      for (final moduleId in obsoleteIds) {
        _moduleToggleFocusNodes.remove(moduleId)?.dispose();
      }
    });
  }

  void _scheduleEditorFocusRecovery() {
    if (_focusRecoveryScheduled) {
      return;
    }
    _focusRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusRecoveryScheduled = false;
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
        return;
      }
      final primaryFocus = FocusManager.instance.primaryFocus;
      final focusContext = primaryFocus?.context;
      final route = focusContext == null ? null : ModalRoute.of(focusContext);
      final editorRoute = ModalRoute.of(context);
      final hasEditorFocus = primaryFocus != null &&
          primaryFocus is! FocusScopeNode &&
          focusContext != null &&
          primaryFocus.canRequestFocus &&
          route == editorRoute;
      final forcedTarget = _forcedRecoveryFocusNode;
      if (hasEditorFocus && forcedTarget == null) {
        return;
      }
      final target = forcedTarget ?? _preferredFocusNode;
      final targetContext = target?.context;
      if (target == null || targetContext == null || !target.canRequestFocus) {
        if (forcedTarget != null) {
          _scheduleEditorFocusRecovery();
        }
        return;
      }
      requestTvFocus(target, scope: FocusScope.of(targetContext));
      if (identical(target, forcedTarget)) {
        _forcedRecoveryFocusNode = null;
        _focusedMoveAction = null;
      }
      unawaited(
        Scrollable.ensureVisible(
          targetContext,
          alignment: 0.3,
          duration: Duration.zero,
        ),
      );
    });
  }

  Future<T> _runEditorOverlay<T>(Future<T> Function() showOverlay) async {
    final previousFocus = FocusManager.instance.primaryFocus;
    try {
      return await showOverlay();
    } finally {
      if (mounted && (ref.read(isTelevisionProvider).value ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) {
            return;
          }
          final previousContext = previousFocus?.context;
          if (previousFocus != null &&
              previousContext != null &&
              previousFocus.canRequestFocus) {
            requestTvFocus(
              previousFocus,
              scope: FocusScope.of(previousContext),
            );
            return;
          }
          _scheduleEditorFocusRecovery();
        });
      }
    }
  }

  @override
  void dispose() {
    for (final focusNode in _moduleToggleFocusNodes.values) {
      focusNode.dispose();
    }
    _moduleToggleFocusNodes.clear();
    for (final focusNode in _sourceFocusNodes.values) {
      focusNode.dispose();
    }
    _sourceFocusNodes.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<HomeModuleConfig> modules = ref.watch(homeModulesProvider);
    final isTelevision = ref.watch(isTelevisionProvider).value ?? false;
    final heroModule = _homeEditorHeroModule(modules);
    final sortableModules = _homeEditorSortableModules(modules);
    final List<MediaSourceConfig> mediaSources = ref.watch(
      homeSelectableMediaSourcesProvider,
    );
    final collectionsAsync = ref.watch(homeEditorCollectionsProvider);
    final Set<String> visibleSourceIds =
        (collectionsAsync.value ?? const <MediaCollection>[])
            .map((item) => item.sourceId)
            .toSet();
    final enabledSources = mediaSources.where((item) => item.enabled).toList();
    final scopedSources = enabledSources
        .where(
          (item) =>
              item.kind == MediaSourceKind.nas ||
              visibleSourceIds.contains(item.id),
        )
        .toList();
    _syncEditorFocus(
      isTelevision: isTelevision,
      modules: modules,
      heroModule: heroModule,
      sortableModules: sortableModules,
      sourceIds:
          scopedSources.map((source) => source.id).toList(growable: false),
    );

    return PopScope<void>(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(homeNavigationResetRevisionProvider.notifier).state += 1;
        }
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => _showAddModuleSheet(context, ref),
          child: const Icon(Icons.add_rounded),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            AppPageBackground(
              child: ListView(
                padding: overlayToolbarPagePadding(context),
                children: [
                  SectionPanel(
                    title: '当前模块',
                    child: heroModule == null && sortableModules.isEmpty
                        ? const Text('还没有首页模块。')
                        : Column(
                            children: [
                              if (heroModule != null)
                                _HomeModuleCard(
                                  module: heroModule,
                                  toggleFocusNode:
                                      _focusNodeForModule(heroModule.id),
                                  leading: const Icon(
                                    Icons.vertical_align_top_rounded,
                                  ),
                                  onToggle: () {
                                    ref
                                        .read(
                                            settingsControllerProvider.notifier)
                                        .toggleHomeModule(
                                          heroModule.id,
                                          !heroModule.enabled,
                                        );
                                  },
                                ),
                              if (sortableModules.isNotEmpty)
                                ReorderableListView.builder(
                                  shrinkWrap: true,
                                  buildDefaultDragHandles: false,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: sortableModules.length,
                                  onReorder: (oldIndex, newIndex) {
                                    ref
                                        .read(
                                            settingsControllerProvider.notifier)
                                        .reorderHomeModules(oldIndex, newIndex);
                                  },
                                  itemBuilder: (context, index) {
                                    final module = sortableModules[index];
                                    final settingsController = ref.read(
                                      settingsControllerProvider.notifier,
                                    );
                                    return _HomeModuleCard(
                                      key: ValueKey(module.id),
                                      module: module,
                                      toggleFocusNode:
                                          _focusNodeForModule(module.id),
                                      leading: isTelevision
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                StarflowIconButton(
                                                  icon: Icons
                                                      .arrow_upward_rounded,
                                                  tooltip: '上移',
                                                  size: 38,
                                                  onFocused: () {
                                                    final focusNode =
                                                        FocusManager.instance
                                                            .primaryFocus;
                                                    if (focusNode != null) {
                                                      _focusedMoveAction = (
                                                        moduleId: module.id,
                                                        moveUp: true,
                                                        focusNode: focusNode,
                                                      );
                                                    }
                                                  },
                                                  focusId:
                                                      'home-editor:${module.id}:move-up',
                                                  onPressed: index > 0
                                                      ? () => settingsController
                                                              .moveHomeModule(
                                                            index,
                                                            index - 1,
                                                          )
                                                      : null,
                                                ),
                                                const SizedBox(width: 6),
                                                StarflowIconButton(
                                                  icon: Icons
                                                      .arrow_downward_rounded,
                                                  tooltip: '下移',
                                                  size: 38,
                                                  onFocused: () {
                                                    final focusNode =
                                                        FocusManager.instance
                                                            .primaryFocus;
                                                    if (focusNode != null) {
                                                      _focusedMoveAction = (
                                                        moduleId: module.id,
                                                        moveUp: false,
                                                        focusNode: focusNode,
                                                      );
                                                    }
                                                  },
                                                  focusId:
                                                      'home-editor:${module.id}:move-down',
                                                  onPressed: index <
                                                          sortableModules
                                                                  .length -
                                                              1
                                                      ? () => settingsController
                                                              .moveHomeModule(
                                                            index,
                                                            index + 1,
                                                          )
                                                      : null,
                                                ),
                                              ],
                                            )
                                          : ReorderableDragStartListener(
                                              index: index,
                                              child: const Icon(
                                                Icons.drag_indicator_rounded,
                                              ),
                                            ),
                                      onEdit: () => _showEditModuleDialog(
                                        context,
                                        ref,
                                        module,
                                      ),
                                      onRemove: () {
                                        ref
                                            .read(settingsControllerProvider
                                                .notifier)
                                            .removeHomeModule(module.id);
                                      },
                                      onToggle: () {
                                        ref
                                            .read(settingsControllerProvider
                                                .notifier)
                                            .toggleHomeModule(
                                              module.id,
                                              !module.enabled,
                                            );
                                      },
                                    );
                                  },
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 18),
                  SectionPanel(
                    title: '可添加来源',
                    child: Column(
                      children: [
                        _SourceCategoryTile(
                          title: '内置',
                          icon: Icons.auto_awesome_rounded,
                          focusNode: _focusNodeForSource('builtin'),
                          onTap: () => _showBuiltinModuleSheet(context, ref),
                        ),
                        const SizedBox(height: 10),
                        _SourceCategoryTile(
                          title: '豆瓣',
                          icon: Icons.movie_filter_rounded,
                          focusNode: _focusNodeForSource('douban'),
                          onTap: () => _showDoubanModuleSheet(context, ref),
                        ),
                        if (scopedSources.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ...scopedSources.map(
                            (source) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _SourceCategoryTile(
                                title: source.name,
                                focusNode: _focusNodeForSource(source.id),
                                icon: source.kind == MediaSourceKind.emby
                                    ? Icons.video_library_rounded
                                    : Icons.storage_rounded,
                                onTap: () => _showMediaSourceModuleSheet(
                                  context,
                                  ref,
                                  source,
                                ),
                              ),
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              '还没有可用的 Emby、WebDAV 或 Quark 来源，先去设置里接入并启用后，这里就会出现。',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                  appPageBottomSpacer(),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OverlayToolbar(
                onBack: () => context.pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddModuleSheet(BuildContext context, WidgetRef ref) {
    final enabledSources =
        ref.read(homeSelectableMediaSourcesProvider).toList();
    return ref.read(homeEditorCollectionsProvider.future).then((collections) {
      if (!context.mounted) {
        return Future<void>.value();
      }
      final visibleSourceIds = collections.map((item) => item.sourceId).toSet();
      final scopedSources = enabledSources
          .where(
            (item) =>
                item.kind == MediaSourceKind.nas ||
                visibleSourceIds.contains(item.id),
          )
          .toList();
      return _runEditorOverlay(
        () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) {
            return _HomeEditorSecondarySheetBody(
              title: '选择来源分类',
              tiles: [
                _AddModuleTile(
                  title: '内置',
                  autofocus: true,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showBuiltinModuleSheet(context, ref);
                  },
                ),
                _AddModuleTile(
                  title: '豆瓣',
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _showDoubanModuleSheet(context, ref);
                  },
                ),
                ...scopedSources.map(
                  (source) => _AddModuleTile(
                    title: source.name,
                    onTap: () async {
                      Navigator.of(context).pop();
                      await _showMediaSourceModuleSheet(
                        context,
                        ref,
                        source,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      );
    });
  }

  Future<void> _showBuiltinModuleSheet(BuildContext context, WidgetRef ref) {
    return _runEditorOverlay(
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return _HomeEditorSecondarySheetBody(
            title: '内置模块',
            tiles: [
              _AddModuleTile(
                title: '最近新增',
                autofocus: true,
                onTap: () {
                  ref
                      .read(settingsControllerProvider.notifier)
                      .saveHomeModule(HomeModuleConfig.recentlyAdded());
                  Navigator.of(context).pop();
                },
              ),
              _AddModuleTile(
                title: '最近播放',
                onTap: () {
                  ref
                      .read(settingsControllerProvider.notifier)
                      .saveHomeModule(HomeModuleConfig.recentPlayback());
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDoubanModuleSheet(BuildContext context, WidgetRef ref) {
    final doubanAccount = ref.read(homeDoubanAccountProvider);
    return _runEditorOverlay(
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return _HomeEditorSecondarySheetBody(
            title: '豆瓣模块',
            tiles: [
              _AddModuleTile(
                title: '豆瓣账号设置',
                autofocus: true,
                onTap: () async {
                  Navigator.of(context).pop();
                  await _runEditorOverlay(
                    () => Navigator.of(
                      context,
                      rootNavigator: true,
                    ).push<void>(
                      SettingsMaterialPageRoute<void>(
                        builder: (context) => DoubanAccountEditorPage(
                          initial: doubanAccount,
                        ),
                      ),
                    ),
                  );
                },
              ),
              _AddModuleTile(
                title: '豆瓣我想看',
                onTap: () {
                  ref.read(settingsControllerProvider.notifier).saveHomeModule(
                        HomeModuleConfig.doubanInterest(
                          DoubanInterestStatus.mark,
                        ),
                      );
                  Navigator.of(context).pop();
                },
              ),
              _AddModuleTile(
                title: '豆瓣随机想看',
                onTap: () {
                  ref.read(settingsControllerProvider.notifier).saveHomeModule(
                        HomeModuleConfig.doubanInterest(
                          DoubanInterestStatus.randomMark,
                        ),
                      );
                  Navigator.of(context).pop();
                },
              ),
              _AddModuleTile(
                title: '豆瓣个性化推荐 · 电影',
                onTap: () {
                  ref.read(settingsControllerProvider.notifier).saveHomeModule(
                        HomeModuleConfig.doubanSuggestion(
                          DoubanSuggestionMediaType.movie,
                        ),
                      );
                  Navigator.of(context).pop();
                },
              ),
              _AddModuleTile(
                title: '豆瓣个性化推荐 · 电视',
                onTap: () {
                  ref.read(settingsControllerProvider.notifier).saveHomeModule(
                        HomeModuleConfig.doubanSuggestion(
                          DoubanSuggestionMediaType.tv,
                        ),
                      );
                  Navigator.of(context).pop();
                },
              ),
              _AddModuleTile(
                title: '豆瓣片单',
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showDoubanListDialog(context, ref);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMediaSourceModuleSheet(
    BuildContext context,
    WidgetRef ref,
    MediaSourceConfig source,
  ) async {
    final collections = await ref.read(homeEditorCollectionsProvider.future);
    if (!context.mounted) {
      return;
    }

    final sourceCollections = collections
        .where((collection) => collection.sourceId == source.id)
        .toList();
    if (sourceCollections.isEmpty && source.kind != MediaSourceKind.nas) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${source.name} 还没有可用分区'),
        ),
      );
      return;
    }

    await _runEditorOverlay(
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return _HomeEditorSecondarySheetBody(
            title: source.name,
            tiles: [
              if (source.kind == MediaSourceKind.nas)
                _AddModuleTile(
                  title: '全部内容',
                  autofocus: true,
                  onTap: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(HomeModuleConfig.librarySource(source));
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已添加 ${source.name} 全部内容')),
                    );
                  },
                ),
              for (var index = 0; index < sourceCollections.length; index++)
                _AddModuleTile(
                  autofocus: source.kind != MediaSourceKind.nas && index == 0,
                  title: sourceCollections[index].title,
                  onTap: () {
                    ref
                        .read(settingsControllerProvider.notifier)
                        .saveHomeModule(
                          HomeModuleConfig.libraryCollection(
                            sourceCollections[index],
                          ),
                        );
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '已添加 ${sourceCollections[index].title}',
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showDoubanListDialog(
    BuildContext context,
    WidgetRef ref, {
    HomeModuleConfig? existing,
  }) {
    final initialPreset = _findDoubanListPreset(existing?.doubanListUrl ?? '');
    final titleController = TextEditingController(
      text: existing?.title ?? initialPreset?.title ?? '豆瓣片单',
    );
    final urlController = TextEditingController(
      text: existing?.doubanListUrl ?? initialPreset?.url ?? '',
    );
    var selectedPresetUrl = initialPreset?.url ?? _kCustomDoubanListPresetValue;
    var displayStyle = existing?.displayStyle ?? HomeModuleDisplayStyle.poster;
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    final titleFocusNode = FocusNode(debugLabel: 'home-douban-title');
    final urlFocusNode = FocusNode(debugLabel: 'home-douban-url');
    final displayStyleFocusNode = FocusNode(
      debugLabel: 'home-douban-display-style',
    );
    final cancelFocusNode = FocusNode(debugLabel: 'home-douban-cancel');
    final saveFocusNode = FocusNode(debugLabel: 'home-douban-save');

    return _runEditorOverlay(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              final dialog = AlertDialog(
                title: Text(existing == null ? '新增豆瓣片单' : '编辑豆瓣片单'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: selectedPresetUrl,
                        decoration: const InputDecoration(labelText: '默认片单'),
                        items: [
                          for (final preset in _defaultDoubanListPresets)
                            DropdownMenuItem<String>(
                              value: preset.url,
                              child: Text(preset.title),
                            ),
                          const DropdownMenuItem<String>(
                            value: _kCustomDoubanListPresetValue,
                            child: Text('自定义输入'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            selectedPresetUrl = value;
                            if (value == _kCustomDoubanListPresetValue) {
                              return;
                            }
                            final preset = _findDoubanListPreset(value);
                            if (preset == null) {
                              return;
                            }
                            titleController.text = preset.title;
                            urlController.text = preset.url;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      wrapTelevisionDialogFieldTraversal(
                        enabled: isTelevision,
                        child: TextField(
                          controller: titleController,
                          focusNode: titleFocusNode,
                          autofocus: true,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(labelText: '标题'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      wrapTelevisionDialogFieldTraversal(
                        enabled: isTelevision,
                        child: TextField(
                          controller: urlController,
                          focusNode: urlFocusNode,
                          minLines: 2,
                          maxLines: 3,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(labelText: '片单地址'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      wrapTelevisionDialogFieldTraversal(
                        enabled: isTelevision,
                        child: DropdownButtonFormField<HomeModuleDisplayStyle>(
                          initialValue: displayStyle,
                          focusNode: displayStyleFocusNode,
                          decoration: const InputDecoration(labelText: '展示样式'),
                          items: HomeModuleDisplayStyle.values
                              .map(
                                (style) => DropdownMenuItem(
                                  value: style,
                                  child: Text(style.label),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                displayStyle = value;
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  StarflowButton(
                    label: '取消',
                    focusNode: cancelFocusNode,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    variant: StarflowButtonVariant.ghost,
                    compact: true,
                  ),
                  StarflowButton(
                    label: '保存',
                    focusNode: saveFocusNode,
                    onPressed: () {
                      final url = urlController.text.trim();
                      if (url.isEmpty) {
                        return;
                      }
                      ref
                          .read(settingsControllerProvider.notifier)
                          .saveHomeModule(
                            existing == null
                                ? HomeModuleConfig.doubanList(
                                    title: titleController.text.trim().isEmpty
                                        ? '豆瓣片单'
                                        : titleController.text.trim(),
                                    url: url,
                                    displayStyle: displayStyle,
                                  )
                                : existing.copyWith(
                                    title: titleController.text.trim().isEmpty
                                        ? existing.title
                                        : titleController.text.trim(),
                                    doubanListUrl: url,
                                    displayStyle: displayStyle,
                                  ),
                          );
                      Navigator.of(dialogContext).pop();
                    },
                    compact: true,
                  ),
                ],
              );
              return wrapTelevisionDialogBackHandling(
                enabled: isTelevision,
                dialogContext: dialogContext,
                inputFocusNodes: [titleFocusNode, urlFocusNode],
                contentFocusNodes: [
                  titleFocusNode,
                  urlFocusNode,
                  displayStyleFocusNode,
                ],
                actionFocusNodes: [saveFocusNode, cancelFocusNode],
                child: dialog,
              );
            },
          );
        },
      ).whenComplete(() {
        titleController.dispose();
        urlController.dispose();
        titleFocusNode.dispose();
        urlFocusNode.dispose();
        displayStyleFocusNode.dispose();
        cancelFocusNode.dispose();
        saveFocusNode.dispose();
      }),
    );
  }

  Future<void> _showEditModuleDialog(
    BuildContext context,
    WidgetRef ref,
    HomeModuleConfig module,
  ) {
    final titleController = TextEditingController(text: module.title);
    var interestStatus = module.doubanInterestStatus;
    var suggestionType = module.doubanSuggestionType;
    var displayStyle = module.displayStyle;
    final isTelevision = ref.read(isTelevisionProvider).value ?? false;
    final titleFocusNode = FocusNode(debugLabel: 'home-module-title');
    final displayStyleFocusNode = FocusNode(
      debugLabel: 'home-module-display-style',
    );
    final cancelFocusNode = FocusNode(debugLabel: 'home-module-cancel');
    final saveFocusNode = FocusNode(debugLabel: 'home-module-save');

    if (module.type == HomeModuleType.doubanList) {
      return _showDoubanListDialog(
        context,
        ref,
        existing: module,
      );
    }

    return _runEditorOverlay(
      () => showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setState) {
              final dialog = AlertDialog(
                title: const Text('编辑模块'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      wrapTelevisionDialogFieldTraversal(
                        enabled: isTelevision,
                        child: TextField(
                          controller: titleController,
                          focusNode: titleFocusNode,
                          autofocus: true,
                          decoration: const InputDecoration(labelText: '标题'),
                        ),
                      ),
                      if (module.type == HomeModuleType.doubanInterest) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<DoubanInterestStatus>(
                          initialValue: interestStatus,
                          decoration: const InputDecoration(labelText: '豆瓣状态'),
                          items: DoubanInterestStatus.values
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                interestStatus = value;
                              });
                            }
                          },
                        ),
                      ],
                      if (module.type == HomeModuleType.doubanSuggestion) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<DoubanSuggestionMediaType>(
                          initialValue: suggestionType,
                          decoration: const InputDecoration(labelText: '推荐类型'),
                          items: DoubanSuggestionMediaType.values
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item,
                                  child: Text(item.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                suggestionType = value;
                              });
                            }
                          },
                        ),
                      ],
                      if (module.supportsDisplayStyle) ...[
                        const SizedBox(height: 12),
                        wrapTelevisionDialogFieldTraversal(
                          enabled: isTelevision,
                          child:
                              DropdownButtonFormField<HomeModuleDisplayStyle>(
                            initialValue: displayStyle,
                            focusNode: displayStyleFocusNode,
                            decoration:
                                const InputDecoration(labelText: '展示样式'),
                            items: HomeModuleDisplayStyle.values
                                .map(
                                  (style) => DropdownMenuItem(
                                    value: style,
                                    child: Text(style.label),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  displayStyle = value;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  StarflowButton(
                    label: '取消',
                    focusNode: cancelFocusNode,
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    variant: StarflowButtonVariant.ghost,
                    compact: true,
                  ),
                  StarflowButton(
                    label: '保存',
                    focusNode: saveFocusNode,
                    onPressed: () {
                      ref
                          .read(settingsControllerProvider.notifier)
                          .saveHomeModule(
                            module.copyWith(
                              title: titleController.text.trim().isEmpty
                                  ? module.title
                                  : titleController.text.trim(),
                              doubanInterestStatus: interestStatus,
                              doubanSuggestionType: suggestionType,
                              displayStyle: displayStyle,
                            ),
                          );
                      Navigator.of(dialogContext).pop();
                    },
                    compact: true,
                  ),
                ],
              );
              return wrapTelevisionDialogBackHandling(
                enabled: isTelevision,
                dialogContext: dialogContext,
                inputFocusNodes: [titleFocusNode],
                contentFocusNodes: [titleFocusNode, displayStyleFocusNode],
                actionFocusNodes: [saveFocusNode, cancelFocusNode],
                child: dialog,
              );
            },
          );
        },
      ).whenComplete(() {
        titleController.dispose();
        titleFocusNode.dispose();
        displayStyleFocusNode.dispose();
        cancelFocusNode.dispose();
        saveFocusNode.dispose();
      }),
    );
  }
}

_DoubanListPreset? _findDoubanListPreset(String url) {
  final normalizedUrl = url.trim();
  if (normalizedUrl.isEmpty) {
    return null;
  }

  for (final preset in _defaultDoubanListPresets) {
    if (preset.url == normalizedUrl) {
      return preset;
    }
  }
  return null;
}

class _DoubanListPreset {
  const _DoubanListPreset({
    required this.title,
    required this.url,
  });

  final String title;
  final String url;
}

class _AddModuleTile extends StatelessWidget {
  const _AddModuleTile({
    required this.title,
    required this.onTap,
    this.autofocus = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: StarflowSelectionTile(
        title: title,
        onPressed: onTap,
        autofocus: autofocus,
        focusId: 'home-editor:add:$title',
        trailing: const Icon(Icons.add_circle_outline_rounded),
      ),
    );
  }
}

class _SourceCategoryTile extends StatelessWidget {
  const _SourceCategoryTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.focusNode,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return StarflowSelectionTile(
      leading: CircleAvatar(
        backgroundColor: scheme.primary.withValues(alpha: 0.12),
        foregroundColor: scheme.primary,
        child: Icon(icon),
      ),
      title: title,
      onPressed: onTap,
      focusNode: focusNode,
      focusId: focusNode?.debugLabel,
    );
  }
}
