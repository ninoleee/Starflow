import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Offstage(
        offstage: _browse,
        child: TickerMode(
          enabled: !_browse,
          child: ExcludeFocus(
            excluding: _browse,
            child:
                SearchPage(initialQuery: widget.initialQuery, embedded: true),
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
              child: const DoubanBrowsePage(),
            ),
          ),
        ),
      Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        left: 16,
        right: 16,
        child: Center(
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('资源搜索')),
              ButtonSegment(value: true, label: Text('豆瓣选片')),
            ],
            selected: {_browse},
            onSelectionChanged: (selection) {
              _modeTouched = true;
              setState(() {
                _browse = selection.single;
                _browseCreated |= _browse;
              });
              unawaited(ref
                  .read(searchPreferencesRepositoryProvider)
                  .saveBrowseMode(_browse)
                  .catchError((Object _) {}));
            },
          ),
        ),
      ),
    ]);
  }
}
