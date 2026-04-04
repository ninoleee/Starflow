import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  test('app settings persist home hero style', () {
    final settings = AppSettings.fromJson({
      'homeHeroStyle': 'borderless',
    });

    expect(settings.homeHeroStyle, HomeHeroStyle.borderless);
    expect(settings.toJson()['homeHeroStyle'], 'borderless');
  });

  test('app settings default hero style is normal', () {
    final settings = AppSettings.fromJson(const {});

    expect(settings.homeHeroStyle, HomeHeroStyle.normal);
  });
}
