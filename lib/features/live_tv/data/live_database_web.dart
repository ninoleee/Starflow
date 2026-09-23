import 'package:sembast_web/sembast_web.dart';

Future<Database> openLiveDatabase() =>
    databaseFactoryWeb.openDatabase('starflow-live-tv-v2');
