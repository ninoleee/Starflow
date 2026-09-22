import 'dart:async';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/core/network/bounded_http_request.dart';
import 'package:starflow/core/network/network_failure.dart';
import 'package:starflow/core/network/starflow_http_transport.dart';
import '../domain/live_models.dart';
import 'live_database.dart';
import 'live_epg_parser.dart';
import 'live_playlist_parser.dart';
import 'live_backup.dart';

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  final repository = LiveRepository(
      openDatabase: openLiveDatabase, client: createStarflowTransportClient());
  ref.onDispose(repository.dispose);
  return repository;
});
final liveSnapshotProvider = StreamProvider<LiveSnapshot>(
    (ref) => ref.watch(liveRepositoryProvider).watch());
final liveGuideProvider = FutureProvider.autoDispose
    .family<List<LiveProgramme>, String>((ref, channelId) async {
  final snapshot = await ref.watch(liveSnapshotProvider.future);
  final channel = snapshot.channels.where((c) => c.id == channelId).firstOrNull;
  if (channel == null) return [];
  return ref
      .read(liveRepositoryProvider)
      .guide(channel.sourceId, snapshot.epgId(channel));
});

final liveNowNextProvider =
    FutureProvider.autoDispose<Map<String, List<LiveProgramme>>>((ref) async {
  await ref.watch(liveSnapshotProvider.future);
  return ref.read(liveRepositoryProvider).nowNext();
});

