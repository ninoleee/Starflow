import 'dart:convert';
import 'dart:typed_data';

import '../domain/live_models.dart';
import 'live_playlist_parser.dart';

const liveBackupMaxBytes = 32 * 1024 * 1024;
const liveBackupStores = {
  'sources',
  'channels',
  'preferences',
  'channelOwners',
  'epg',
  'epgLogos',
  'meta',
};

/// A validated database snapshot. Cached guide rows are included for offline
/// restore; no application settings or runtime playback resources are included.
class LiveBackup {
  LiveBackup(this.stores);
  final Map<String, Map<String, Object?>> stores;

  Uint8List encode() {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({
      'format': 'starflow-live-tv',
      'version': 1,
      'stores': stores,
    })));
    if (bytes.length > liveBackupMaxBytes) {
      throw const FormatException('直播备份超过 32 MiB');
    }
    return bytes;
  }

  static LiveBackup decode(Uint8List bytes) {
    try {
      if (bytes.length > liveBackupMaxBytes) throw const FormatException();
      final root = jsonDecode(utf8.decode(bytes)) as Map;
      if (root['format'] != 'starflow-live-tv' || root['version'] != 1) {
        throw const FormatException();
      }
      final raw = root['stores'] as Map;
      if (raw.keys.toSet().difference(liveBackupStores).isNotEmpty ||
          !raw.keys.toSet().containsAll(liveBackupStores)) {
        throw const FormatException();
      }
      final stores = <String, Map<String, Object?>>{
        for (final name in liveBackupStores)
          name: Map<String, Object?>.from(raw[name] as Map),
      };
      Map<String, dynamic> row(Object? value) =>
          Map<String, dynamic>.from(value as Map);
      void check(bool valid) {
        if (!valid) throw const FormatException();
      }

      void url(String value) => check(value.isEmpty || isLiveHttpUrl(value));
      final sources = stores['sources']!;
      check(sources.length <= 1000);
      for (final entry in sources.entries) {
        final source = LiveSource.fromJson(row(entry.value));
        check(entry.key.isNotEmpty &&
            source.id == entry.key &&
            source.name.trim().isNotEmpty);
        url(source.url);
        url(source.epgUrl);
        url(source.discoveredEpgUrl);
      }
      final channels = stores['channels']!;
      check(channels.length <= 100000);
      for (final entry in channels.entries) {
        final c = LiveChannel.fromJson(row(entry.value));
        check(c.id == entry.key &&
            c.id.isNotEmpty &&
            sources.containsKey(c.sourceId) &&
            c.name.isNotEmpty &&
            c.lines.isNotEmpty &&
            c.lines.length <= liveMaxLinesPerChannel);
        url(c.logo);
        for (final line in c.lines) {
          check(isLiveHttpUrl(line.url));
          for (final header in line.headers.entries) {
            check(
                RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(header.key) &&
                    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(header.value));
          }
        }
      }
      for (final entry in stores['channelOwners']!.entries) {
        check(entry.key.isNotEmpty && sources.containsKey(entry.value));
        if (channels.containsKey(entry.key)) {
          check(row(channels[entry.key])['sourceId'] == entry.value);
        }
      }
      for (final entry in stores['preferences']!.entries) {
        final value = row(entry.value);
        final owner = value['sourceId'];
        check(sources.containsKey(owner) &&
            stores['channelOwners']![entry.key] == owner);
        final preference = LivePreference.fromJson(value);
        check(preference.line >= 0 && preference.order >= -1);
        url(preference.logo);
      }
      for (final value in stores['epg']!.values) {
        final j = row(value);
        check(sources.containsKey(j['sourceId']));
        final p = LiveProgramme.fromJson(j);
        check(p.end.isAfter(p.start));
      }
      for (final value in stores['epgLogos']!.values) {
        final j = row(value);
        check(sources.containsKey(j['sourceId']) && j['channel'] is String);
        url(j['logo'] as String);
      }
      final meta = stores['meta']!;
      check(meta.keys.every((k) =>
          k == 'engine' || k == 'lastChannel' || k == 'groupPreferences'));
      check(meta['engine'] == null ||
          const {'mpv', 'exo'}.contains(meta['engine']));
      final groupPreferences = meta['groupPreferences'];
      if (groupPreferences != null) {
        check(groupPreferences is String);
        final parsed = parseLiveGroupPreferences(groupPreferences as String);
        check(parsed.length <= 10000);
        for (final group in parsed.keys) {
          check(group.isNotEmpty && parsed[group]!.order >= -1);
        }
      }
      final last = meta['lastChannel'];
      check(last == null ||
          last == '' ||
          stores['channelOwners']!.containsKey(last));
      return LiveBackup(stores);
    } catch (_) {
      throw const FormatException('直播备份格式、版本或内容无效');
    }
  }
}

enum LiveBackupImportMode { merge, replace }
