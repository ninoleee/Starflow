import 'package:http/http.dart' as http;
import 'package:starflow/features/update/domain/app_update.dart';
import 'package:starflow/features/update/domain/update_source.dart';

class UpdatePackageDownloader {
  UpdatePackageDownloader({
    http.Client? client,
    http.Client Function()? clientFactory,
    Object? directory,
  });

  static const int maxPackageBytes = 512 * 1024 * 1024;

  Future<String> download(
    UpdateArtifact artifact, {
    required void Function(int) onProgress,
    required void Function() onVerifying,
    UpdateSource? source,
  }) async {
    throw const UpdateFailure(
        'unsupported', 'APK downloads require an IO platform.');
  }

  void cancel() {}

  Future<void> dispose() async {}
}