class LiveRepository {
  LiveRepository(
      {required Future<Database> Function() openDatabase, required this.client})
      : _opener = openDatabase;
  final Future<Database> Function() _opener;
  final http.Client client;
  Future<Database>? _db;
  final _changes = StreamController<void>.broadcast();
  final _sources = stringMapStoreFactory.store('sources');
  final _channels = stringMapStoreFactory.store('channels');
  final _prefs = stringMapStoreFactory.store('preferences');
  final _epg = stringMapStoreFactory.store('epg');
  final _logos = stringMapStoreFactory.store('epgLogos');
  final _owners = StoreRef<String, String>('channelOwners');
  final _meta = StoreRef<String, String>('meta');
  Future<void> _tail = Future.value();
  final Map<(String, int), Future<void>> _refreshing = {};
  final Map<String, int> _versions = {};
  final Map<String, DateTime> _attempts = {};
  int _backupEpoch = 0;
  bool _disposed = false;
  Future<Database> get database => _db ??= _opener();
  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  Future<T> _write<T>(Future<T> Function(Database) action) {
    final result = _tail.then((_) async {
      if (_disposed) throw StateError('Repository closed');
      final value = await action(await database);
      _notify();
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Stream<LiveSnapshot> watch() async* {
    // Subscribe before loading to avoid missing a concurrent write.
    final updates = StreamIterator(_changes.stream);
    var next = updates.moveNext();
    try {
      yield await load();
      while (await next) {
        next = updates.moveNext();
        yield await load();
      }
    } finally {
      await updates.cancel();
    }
  }

  Future<LiveSnapshot> load() async {
    final db = await database;
    return db.transaction((txn) async => LiveSnapshot(
        sources: (await _sources.find(txn))
            .map((e) => LiveSource.fromJson(e.value))
            .toList(),
        channels: (await _channels.find(txn,
                finder: Finder(
                    sortOrders: [SortOrder('sourceId'), SortOrder('ordinal')])))
            .map((e) => LiveChannel.fromJson(e.value))
            .toList(),
        preferences: {
          for (final e in await _prefs.find(txn))
            e.key: LivePreference.fromJson(e.value)
        },
        groupPreferences: decodeLiveGroupPreferences(
            await _meta.record('groupPreferences').get(txn)),
        lastChannel: await _meta.record('lastChannel').get(txn) ?? '',
        engine: await _meta.record('engine').get(txn) ?? 'mpv'));
  }

  Future<Uint8List> exportBackup() =>
      _write((db) => db.transaction((txn) async {
            final stores = <String, Map<String, Object?>>{};
            for (final name in liveBackupStores) {
              final store = StoreRef<String, Object?>(name);
              stores[name] = {
                for (final row in await store.find(txn)) row.key: row.value
              };
            }
            // Upgrade historical ownership in the exported snapshot, not the live DB.
            for (final entry in stores['channels']!.entries) {
              final source = (entry.value as Map)['sourceId'] as String;
              stores['channelOwners']![entry.key] = source;
              final preference = stores['preferences']![entry.key];
              if (preference is Map) {
                stores['preferences']![entry.key] = {
                  ...preference,
                  'sourceId': source
                };
              }
            }
            return LiveBackup.decode(LiveBackup(stores).encode()).encode();
          }));

  Future<void> importBackup(Uint8List bytes, LiveBackupImportMode mode) async {
    final backup = await compute(LiveBackup.decode, bytes);
    // Invalidate downloads before entering the write queue; neither replace nor
    // merge may receive a stale refresh commit after restoring the snapshot.
    _backupEpoch++;
    _attempts.clear();
    await _write((db) => db.transaction((txn) async {
          final existingSources =
              (await _sources.find(txn)).map((e) => e.key).toSet();
          final incomingSources = backup.stores['sources']!.keys.toSet();
          final accepted = mode == LiveBackupImportMode.replace
              ? incomingSources
              : incomingSources.difference(existingSources);
          // Merge preserves whole existing sources, avoiding partial ID collisions.
          for (final name in [
            'channels',
            'channelOwners',
            'preferences',
            'epg',
            'epgLogos'
          ]) {
            final store = StoreRef<String, Object?>(name);
            for (final entry in backup.stores[name]!.entries) {
              final owner = name == 'channelOwners'
                  ? entry.value
                  : (entry.value as Map)['sourceId'];
              if (mode == LiveBackupImportMode.merge &&
                  accepted.contains(owner) &&
                  await store.record(entry.key).exists(txn)) {
                throw const FormatException('直播备份频道身份冲突');
              }
            }
          }
          for (final name in liveBackupStores) {
            final store = StoreRef<String, Object?>(name);
            if (mode == LiveBackupImportMode.replace) await store.delete(txn);
            for (final entry in backup.stores[name]!.entries) {
              final owner = name == 'sources'
                  ? entry.key
                  : name == 'channelOwners'
                      ? entry.value
                      : name == 'meta'
                          ? null
                          : (entry.value as Map)['sourceId'];
              if (mode == LiveBackupImportMode.replace ||
                  accepted.contains(owner)) {
                await store.record(entry.key).put(txn, entry.value);
              }
            }
          }
          if (mode == LiveBackupImportMode.merge) {
            final incoming = backup.stores['meta']!['groupPreferences'];
            if (incoming is String) {
              final acceptedGroups = <String>{};
              for (final entry in backup.stores['channels']!.entries) {
                final channel = Map<String, dynamic>.from(entry.value as Map);
                if (!accepted.contains(channel['sourceId'])) continue;
                final rawPreference = backup.stores['preferences']![entry.key];
                final preference = rawPreference is Map
                    ? LivePreference.fromJson(
                        Map<String, dynamic>.from(rawPreference))
                    : const LivePreference();
                final group = preference.group.isEmpty
                    ? channel['group'] as String? ?? ''
                    : preference.group;
                if (group.isNotEmpty) acceptedGroups.add(group);
              }
              final current = decodeLiveGroupPreferences(
                  await _meta.record('groupPreferences').get(txn));
              final imported = parseLiveGroupPreferences(incoming);
              var changed = false;
              for (final entry in imported.entries) {
                if (current.containsKey(entry.key) ||
                    !acceptedGroups.contains(entry.key)) {
                  continue;
                }
                current[entry.key] = entry.value;
                changed = true;
              }
              if (changed) {
                await _meta
                    .record('groupPreferences')
                    .put(txn, encodeLiveGroupPreferences(current));
              }
            }
          }
        }));
  }

  Future<void> saveSource(LiveSource source, {Uint8List? imported}) async {
    if (source.id.isEmpty ||
        source.name.trim().isEmpty ||
        (imported == null &&
            source.url.isNotEmpty &&
            !isLiveHttpUrl(source.url)) ||
        (source.epgUrl.isNotEmpty && !isLiveHttpUrl(source.epgUrl))) {
      throw const FormatException('请检查名称与 HTTP/HTTPS 地址');
    }
    if (imported != null && imported.length > livePlaylistMaxBytes) {
      throw const FormatException('频道列表超过 8 MiB');
    }
    _versions[source.id] = (_versions[source.id] ?? 0) + 1;
    final version = _versions[source.id]!;
    _attempts.remove(source.id);
    await _write((db) async {
      final parsed = imported == null
          ? null
          : await compute(
              _parsePlaylistBytes, (imported, source.id, source.url));
      return db.transaction((txn) async {
        if ((_versions[source.id] ?? 0) != version) return;
        final previous = await _sources.record(source.id).get(txn);
        final discoveredEpgUrl = parsed?.epgUrl ??
            (previous?['url'] == source.url
                ? (previous?['discoveredEpgUrl'] ?? source.discoveredEpgUrl)
                : '');
        final endpointChanged = previous != null &&
            (previous['url'] != source.url ||
                previous['epgUrl'] != source.epgUrl);
        final discoveredEpgChanged = source.epgUrl.isEmpty &&
            previous?['discoveredEpgUrl'] != discoveredEpgUrl;
        await _sources.record(source.id).put(txn, {
          ...source.toJson(),
          if (previous != null) 'updatedAt': previous['updatedAt'] ?? 0,
          if (previous != null) 'epgUpdatedAt': previous['epgUpdatedAt'] ?? 0,
          if (endpointChanged) 'updatedAt': 0,
          if (endpointChanged || discoveredEpgChanged) 'epgUpdatedAt': 0,
          if (parsed != null)
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          'discoveredEpgUrl': discoveredEpgUrl,
        });
        if (parsed != null) {
          await _replaceChannels(txn, source.id, parsed.channels);
        }
      });
    });
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    _versions[id] = (_versions[id] ?? 0) + 1;
    _attempts.remove(id);
    await _write((db) => db.transaction((txn) async {
          final record = _sources.record(id);
          if (await record.exists(txn)) {
            await record.update(txn, {'enabled': enabled});
          }
        }));
  }

  Future<void> removeSource(String id) async {
    _versions[id] = (_versions[id] ?? 0) + 1;
    _attempts.remove(id);
    await _write((db) => db.transaction((txn) async {
          final channels = await _channels.find(txn,
              finder: Finder(filter: Filter.equals('sourceId', id)));
          final owned = {
            for (final c in channels) c.key,
            for (final owner in await _owners.find(txn,
                finder: Finder(filter: Filter.equals(Field.value, id))))
              owner.key,
            for (final p in await _prefs.find(txn,
                finder: Finder(filter: Filter.equals('sourceId', id))))
              p.key,
          };
          for (final channelId in owned) {
            await _prefs.record(channelId).delete(txn);
            await _owners.record(channelId).delete(txn);
          }
          if (owned.contains(await _meta.record('lastChannel').get(txn))) {
            await _meta.record('lastChannel').delete(txn);
          }
          await _sources.record(id).delete(txn);
          await _channels.delete(txn,
              finder: Finder(filter: Filter.equals('sourceId', id)));
          await _epg.delete(txn,
              finder: Finder(filter: Filter.equals('sourceId', id)));
          await _logos.delete(txn,
              finder: Finder(filter: Filter.equals('sourceId', id)));
        }));
  }

  Future<void> preference(String id, Map<String, dynamic> patch) =>
      _write((db) => db.transaction((txn) async {
            final channel = await _channels.record(id).get(txn);
            final sourceId = channel?['sourceId'] as String? ??
                await _owners.record(id).get(txn);
            if (sourceId == null ||
                await _sources.record(sourceId).get(txn) == null) {
              return;
            }
            final old = await _prefs.record(id).get(txn) ?? {};
            await _prefs.record(id).put(txn, {
              ...LivePreference.fromJson(old).patch(patch).toJson(),
              'sourceId': sourceId,
            });
            await _owners.record(id).put(txn, sourceId);
          }));
  Future<void> remember(String id, int line) =>
      _write((db) => db.transaction((txn) async {
            final channel = await _channels.record(id).get(txn);
            if (channel == null) return;
            final lines = channel['lines'] as List;
            if (lines.isEmpty) return;
            await _meta.record('lastChannel').put(txn, id);
            final old = await _prefs.record(id).get(txn) ?? {};
            await _prefs.record(id).put(txn, {
              ...LivePreference.fromJson(old)
                  .patch({'line': line.clamp(0, lines.length - 1)}).toJson(),
              'sourceId': channel['sourceId'],
            });
            await _owners.record(id).put(txn, channel['sourceId'] as String);
          }));
  Future<void> setEngine(String engine) => _write((db) async {
        await _meta.record('engine').put(db, engine == 'exo' ? 'exo' : 'mpv');
      });
  Future<void> setGroupHidden(String group, bool hidden) =>
      _write((db) => db.transaction((txn) async {
            if (group.isEmpty) return;
            final preferences = decodeLiveGroupPreferences(
                await _meta.record('groupPreferences').get(txn));
            preferences[group] =
                (preferences[group] ?? const LiveGroupPreference())
                    .patch({'hidden': hidden});
            await _meta
                .record('groupPreferences')
                .put(txn, encodeLiveGroupPreferences(preferences));
          }));
  Future<void> moveGroup(String group, int delta) =>
      _write((db) => db.transaction((txn) async {
            if (group.isEmpty) return;
            final snapshot = await loadOutsideTransaction(txn);
            final groups = snapshot.groups(includeHidden: true);
            final index = groups.indexOf(group);
            if (index < 0) return;
            final target = (index + delta).clamp(0, groups.length - 1);
            if (target == index) return;
            groups.insert(target, groups.removeAt(index));
            final preferences = {...snapshot.groupPreferences};
            for (var i = 0; i < groups.length; i++) {
              preferences[groups[i]] =
                  (preferences[groups[i]] ?? const LiveGroupPreference())
                      .patch({'order': i});
            }
            await _meta
                .record('groupPreferences')
                .put(txn, encodeLiveGroupPreferences(preferences));
          }));
  Future<void> move(String id, int delta) =>
      _write((db) => db.transaction((txn) async {
            final snap = await loadOutsideTransaction(txn);
            final list = snap.visible(includeHidden: true);
            final index = list.indexWhere((c) => c.id == id);
            if (index < 0) return;
            final target = (index + delta).clamp(0, list.length - 1);
            list.insert(target, list.removeAt(index));
            for (var i = 0; i < list.length; i++) {
              await _prefs.record(list[i].id).put(txn, {
                ...snap.preference(list[i]).patch({'order': i}).toJson(),
                'sourceId': list[i].sourceId,
              });
              await _owners.record(list[i].id).put(txn, list[i].sourceId);
            }
          }));
  Future<LiveSnapshot> loadOutsideTransaction(DatabaseClient db) async =>
      LiveSnapshot(
          sources: (await _sources.find(db))
              .map((e) => LiveSource.fromJson(e.value))
              .toList(),
          channels: (await _channels.find(db,
                  finder: Finder(sortOrders: [
                    SortOrder('sourceId'),
                    SortOrder('ordinal')
                  ])))
              .map((e) => LiveChannel.fromJson(e.value))
              .toList(),
          preferences: {
            for (final e in await _prefs.find(db))
              e.key: LivePreference.fromJson(e.value)
          },
          groupPreferences: decodeLiveGroupPreferences(
              await _meta.record('groupPreferences').get(db)));
  Future<void> _replaceChannels(
      DatabaseClient db, String sourceId, List<LiveChannel> channels) async {
    final previous = await _channels.find(db,
        finder: Finder(filter: Filter.equals('sourceId', sourceId)));
    final oldById = {for (final c in previous) c.key: c.value};
    // Migrate legacy IDs when a unique upstream tvg-id survives a rename/regroup.
    // Legacy rows lack identity; their epgId is usable only for an explicit
    // incoming tvg-id and a one-to-one match. Never migrate by display name.
    final oldIdentity = <String, List<String>>{};
    final newIdentity = <String, int>{};
    for (final c in previous) {
      final key =
          c.value['identity'] as String? ?? c.value['epgId'] as String? ?? '';
      if (key.isNotEmpty) (oldIdentity[key] ??= []).add(c.key);
    }
    for (final c in channels) {
      newIdentity.update(c.identity, (n) => n + 1, ifAbsent: () => 1);
    }
    // Retain ownership when an upstream channel disappears, including old DBs.
    for (final c in previous) {
      await _owners.record(c.key).put(db, sourceId);
    }
    final logos = {
      for (final e in await _logos.find(db,
          finder: Finder(filter: Filter.equals('sourceId', sourceId))))
        e.value['channel']: e.value['logo']
    };
    await _channels.delete(db,
        finder: Finder(filter: Filter.equals('sourceId', sourceId)));
    for (var i = 0; i < channels.length; i++) {
      final incoming = channels[i];
      final candidates = oldIdentity[incoming.identity] ?? [];
      final previousId = oldById.containsKey(incoming.id)
          ? incoming.id
          : incoming.identity.isNotEmpty &&
                  newIdentity[incoming.identity] == 1 &&
                  candidates.length == 1
              ? candidates.single
              : incoming.id;
      final c = incoming;
      if (previousId != c.id) {
        final preference = await _prefs.record(previousId).get(db);
        if (preference != null && !await _prefs.record(c.id).exists(db)) {
          await _prefs
              .record(c.id)
              .put(db, {...preference, 'sourceId': sourceId});
        }
        if (await _meta.record('lastChannel').get(db) == previousId) {
          await _meta.record('lastChannel').put(db, c.id);
        }
        await _prefs.record(previousId).delete(db);
      }
      final old = oldById[previousId];
      final cachedLogo = logos[c.epgId] ??
          (old != null && old['epgId'] == c.epgId ? old['logo'] : null) ??
          '';
      await _channels.record(c.id).put(db, {
        ...c.toJson(),
        'playlistLogo': c.logo,
        'logo': c.logo.isEmpty ? cachedLogo : c.logo,
        'ordinal': i,
      });
      await _owners.record(c.id).put(db, sourceId);
    }
  }

  Future<Uint8List> _download(String url, int maxBytes) async {
    if (!isLiveHttpUrl(url)) throw const FormatException('只支持 HTTP/HTTPS 地址');
    // Deliberately bypass request-path logging: IPTV credentials may be path segments.
    final http.Response response;
    try {
      response = await sendBoundedRequest(client, 'GET', Uri.parse(url),
          timeout: const Duration(seconds: 30), maxBytes: maxBytes);
    } catch (error) {
      final category = error is http.ClientException &&
              error.message == 'Response exceeds byte limit'
          ? 'sizeLimit'
          : classifyNetworkFailure(error).kind.name;
      throw _LiveDownloadFailure(category);
    }
    if (response.statusCode != 200) {
      throw _LiveDownloadFailure('httpStatus', status: response.statusCode);
    }
    return response.bodyBytes;
  }

  Future<void> refresh(String id) {
    final key = ('$id:$_backupEpoch', _versions[id] ?? 0);
    final epoch = _backupEpoch;
    return _refreshing[key] ??= _refresh(id, key.$2, epoch).whenComplete(() {
      _refreshing.remove(key);
    });
  }

  bool _current(String id, int version) =>
      !_disposed && (_versions[id] ?? 0) == version;

  Future<void> _refresh(String id, int version, int epoch) async {
    await _tail;
    if (!_current(id, version) || epoch != _backupEpoch) return;
    final source = (await load()).sources.where((s) => s.id == id).firstOrNull;
    if (source == null || !source.enabled || !_current(id, version)) return;
    _attempts[id] = DateTime.now();
    var stage = 'playlist';
    try {
      var epgUrl = source.effectiveEpgUrl;
      if (source.url.isNotEmpty) {
        final playlist = await compute(_parsePlaylistBytes, (
          await _download(source.url, livePlaylistMaxBytes),
          id,
          source.url
        ));
        if (!_current(id, version) || epoch != _backupEpoch) return;
        epgUrl = source.epgUrl.isEmpty ? playlist.epgUrl : source.epgUrl;
        await _write((db) => db.transaction((txn) async {
              if (epoch != _backupEpoch ||
                  (_versions[id] ?? 0) != version ||
                  await _sources.record(id).get(txn) == null) {
                return;
              }
              await _replaceChannels(txn, id, playlist.channels);
              await _sources.record(id).put(txn, {
                ...source.toJson(),
                'discoveredEpgUrl': playlist.epgUrl,
                if (epgUrl != source.effectiveEpgUrl) 'epgUpdatedAt': 0,
                'updatedAt': DateTime.now().millisecondsSinceEpoch
              });
            }));
      }
      if (epgUrl.isNotEmpty && _current(id, version) && epoch == _backupEpoch) {
        stage = 'epg';
        final epg = await compute(
            _parseEpgBytes, await _download(epgUrl, livePlaylistMaxBytes));
        if (!_current(id, version) || epoch != _backupEpoch) return;
        await _write((db) => db.transaction((txn) async {
              if (epoch != _backupEpoch || (_versions[id] ?? 0) != version) {
                return;
              }
              final current = await _sources.record(id).get(txn);
              if (current == null) return;
              await _epg.delete(txn,
                  finder: Finder(filter: Filter.equals('sourceId', id)));
              for (final p in epg.programmes) {
                await _epg
                    .record(liveId(
                        '${id.length}:$id${p.channel.length}:${p.channel}:${p.start.millisecondsSinceEpoch}'))
                    .put(txn, {...p.toJson(), 'sourceId': id});
              }
              await _logos.delete(txn,
                  finder: Finder(filter: Filter.equals('sourceId', id)));
              for (final logo in epg.logos.entries) {
                if (!isLiveHttpUrl(logo.value)) continue;
                await _logos.record(liveId('${id.length}:$id${logo.key}')).put(
                    txn,
                    {'sourceId': id, 'channel': logo.key, 'logo': logo.value});
              }
              for (final entry in await _channels.find(txn,
                  finder: Finder(filter: Filter.equals('sourceId', id)))) {
                final logo = epg.logos[entry.value['epgId']];
                if ((entry.value['playlistLogo'] as String? ?? '').isEmpty) {
                  await _channels.record(entry.key).put(txn, {
                    ...entry.value,
                    'logo': logo != null && isLiveHttpUrl(logo) ? logo : '',
                  });
                }
              }
              await _sources.record(id).put(txn, {
                ...current,
                'epgUpdatedAt': DateTime.now().millisecondsSinceEpoch
              });
            }));
      }
      if (!_current(id, version) || epoch != _backupEpoch) return;
      appLogInfo('live.refresh', 'Subscription refreshed',
          fields: {'sourceId': liveId(id)});
    } catch (error) {
      if (!_current(id, version) || epoch != _backupEpoch) return;
      appLogWarning(
          'live.refresh', 'Subscription refresh failed; cache retained',
          fields: {
            'sourceId': liveId(id),
            'stage': stage,
            'errorCategory': error is _LiveDownloadFailure
                ? error.category
                : error is FormatException
                    ? 'format'
                    : 'unknown',
            if (error is _LiveDownloadFailure && error.status != null)
              'httpStatus': error.status,
          });
      if (error is FormatException) {
        throw const FormatException('直播数据格式无效，已保留缓存');
      }
      if (error is _LiveDownloadFailure && error.status != null) {
        throw StateError(
            '${stage == 'epg' ? '节目单' : '频道列表'}更新失败（HTTP ${error.status}），已保留缓存');
      }
      throw StateError('直播更新失败，已保留缓存');
    }
  }

  Future<void> refreshDue({bool Function()? canContinue}) async {
    for (final s in (await load()).sources) {
      if (_disposed || canContinue?.call() == false) return;
      final now = DateTime.now();
      if (!s.enabled ||
          (s.url.isEmpty && s.effectiveEpgUrl.isEmpty) ||
          now.difference(_attempts[s.id] ?? DateTime(1970)) <
              const Duration(minutes: 5)) {
        continue;
      }
      final ttl = Duration(hours: s.refreshHours).inMilliseconds;
      final playlistDue =
          s.url.isNotEmpty && now.millisecondsSinceEpoch - s.updatedAt >= ttl;
      final epgDue = s.effectiveEpgUrl.isNotEmpty &&
          now.millisecondsSinceEpoch - s.epgUpdatedAt >= ttl;
      if (!playlistDue && !epgDue) {
        continue;
      }
      try {
        await refresh(s.id);
      } catch (_) {/* Cached channels remain available. */}
    }
  }

  Future<List<LiveProgramme>> guide(String sourceId, String channel) async {
    if (channel.isEmpty) return [];
    final entries = await _epg.find(await database,
        finder: Finder(
            filter: Filter.and([
              Filter.equals('sourceId', sourceId),
              Filter.equals('channel', channel),
              Filter.greaterThan(
                  'end',
                  DateTime.now()
                      .subtract(const Duration(days: 1))
                      .millisecondsSinceEpoch),
            ]),
            sortOrders: [SortOrder('start')],
            limit: 1000));
    return entries.map((e) => LiveProgramme.fromJson(e.value)).toList();
  }

  Future<Map<String, List<LiveProgramme>>> nowNext() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final entries = await _epg.find(await database,
        finder: Finder(
            filter: Filter.and([
              Filter.greaterThan('end', now),
              Filter.lessThanOrEquals(
                  'start', now + const Duration(days: 1).inMilliseconds),
            ]),
            sortOrders: [SortOrder('start')]));
    final result = <String, List<LiveProgramme>>{};
    for (final e in entries) {
      final key = '${e.value['sourceId']}|${e.value['channel']}';
      final programmes = result.putIfAbsent(key, () => []);
      if (programmes.length < 2) {
        programmes.add(LiveProgramme.fromJson(e.value));
      }
    }
    return result;
  }

  void dispose() {
    _disposed = true;
    client.close();
    unawaited(_changes.close());
    unawaited(_tail.then((_) async {
      await (await _db)?.close();
    }));
  }
}

class _LiveDownloadFailure implements Exception {
  const _LiveDownloadFailure(this.category, {this.status});
  final String category;
  final int? status;
}

LivePlaylist _parsePlaylistBytes((Uint8List, String, String) input) {
  if (input.$1.length > livePlaylistMaxBytes) {
    throw const FormatException('频道列表超过 8 MiB');
  }
  return parseLivePlaylist(decodeLiveText(input.$1), input.$2,
      baseUrl: input.$3);
}

LiveEpg _parseEpgBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 31 && bytes[1] == 139) {
    if (bytes.length < 18) throw const FormatException('Gzip 文件不完整');
    if (bytes[2] != 8 || bytes[3] & 0xe0 != 0) {
      throw const FormatException('Gzip 文件头无效');
    }
    final footer = ByteData.sublistView(bytes, bytes.length - 8);
    final crc = footer.getUint32(0, Endian.little);
    final size = footer.getUint32(4, Endian.little);
    if (size > liveEpgMaxBytes) {
      throw const FormatException('节目单解压超过 32 MiB');
    }
    final output = _BoundedEpgOutput();
    const GZipDecoderWeb()
        .decodeStream(InputMemoryStream(bytes), output, verify: true);
    bytes = output.getBytes();
    if (size != bytes.length || getCrc32(bytes) != crc) {
      throw const FormatException('Gzip 校验失败');
    }
  }
  return parseLiveEpg(decodeLiveText(bytes));
}

class _BoundedEpgOutput extends OutputMemoryStream {
  void _check(int count) {
    if (length + count > liveEpgMaxBytes) {
      throw const FormatException('节目单解压超过 32 MiB');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }
}
