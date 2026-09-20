import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/details/application/detail_page_controller.dart';
import 'package:starflow/features/details/domain/media_detail_models.dart';

void main() {
  test('selection and resets expose consistent state during notifications', () {
    const target = MediaDetailTarget(
      title: 'Movie',
      posterUrl: '',
      overview: '',
      itemType: 'movie',
    );
    final controller = DetailPageController();
    addTearDown(controller.dispose);
    final notifications = <String>[];
    controller.libraryMatchViewListenable.addListener(() {
      expect(controller.libraryMatchView,
          same(controller.libraryMatchViewListenable.value));
      notifications.add('view');
    });
    controller.manualOverrideTargetListenable.addListener(() {
      expect(controller.manualOverrideTarget,
          same(controller.manualOverrideTargetListenable.value));
      notifications.add('target');
    });

    expect(controller.applySelectedLibraryMatchIndex(0), isNull);
    expect(notifications, isEmpty);
    controller.updateLibraryMatchView(choices: [target], isMatching: true);
    expect(controller.applySelectedLibraryMatchIndex(99), same(target));
    expect(controller.selectedLibraryMatchIndex, 0);
    expect(controller.manualOverrideTarget, same(target));
    expect(notifications, ['view', 'view', 'target']);

    controller.resetForPageInactive();
    expect(controller.isMatchingLocalResource, isFalse);
    expect(controller.libraryMatchChoices, [target]);
    expect(controller.manualOverrideTarget, same(target));
    notifications.clear();
    controller.resetForTargetChange();
    expect(notifications, ['target', 'view']);
    expect(controller.libraryMatchChoices, isEmpty);
    expect(controller.manualOverrideTarget, isNull);
    expect(controller.selectedLibraryMatchIndex, 0);
  });

  test('new sessions invalidate old work and require a visible mounted page',
      () {
    final controller = DetailPageController(initialSessionId: 7);
    addTearDown(controller.dispose);
    final previous = controller.detailSessionId;
    final current = controller.startNewSession();
    expect(current, previous + 1);
    expect(
        controller.isSessionActive(previous,
            isMounted: true, isPageVisible: true),
        isFalse);
    expect(
        controller.isSessionActive(current,
            isMounted: true, isPageVisible: true),
        isTrue);
    expect(
        controller.isSessionActive(current,
            isMounted: false, isPageVisible: true),
        isFalse);
    expect(
        controller.isSessionActive(current,
            isMounted: true, isPageVisible: false),
        isFalse);
  });
}
