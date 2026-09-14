import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/logging/app_logger.dart';
import 'package:starflow/features/search/data/search_preferences_repository.dart';
import 'package:starflow/features/settings/data/webdav_sync_service.dart';

final favoriteAutoSyncProvider = Provider<FavoriteAutoSync>((ref) {
  final sync = FavoriteAutoSync(
    repository: ref.watch(searchPreferencesRepositoryProvider),
    preferences: ref.watch(webDavSyncPreferencesProvider),
    service: ref.watch(webDavSyncServiceProvider),
  );
  sync.start();
  ref.onDispose(sync.dispose);
  return sync;
});

enum FavoriteSyncTrigger { firstEntry, membershipChange, manual, requested }

class FavoriteAutoSync extends ChangeNotifier with WidgetsBindingObserver {
  FavoriteAutoSync({
    required this.repository,
    required this.preferences,
    required this.service,
  });

  final SearchPreferencesRepository repository;
  final WebDavSyncPreferences preferences;
  final WebDavSyncService service;
  StreamSubscription<void>? _changes;
  StreamSubscription<void>? _configChanges;
  WebDavSyncConfig? _config;
  Future<void>? _configurationLoad;
  Completer<void>? _activeSync;
  int _epoch = 0;
  int _loadRevision = 0;
  bool _foreground = true;
  bool _disposed = false;
  bool _hasEnteredFavorites = false;
  bool _membershipChangedDuringSync = false;
  String status = '收藏自动同步未开启';
  DateTime? lastSuccess;
  bool get enabled => _config?.autoFavorites ?? false;
  bool get running => _activeSync != null;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _changes = repository.favoriteMembershipChanges.listen((_) {
      if (_disposed || !_foreground) return;
      if (running) {
        _membershipChangedDuringSync = true;
      } else {
        unawaited(synchronize(trigger: FavoriteSyncTrigger.membershipChange));
      }
    });
    _configChanges = preferences.changes.listen((_) => unawaited(reload()));
    unawaited(reload());
  }

  Future<void> onFavoritesPageEntered() async {
    if (_disposed || _hasEnteredFavorites) return;
    // Consume the entry before awaiting, including disabled or failed attempts.
    _hasEnteredFavorites = true;
    await synchronize(trigger: FavoriteSyncTrigger.firstEntry);
  }

  Future<void> reload() {
    final future = _loadConfiguration();
    _configurationLoad = future;
    return future;
  }

  Future<void> _loadConfiguration() async {
    final revision = ++_loadRevision;
    _epoch++;
    _membershipChangedDuringSync = false;
    _config = null;
    lastSuccess = null;
    try {
      final config = await preferences.load();
      if (_disposed || revision != _loadRevision) return;
      _config = config;
      status = enabled ? '收藏等待同步' : '收藏自动同步未开启';
    } catch (_) {
      if (_disposed || revision != _loadRevision) return;
      status = '读取收藏同步设置失败，请检查地址并重新保存';
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _epoch++;
      _membershipChangedDuringSync = false;
    }
  }

  Future<void> synchronize({
    bool manual = false,
    FavoriteSyncTrigger trigger = FavoriteSyncTrigger.requested,
  }) async {
    if (_disposed) return;
    await _configurationLoad;
    if (_disposed || !_foreground || (!manual && !enabled)) return;
    final active = _activeSync;
    if (active != null) return active.future;
    final config = _config;
    if (config == null || config.url.trim().isEmpty) {
      if (manual) {
        status = '请先在设置中保存 WebDAV 地址和账号';
        notifyListeners();
      }
      return;
    }
    final completion = Completer<void>();
    _activeSync = completion;
    _membershipChangedDuringSync = false;
    status = '收藏正在同步';
    notifyListeners();
    final logFields = <String, Object?>{
      'trigger': (manual ? FavoriteSyncTrigger.manual : trigger).name,
    };
    appLogInfo('sync.favorites', 'Favorite sync started', fields: logFields);
    var phase = 'read';
    var outcome = 'cancelled';
    final epoch = _epoch;
    bool current() => !_disposed && _foreground && epoch == _epoch;
    try {
      phase = 'device';
      final deviceId = await repository.loadFavoriteSyncDeviceId();
      if (!current()) return;
      phase = 'read';
      final remote = await service.readFavorites(config, deviceId: deviceId);
      if (!current()) return;
      phase = 'merge';
      final local = await repository.loadFavoriteSyncDocument();
      if (!current()) return;
      var merged = local.mergeAll(remote.documents);
      if (merged.entries.isNotEmpty &&
          merged.encodeForSync() != remote.deviceDocument?.encodeForSync()) {
        if (remote.deviceDocument == null) {
          phase = 'createDirectory';
          await service.ensureDirectory(config);
          if (!current()) return;
        }
        phase = 'write';
        await service.writeFavorites(config, merged, deviceId: deviceId);
        if (!current()) return;
        phase = 'verify';
        merged = await service.verifyFavoritesWrite(config, merged,
            deviceId: deviceId);
        if (!current()) return;
      }
      phase = 'apply';
      await repository.mergeFavoriteSyncDocument(merged, shouldApply: current);
      if (!current()) return;
      lastSuccess = DateTime.now();
      status = '收藏已同步';
      outcome = 'success';
      appLogInfo('sync.favorites', 'Favorite sync completed', fields: {
        ...logFields,
        'outcome': outcome,
        'favoriteCount': merged.favorites.length,
        'deviceCount': remote.deviceCount,
        'writeMode': 'device',
      });
    } catch (error) {
      if (!current()) return;
      outcome = 'failed';
      appLogWarning('sync.favorites', 'Favorite sync failed', fields: {
        ...logFields,
        'outcome': outcome,
        'phase': phase,
        'errorType': error.runtimeType.toString(),
      });
      status = switch (error) {
        StateError(:final message) => '$message；本地收藏已保留',
        FormatException() || TypeError() => '收藏同步文件无效，已保留本地数据',
        _ => '收藏同步失败，本地修改已保留，请再次同步',
      };
    } finally {
      if (outcome == 'cancelled') {
        appLogInfo('sync.favorites', 'Favorite sync result discarded', fields: {
          ...logFields,
          'outcome': outcome,
          'phase': phase,
        });
      }
      final followUp = current() && _membershipChangedDuringSync && enabled;
      _activeSync = null;
      _membershipChangedDuringSync = false;
      completion.complete();
      if (!_disposed) {
        notifyListeners();
        // Only a new membership event may request another pass, never a timer.
        if (followUp) {
          unawaited(synchronize(trigger: FavoriteSyncTrigger.membershipChange));
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _changes?.cancel();
    _configChanges?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
