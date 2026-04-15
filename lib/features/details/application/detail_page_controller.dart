import 'package:flutter/foundation.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

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

class DetailPageController {
  DetailPageController({
    int initialSessionId = 0,
    MediaDetailTarget? initialManualOverrideTarget,
    DetailLibraryMatchViewState libraryMatchView =
        const DetailLibraryMatchViewState(),
  })  : _detailSessionId = initialSessionId,
        _manualOverrideTarget = initialManualOverrideTarget,
        _libraryMatchView = libraryMatchView {
    _manualOverrideTargetNotifier = ValueNotifier<MediaDetailTarget?>(
      _manualOverrideTarget,
    );
    _libraryMatchViewNotifier =
        ValueNotifier<DetailLibraryMatchViewState>(_libraryMatchView);
  }

  int _detailSessionId;
  MediaDetailTarget? _manualOverrideTarget;
  DetailLibraryMatchViewState _libraryMatchView;
  Object? _activeLibraryMatchToken;
  late final ValueNotifier<MediaDetailTarget?> _manualOverrideTargetNotifier;
  late final ValueNotifier<DetailLibraryMatchViewState>
      _libraryMatchViewNotifier;

  int get detailSessionId => _detailSessionId;
  MediaDetailTarget? get manualOverrideTarget => _manualOverrideTarget;
  DetailLibraryMatchViewState get libraryMatchView => _libraryMatchView;
  ValueListenable<MediaDetailTarget?> get manualOverrideTargetListenable =>
      _manualOverrideTargetNotifier;
  ValueListenable<DetailLibraryMatchViewState> get libraryMatchViewListenable =>
      _libraryMatchViewNotifier;

  List<MediaDetailTarget> get libraryMatchChoices => _libraryMatchView.choices;
  int get selectedLibraryMatchIndex => _libraryMatchView.selectedIndex;
  bool get isMatchingLocalResource => _libraryMatchView.isMatching;
  int get currentLibraryMatchIndex => _libraryMatchView.effectiveSelectedIndex;

  int startNewSession() {
    _detailSessionId += 1;
    return _detailSessionId;
  }

  int cancelDetailTasks() {
    cancelActiveLibraryMatch();
    _detailSessionId += 1;
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
    _manualOverrideTargetNotifier.value = target;
  }

  void resetForTargetChange() {
    _manualOverrideTarget = null;
    _manualOverrideTargetNotifier.value = null;
    _libraryMatchView = const DetailLibraryMatchViewState(
      choices: <MediaDetailTarget>[],
      selectedIndex: 0,
      isMatching: false,
    );
    _libraryMatchViewNotifier.value = _libraryMatchView;
  }

  void resetForPageInactive() {
    _libraryMatchView = _libraryMatchView.copyWith(isMatching: false);
    _libraryMatchViewNotifier.value = _libraryMatchView;
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
    _libraryMatchViewNotifier.value = _libraryMatchView;
  }

  MediaDetailTarget? applySelectedLibraryMatchIndex(int index) {
    if (_libraryMatchView.choices.isEmpty) {
      return null;
    }
    final resolvedIndex = index.clamp(0, _libraryMatchView.choices.length - 1);
    final resolvedTarget = _libraryMatchView.choices[resolvedIndex];
    _libraryMatchView =
        _libraryMatchView.copyWith(selectedIndex: resolvedIndex);
    _libraryMatchViewNotifier.value = _libraryMatchView;
    _manualOverrideTarget = resolvedTarget;
    _manualOverrideTargetNotifier.value = resolvedTarget;
    return resolvedTarget;
  }

  void dispose() {
    _manualOverrideTargetNotifier.dispose();
    _libraryMatchViewNotifier.dispose();
  }
}
