import 'package:flutter/foundation.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';
import 'package:starflow/features/playback/domain/subtitle_search_models.dart';

const Object detailPageViewStateUnchanged = Object();

@immutable
class DetailLibraryMatchViewState {
  const DetailLibraryMatchViewState({
    this.choices = const <MediaDetailTarget>[],
    this.selectedIndex = 0,
    this.isMatching = false,
  });

  final List<MediaDetailTarget> choices;
  final int selectedIndex;
  final bool isMatching;

  int get effectiveSelectedIndex {
    if (choices.isEmpty) {
      return 0;
    }
    return selectedIndex.clamp(0, choices.length - 1);
  }

  DetailLibraryMatchViewState copyWith({
    List<MediaDetailTarget>? choices,
    int? selectedIndex,
    bool? isMatching,
  }) {
    return DetailLibraryMatchViewState(
      choices: choices ?? this.choices,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      isMatching: isMatching ?? this.isMatching,
    );
  }
}

@immutable
class DetailSubtitleSearchViewState {
  const DetailSubtitleSearchViewState({
    this.choices = const <CachedSubtitleSearchOption>[],
    this.selectedIndex = -1,
    this.isSearching = false,
    this.busyResultId,
    this.statusMessage,
  });

  final List<CachedSubtitleSearchOption> choices;
  final int selectedIndex;
  final bool isSearching;
  final String? busyResultId;
  final String? statusMessage;

  int get effectiveSelectedIndex {
    if (choices.isEmpty) {
      return -1;
    }
    return selectedIndex.clamp(-1, choices.length - 1);
  }

  DetailSubtitleSearchViewState copyWith({
    List<CachedSubtitleSearchOption>? choices,
    int? selectedIndex,
    bool? isSearching,
    Object? busyResultId = detailPageViewStateUnchanged,
    Object? statusMessage = detailPageViewStateUnchanged,
  }) {
    return DetailSubtitleSearchViewState(
      choices: choices ?? this.choices,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      isSearching: isSearching ?? this.isSearching,
      busyResultId: identical(busyResultId, detailPageViewStateUnchanged)
          ? this.busyResultId
          : busyResultId as String?,
      statusMessage: identical(statusMessage, detailPageViewStateUnchanged)
          ? this.statusMessage
          : statusMessage as String?,
    );
  }
}

class DetailPageController extends ChangeNotifier {
  DetailPageController({
    int initialSessionId = 0,
    MediaDetailTarget? initialManualOverrideTarget,
    DetailLibraryMatchViewState libraryMatchView =
        const DetailLibraryMatchViewState(),
    DetailSubtitleSearchViewState subtitleSearchView =
        const DetailSubtitleSearchViewState(),
  })  : _detailSessionId = initialSessionId,
        _manualOverrideTarget = initialManualOverrideTarget,
        _libraryMatchView = libraryMatchView,
        _subtitleSearchView = subtitleSearchView;

  int _detailSessionId;
  MediaDetailTarget? _manualOverrideTarget;
  DetailLibraryMatchViewState _libraryMatchView;
  DetailSubtitleSearchViewState _subtitleSearchView;
  Object? _activeLibraryMatchToken;

  int get detailSessionId => _detailSessionId;
  MediaDetailTarget? get manualOverrideTarget => _manualOverrideTarget;
  DetailLibraryMatchViewState get libraryMatchView => _libraryMatchView;
  DetailSubtitleSearchViewState get subtitleSearchView => _subtitleSearchView;

  List<MediaDetailTarget> get libraryMatchChoices => _libraryMatchView.choices;
  int get selectedLibraryMatchIndex => _libraryMatchView.selectedIndex;
  bool get isMatchingLocalResource => _libraryMatchView.isMatching;
  int get currentLibraryMatchIndex => _libraryMatchView.effectiveSelectedIndex;

  List<CachedSubtitleSearchOption> get subtitleSearchChoices =>
      _subtitleSearchView.choices;
  int get selectedSubtitleSearchIndex => _subtitleSearchView.selectedIndex;
  bool get isSearchingSubtitles => _subtitleSearchView.isSearching;
  String? get busySubtitleResultId => _subtitleSearchView.busyResultId;
  String? get subtitleSearchStatusMessage => _subtitleSearchView.statusMessage;

  int startNewSession() {
    _detailSessionId += 1;
    notifyListeners();
    return _detailSessionId;
  }

  int cancelDetailTasks() {
    cancelActiveLibraryMatch();
    _detailSessionId += 1;
    notifyListeners();
    return _detailSessionId;
  }

  bool isSessionActive(
    int sessionId, {
    required bool isMounted,
    required bool isPageVisible,
  }) {
    return isMounted && isPageVisible && _detailSessionId == sessionId;
  }

