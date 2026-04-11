import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/app/router/app_routes.dart';

void main() {
  group('AppRoutes', () {
    test('route names stay unique', () {
      final names = AppRoutes.all.map((route) => route.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('route paths stay unique', () {
      final paths = AppRoutes.all.map((route) => route.path).toList();
      expect(paths.toSet().length, paths.length);
    });

    test('shell branch routes stay in the main navigation order', () {
      expect(
        AppRoutes.shellBranches,
        equals([
          AppRoutes.home,
          AppRoutes.search,
          AppRoutes.library,
          AppRoutes.settings,
        ]),
      );
    });
  });
}
