import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openLiveDatabase() async {
  final directory = Directory(
      p.join((await getApplicationSupportDirectory()).path, 'starflow-db'));
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(p.join(directory.path, 'live_tv.db'));
}
