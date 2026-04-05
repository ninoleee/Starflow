import 'package:sembast/sembast_memory.dart';

Future<Database>? _database;

Future<Database> openNasMediaIndexDatabase() async {
  return _database ??= databaseFactoryMemory.openDatabase('starflow-nas-index');
}
