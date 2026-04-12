part of 'home_controller.dart';

enum HomeSectionLayout {
  posterRail,
  carousel,
}

class HomeCardViewModel {
  const HomeCardViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String posterUrl;
  final MediaDetailTarget detailTarget;
}

class HomeCarouselItemViewModel {
  const HomeCarouselItemViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.detailTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final MediaDetailTarget detailTarget;
}

class HomeSectionViewAllTarget {
  const HomeSectionViewAllTarget.collection(this.extra)
      : routeName = 'collection';

  const HomeSectionViewAllTarget.module(this.extra)
      : routeName = 'home-module-list';

  final String routeName;
  final Object extra;
}

class HomeSectionViewModel {
  const HomeSectionViewModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.layout,
    this.items = const [],
    this.carouselItems = const [],
    this.viewAllTarget,
  });

  final String id;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final HomeSectionLayout layout;
  final List<HomeCardViewModel> items;
  final List<HomeCarouselItemViewModel> carouselItems;
  final HomeSectionViewAllTarget? viewAllTarget;
}

class HomeResolvedSectionsState {
  const HomeResolvedSectionsState({
    this.sections = const <HomeSectionViewModel>[],
    this.hasPendingSections = false,
  });

  final List<HomeSectionViewModel> sections;
  final bool hasPendingSections;
}
