import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/features/bootstrap/application/bootstrap_controller.dart';
import 'package:starflow/features/settings/application/settings_controller.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BootstrapController start completes basic startup flow', () async {
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_PerfSettingsController.new),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(bootstrapControllerProvider.notifier);
    await controller.start();

    final state = container.read(bootstrapControllerProvider);
    expect(state.isComplete, isTrue);
    expect(state.progress, 1);
    expect(state.currentStep, 3);
  });
}

class _PerfSettingsController extends SettingsController {
  @override
  Future<AppSettings> build() async {
    return AppSettings.fromJson(const <String, dynamic>{
      'mediaSources': <Object>[],
      'searchProviders': <Object>[],
      'doubanAccount': <String, Object>{'enabled': false},
      'homeModules': <Object>[],
    });
  }
}