  Object startLibraryMatchTask() {
    final token = Object();
    _activeLibraryMatchToken = token;
    return token;
  }

  void cancelActiveLibraryMatch() {
    _activeLibraryMatchToken = null;
  }

  bool isLibraryMatchTaskActive(
    int sessionId,
    Object token, {
    required bool isMounted,
    required bool isPageVisible,
  }) {
    return isSessionActive(
          sessionId,
          isMounted: isMounted,
          isPageVisible: isPageVisible,
        ) &&
        identical(_activeLibraryMatchToken, token);
  }

  void setManualOverrideTarget(MediaDetailTarget? target) {
    _manualOverrideTarget = target;
    notifyListeners();
  }

  void resetForTargetChange() {
    _manualOverrideTarget = null;
    _libraryMatchView = const DetailLibraryMatchViewState(
      choices: <MediaDetailTarget>[],
      selectedIndex: 0,
      isMatching: false,
    );
    _subtitleSearchView = const DetailSubtitleSearchViewState(
      choices: <CachedSubtitleSearchOption>[],
      selectedIndex: -1,
      isSearching: false,
      busyResultId: null,
      statusMessage: null,
    );
    notifyListeners();
  }

  void resetForPageInactive() {
    _libraryMatchView = _libraryMatchView.copyWith(isMatching: false);
    _subtitleSearchView = _subtitleSearchView.copyWith(
      isSearching: false,
      busyResultId: null,
    );
    notifyListeners();
  }

  void updateLibraryMatchView({
    List<MediaDetailTarget>? choices,
    int? selectedIndex,
    bool? isMatching,
  }) {
    _libraryMatchView = _libraryMatchView.copyWith(
      choices: choices,
      selectedIndex: selectedIndex,
      isMatching: isMatching,
    );
    notifyListeners();
  }

  void updateSubtitleSearchView({
    List<CachedSubtitleSearchOption>? choices,
    int? selectedIndex,
    bool? isSearching,
    Object? busyResultId = detailPageViewStateUnchanged,
    Object? statusMessage = detailPageViewStateUnchanged,
  }) {
    _subtitleSearchView = _subtitleSearchView.copyWith(
      choices: choices,
      selectedIndex: selectedIndex,
      isSearching: isSearching,
      busyResultId: busyResultId,
      statusMessage: statusMessage,
    );
    notifyListeners();
  }

  int normalizeSubtitleSearchIndex(
    int index, {
    List<CachedSubtitleSearchOption>? choices,
  }) {
    final resolvedChoices = choices ?? _subtitleSearchView.choices;
    if (resolvedChoices.isEmpty) {
      return -1;
    }
    return index.clamp(-1, resolvedChoices.length - 1);
  }

  int get currentSubtitleSearchIndex {
    return normalizeSubtitleSearchIndex(_subtitleSearchView.selectedIndex);
  }

  CachedSubtitleSearchOption? get selectedSubtitleSearchChoice {
    final index = currentSubtitleSearchIndex;
    if (index < 0 || index >= _subtitleSearchView.choices.length) {
      return null;
    }
    return _subtitleSearchView.choices[index];
  }

  MediaDetailTarget? applySelectedLibraryMatchIndex(int index) {
    if (_libraryMatchView.choices.isEmpty) {
      return null;
    }
    final resolvedIndex = index.clamp(0, _libraryMatchView.choices.length - 1);
    final resolvedTarget = _libraryMatchView.choices[resolvedIndex];
    _libraryMatchView =
        _libraryMatchView.copyWith(selectedIndex: resolvedIndex);
    _manualOverrideTarget = resolvedTarget;
    notifyListeners();
    return resolvedTarget;
  }

  List<MediaDetailTarget> resolveProviderInvalidationTargets({
    required MediaDetailTarget seedTarget,
    Iterable<MediaDetailTarget> additionalTargets = const [],
  }) {
    final seenKeys = <String>{};
    final result = <MediaDetailTarget>[];
    final targets = <MediaDetailTarget>[
      seedTarget,
      if (_manualOverrideTarget != null) _manualOverrideTarget!,
      ...additionalTargets,
    ];
    for (final target in targets) {
      if (seenKeys.add(buildProviderInvalidationKey(target))) {
        result.add(target);
      }
    }
    return result;
  }

  static String buildProviderInvalidationKey(MediaDetailTarget target) {
    return <String>[
      target.sourceId.trim(),
      target.itemId.trim(),
      target.title.trim(),
      target.searchQuery.trim(),
      target.itemType.trim(),
    ].join('|');
  }
}
