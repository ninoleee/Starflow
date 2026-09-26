import 'package:starflow/features/settings/domain/app_settings.dart';

/// Each editor owns only its fields, including when its save was debounced.
enum NetworkStorageSettingsScope {
  quark,
  cloud115,
  common,
  smartStrm,
  synchronization;

  NetworkStorageConfig merge(
          NetworkStorageConfig current, NetworkStorageConfig draft) =>
      switch (this) {
        quark => current.copyWith(
            quarkCookie: draft.quarkCookie,
            quarkSaveFolderId: draft.quarkSaveFolderId,
            quarkSaveFolderPath: draft.quarkSaveFolderPath,
            smartStrmTaskName: draft.smartStrmTaskName,
            syncDeleteQuarkEnabled: draft.syncDeleteQuarkEnabled,
            syncDeleteQuarkWebDavDirectories:
                draft.syncDeleteQuarkWebDavDirectories),
        cloud115 => current.copyWith(
            cloud115Cookie: draft.cloud115Cookie,
            cloud115SaveFolderId: draft.cloud115SaveFolderId,
            cloud115SaveFolderPath: draft.cloud115SaveFolderPath,
            cloud115SmartStrmTaskName: draft.cloud115SmartStrmTaskName,
            syncDelete115Enabled: draft.syncDelete115Enabled,
            syncDelete115WebDavDirectories:
                draft.syncDelete115WebDavDirectories),
        smartStrm => current.copyWith(
            smartStrmWebhookUrl: draft.smartStrmWebhookUrl,
            smartStrmDelaySeconds: draft.smartStrmDelaySeconds),
        synchronization => current.copyWith(
            refreshMediaSourceIds: draft.refreshMediaSourceIds,
            refreshDelaySeconds: draft.refreshDelaySeconds),
        common => synchronization
            .merge(smartStrm.merge(current, draft), draft)
            .copyWith(
                commonSanitizeSavedNamesEnabled:
                    draft.commonSanitizeSavedNamesEnabled,
                commonSanitizedNameCharacters:
                    draft.commonSanitizedNameCharacters),
      };
}
