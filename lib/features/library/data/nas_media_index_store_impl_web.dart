import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

Database? _database;

Future<Database> openNasMediaIndexDatabase() async {
  return _database ??=
      databaseFactoryWeb.openDatabase('starflow-nas-metadata-index');
}
