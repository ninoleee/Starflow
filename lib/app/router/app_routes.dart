class AppRouteSpec {
  const AppRouteSpec({
    required this.name,
    required this.path,
  });

  final String name;
  final String path;
}

abstract final class AppRoutes {
  static const boot = AppRouteSpec(name: 'boot', path: '/boot');
  static const home = AppRouteSpec(name: 'home', path: '/home');
  static const search = AppRouteSpec(name: 'search', path: '/search');
  static const library = AppRouteSpec(name: 'library', path: '/library');
  static const settings = AppRouteSpec(name: 'settings', path: '/settings');
  static const homeEditor =
      AppRouteSpec(name: 'home-editor', path: '/home-editor');
  static const homeModuleList =
      AppRouteSpec(name: 'home-module-list', path: '/home-module-list');
  static const collection =
      AppRouteSpec(name: 'collection', path: '/collection');
  static const detail = AppRouteSpec(name: 'detail', path: '/detail');
  static const personCredits =
      AppRouteSpec(name: 'person-credits', path: '/person-credits');
  static const detailSearch =
      AppRouteSpec(name: 'detail-search', path: '/detail-search');
  static const metadataIndex =
      AppRouteSpec(name: 'metadata-index', path: '/metadata-index');
  static const subtitleSearch =
      AppRouteSpec(name: 'subtitle-search', path: '/subtitle-search');
  static const player = AppRouteSpec(name: 'player', path: '/player');

  static const shellBranches = <AppRouteSpec>[
    home,
    search,
    library,
    settings,
  ];

  static const all = <AppRouteSpec>[
    boot,
    ...shellBranches,
    homeEditor,
    homeModuleList,
    collection,
    detail,
    personCredits,
    detailSearch,
    metadataIndex,
    subtitleSearch,
    player,
  ];
}
