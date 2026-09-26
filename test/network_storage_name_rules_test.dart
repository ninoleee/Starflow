import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';
import 'package:starflow/features/settings/domain/network_storage_settings_scope.dart';

void main() {
  test('legacy per-drive rename values are kept but no longer applied', () {
    final legacy = NetworkStorageConfig.fromJson({
      'quarkSanitizeSavedNamesEnabled': true,
      'quarkSanitizedNameCharacters': '#',
      'cloud115SanitizeSavedNamesEnabled': false,
      'cloud115SanitizedNameCharacters': '?',
      'aliyunSanitizeSavedNamesEnabled': true,
      'aliyunSanitizedNameCharacters': '%',
    });
    expect([
      legacy.effectiveQuarkNameCharacters,
      legacy.effective115NameCharacters,
      legacy.effectiveAliyunNameCharacters,
    ], [
      '',
      '',
      ''
    ]);

    final common = legacy.copyWith(
        commonSanitizeSavedNamesEnabled: true,
        commonSanitizedNameCharacters: '!');
    expect([
      common.effectiveQuarkNameCharacters,
      common.effective115NameCharacters,
      common.effectiveAliyunNameCharacters,
    ], [
      '!',
      '!',
      '!'
    ]);
    final restored = NetworkStorageConfig.fromJson(common.toJson());
    expect(restored.effective115NameCharacters, '!');
    expect(restored.toJson()['quarkSanitizeSavedNamesEnabled'], isTrue);
    expect(restored.toJson()['quarkSanitizedNameCharacters'], '#');
  });

  test('all drives follow common enablement, characters and JSON round trip',
      () {
    const common = NetworkStorageConfig(
        commonSanitizeSavedNamesEnabled: true,
        commonSanitizedNameCharacters: '#',
        quarkSanitizeSavedNamesEnabled: true,
        quarkSanitizedNameCharacters: '?',
        cloud115SanitizeSavedNamesEnabled: true,
        cloud115SanitizedNameCharacters: '%',
        aliyunSanitizeSavedNamesEnabled: true,
        aliyunSanitizedNameCharacters: '!');
    expect([
      common.effectiveQuarkNameCharacters,
      common.effective115NameCharacters,
      common.effectiveAliyunNameCharacters,
    ], [
      '#',
      '#',
      '#'
    ]);

    final off = common.copyWith(commonSanitizeSavedNamesEnabled: false);
    expect([
      off.effectiveQuarkNameCharacters,
      off.effective115NameCharacters,
      off.effectiveAliyunNameCharacters,
    ], [
      '',
      '',
      ''
    ]);

    final empty = common.copyWith(commonSanitizedNameCharacters: '  ');
    expect(empty.effectiveAliyunNameCharacters, isEmpty);
    expect(NetworkStorageConfig.fromJson(common.toJson()).toJson(),
        common.toJson());
  });

  test('scoped edits cannot overwrite common rename rules', () {
    const current = NetworkStorageConfig(
        commonSanitizeSavedNamesEnabled: true,
        commonSanitizedNameCharacters: '#',
        quarkSanitizedNameCharacters: '!',
        cloud115SanitizedNameCharacters: '?');
    const stale = NetworkStorageConfig(
        commonSanitizedNameCharacters: '%',
        quarkSanitizeSavedNamesEnabled: true,
        quarkSanitizedNameCharacters: '!');
    final quark = NetworkStorageSettingsScope.quark.merge(current, stale);
    expect(quark.commonSanitizeSavedNamesEnabled, isTrue);
    expect(quark.commonSanitizedNameCharacters, '#');
    expect(quark.effectiveQuarkNameCharacters, '#');
    expect(quark.quarkSanitizedNameCharacters, '!');

    final common = NetworkStorageSettingsScope.common.merge(current, stale);
    expect(common.commonSanitizedNameCharacters, '%');
    expect(common.commonSanitizeSavedNamesEnabled, isFalse);
    expect(common.quarkSanitizedNameCharacters, '!');
    expect(common.cloud115SanitizedNameCharacters, '?');
  });
}
