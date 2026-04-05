import 'package:sembast_web/sembast_web.dart';

Future<Database>? _database;

Future<Database> openNasMediaIndexDatabase() async {
  return _database ??=
      databaseFactoryWeb.openDatabase('starflow-nas-metadata-index');
}
