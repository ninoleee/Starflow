import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openNasMediaIndexDatabase() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final directory = Directory(
    p.join(supportDirectory.path, 'starflow-db'),
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return databaseFactoryIo.openDatabase(
    p.join(directory.path, 'nas_metadata_index.db'),
    version: 1,
  );
}
