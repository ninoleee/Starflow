import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';

Database? _database;

Future<Database> openNasMediaIndexDatabase() async {
  return _database ??= databaseFactoryMemory.openDatabase('starflow-nas-index');
}
