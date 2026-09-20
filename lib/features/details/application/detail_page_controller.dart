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
        _manualOverrideTargetNotifier =
            ValueNotifier(initialManualOverrideTarget),
        _libraryMatchViewNotifier = ValueNotifier(libraryMatchView);

  int _detailSessionId;
  final ValueNotifier<MediaDetailTarget?> _manualOverrideTargetNotifier;
  final ValueNotifier<DetailLibraryMatchViewState> _libraryMatchViewNotifier;

  int get detailSessionId => _detailSessionId;
  MediaDetailTarget? get manualOverrideTarget =>
      _manualOverrideTargetNotifier.value;
  DetailLibraryMatchViewState get libraryMatchView =>
      _libraryMatchViewNotifier.value;
  ValueListenable<MediaDetailTarget?> get manualOverrideTargetListenable =>
      _manualOverrideTargetNotifier;
  ValueListenable<DetailLibraryMatchViewState> get libraryMatchViewListenable =>
      _libraryMatchViewNotifier;

  List<MediaDetailTarget> get libraryMatchChoices => libraryMatchView.choices;
  int get selectedLibraryMatchIndex => libraryMatchView.selectedIndex;
  bool get isMatchingLocalResource => libraryMatchView.isMatching;

  int startNewSession() {
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

  void setManualOverrideTarget(MediaDetailTarget? target) {
    _manualOverrideTargetNotifier.value = target;
  }

  void resetForTargetChange() {
    setManualOverrideTarget(null);
    _libraryMatchViewNotifier.value = const DetailLibraryMatchViewState();
  }

  void resetForPageInactive() {
    updateLibraryMatchView(isMatching: false);
  }

  void updateLibraryMatchView({
    List<MediaDetailTarget>? choices,
    int? selectedIndex,
    bool? isMatching,
  }) {
    _libraryMatchViewNotifier.value = libraryMatchView.copyWith(
      choices: choices,
      selectedIndex: selectedIndex,
      isMatching: isMatching,
    );
  }

  MediaDetailTarget? applySelectedLibraryMatchIndex(int index) {
    if (libraryMatchChoices.isEmpty) {
      return null;
    }
    final resolvedIndex = index.clamp(0, libraryMatchChoices.length - 1);
    final resolvedTarget = libraryMatchChoices[resolvedIndex];
    updateLibraryMatchView(selectedIndex: resolvedIndex);
    setManualOverrideTarget(resolvedTarget);
    return resolvedTarget;
  }

  void dispose() {
    _manualOverrideTargetNotifier.dispose();
    _libraryMatchViewNotifier.dispose();
  }
}
