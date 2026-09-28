import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/discovery/presentation/douban_browse_page.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/search/presentation/search_page.dart';

class SearchHubPage extends ConsumerStatefulWidget {
  const SearchHubPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchHubPage> createState() => _SearchHubPageState();
}

class _SearchHubPageState extends ConsumerState<SearchHubPage> {
  bool _browse = false;
  bool _browseCreated = false;
  bool _modeTouched = false;
  bool _modeTabsFocused = false;
  final _searchScrollController = ScrollController();
  final _browseScrollController = ScrollController();
  final _searchPageSearchKey = GlobalKey();
  final _searchPageBrowseKey = GlobalKey();
  final _browsePageSearchKey = GlobalKey();
  final _browsePageBrowseKey = GlobalKey();
  final _searchPageSearchFocus =
      FocusNode(debugLabel: 'search-hub-search-search');
  final _searchPageBrowseFocus =
      FocusNode(debugLabel: 'search-hub-search-browse');
  final _browsePageSearchFocus =
      FocusNode(debugLabel: 'search-hub-browse-search');
  final _browsePageBrowseFocus =
      FocusNode(debugLabel: 'search-hub-browse-browse');

  @override
  void dispose() {
    _searchScrollController.removeListener(_handlePageScroll);
    _browseScrollController.removeListener(_handlePageScroll);
    _searchScrollController.dispose();
    _browseScrollController.dispose();
    _searchPageSearchFocus.dispose();
    _searchPageBrowseFocus.dispose();
    _browsePageSearchFocus.dispose();
    _browsePageBrowseFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _searchScrollController.addListener(_handlePageScroll);
    _browseScrollController.addListener(_handlePageScroll);
    _restoreMode();
  }

  Future<void> _restoreMode() async {
    final selected =
        await ref.read(searchPreferencesRepositoryProvider).loadBrowseMode();
    if (!mounted ||
        _modeTouched ||
        (widget.initialQuery ?? '').trim().isNotEmpty) {
      return;
    }
    setState(() {
      _browse = selected;
      _browseCreated |= selected;
    });
  }

  @override
  void didUpdateWidget(covariant SearchHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery &&
        (widget.initialQuery ?? '').trim().isNotEmpty) {
      _browse = false;
    }
  }

  Widget _buildModeTabs({
    required bool browsePage,
    required bool isTelevision,
  }) {
    return Padding(
      key: const ValueKey('search-hub-tabs'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: _handleModeTabsFocus,
        child: Center(
          child: ConstrainedBox(
            key: const ValueKey('search-hub-mode-tabs-group'),
            constraints: BoxConstraints(maxWidth: isTelevision ? 320 : 240),
            child: Row(children: [
              Expanded(
                child: StarflowChipButton(
                  key: browsePage ? _browsePageSearchKey : _searchPageSearchKey,
                  focusId: 'search-hub-mode-search',
                  focusNode: browsePage
                      ? _browsePageSearchFocus
                      : _searchPageSearchFocus,
                  label: '搜索',
                  selected: !_browse,
                  onPressed: () => _selectMode(false),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StarflowChipButton(
                  key: browsePage ? _browsePageBrowseKey : _searchPageBrowseKey,
                  focusId: 'search-hub-mode-browse',
                  focusNode: browsePage
                      ? _browsePageBrowseFocus
                      : _searchPageBrowseFocus,
                  label: '选片',
                  selected: _browse,
                  onPressed: () => _selectMode(true),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _selectMode(bool browse) {
    _modeTouched = true;
    setState(() {
      _browse = browse;
      _browseCreated |= browse;
    });
    unawaited(ref
        .read(searchPreferencesRepositoryProvider)
        .saveBrowseMode(browse)
        .catchError((Object _) {}));
  }

  Future<void> _returnToModeTabs() async {
    final controller =
        _browse ? _browseScrollController : _searchScrollController;
    if (controller.hasClients && controller.offset > 0) {
      await controller.animateTo(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusSelectedModeTab();
    });
  }

  bool _focusSelectedModeTab() {
    final focus = _browse
        ? (_browse ? _browsePageBrowseFocus : _browsePageSearchFocus)
        : (_browse ? _searchPageBrowseFocus : _searchPageSearchFocus);
    if (!focus.canRequestFocus) return false;
    focus.requestFocus();
    if (!_modeTabsFocused) {
      setState(() => _modeTabsFocused = true);
    }
    return true;
  }

  void _handleModeTabsFocus(bool focused) {
    if (!mounted || _modeTabsFocused == focused) return;
    setState(() => _modeTabsFocused = focused);
  }

  void _handlePageScroll() {
    if (_modeTabsFocused &&
        ((_browse &&
                _browseScrollController.hasClients &&
                _browseScrollController.offset > 8) ||
            (!_browse &&
                _searchScrollController.hasClients &&
                _searchScrollController.offset > 8))) {
      setState(() => _modeTabsFocused = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tv = ref.watch(isTelevisionProvider).value ?? false;
    return PopScope<void>(
      canPop: !tv || _modeTabsFocused,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !tv || _modeTabsFocused) return;
        unawaited(_returnToModeTabs());
      },
      child: Stack(children: [
        Offstage(
          offstage: _browse,
          child: TickerMode(
            enabled: !_browse,
            child: ExcludeFocus(
              excluding: _browse,
              child: SearchPage(
                initialQuery: widget.initialQuery,
                embedded: true,
                embeddedHeader:
                    _buildModeTabs(browsePage: false, isTelevision: tv),
                scrollController: _searchScrollController,
              ),
            ),
          ),
        ),
        if (_browseCreated)
          Offstage(
            offstage: !_browse,
            child: TickerMode(
              enabled: _browse,
              child: ExcludeFocus(
                excluding: !_browse,
                child: DoubanBrowsePage(
                  topContent:
                      _buildModeTabs(browsePage: true, isTelevision: tv),
                  scrollController: _browseScrollController,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
