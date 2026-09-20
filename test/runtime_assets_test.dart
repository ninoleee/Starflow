import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime bundle contains logos but not design masters or perf video',
      () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    expect(assets, contains('assets/branding/starflow_logo_primary.png'));
    expect(assets, contains('assets/branding/starflow_launch_logo.png'));
    expect(assets, isNot(contains('assets/branding/starflow_logo_source.png')));
    expect(assets,
        isNot(contains('assets/branding/starflow_ios_dark_icon_source.png')));
    expect(assets, isNot(contains('assets/perf/baseline.mp4')));
  });
}
