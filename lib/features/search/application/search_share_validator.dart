import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:starflow/core/network/starflow_http_client.dart';
import 'package:starflow/features/search/data/aliyun_transfer_client.dart';
import 'package:starflow/features/search/data/cloud115_save_client.dart';
import 'package:starflow/features/search/data/quark_save_client.dart';
import 'package:starflow/features/search/domain/search_models.dart';
import 'package:starflow/features/search/domain/share_link_validation.dart';
import 'package:starflow/features/settings/domain/app_settings.dart';

typedef SearchValidationJob = Future<ShareLinkValidationResult> Function();
typedef SearchValidationResolver = SearchValidationJob? Function(SearchResult);

final searchShareValidatorProvider = Provider((ref) => SearchShareValidator(
      quark: ref.watch(quarkSaveClientProvider),
      cloud115: ref.watch(cloud115SaveClientProvider),
      aliyun: AliyunTransferClient(ref.watch(starflowHttpClientProvider)),
    ));

class SearchShareValidator {
  const SearchShareValidator(
      {required this.quark, required this.cloud115, this.aliyun});

  final QuarkSaveClient quark;
  final Cloud115SaveClient cloud115;
  final AliyunTransferClient? aliyun;

  SearchValidationJob? resolve(
      SearchResult result, NetworkStorageConfig config) {
    if (result.detailTarget != null) return null;
    switch (detectSearchCloudTypeFromUrl(result.resourceUrl)) {
      case SearchCloudType.aliyun:
        if (aliyun == null || !config.hasAliyunCredential) {
          return null;
        }
        return () => aliyun!.validateShareLink(
            shareUrl: result.resourceUrl,
            password: searchResultSharePassword(result));
      case SearchCloudType.quark:
        if (config.quarkCookie.trim().isEmpty) return null;
        return () => quark.validateShareLink(
              shareUrl: result.resourceUrl,
              cookie: config.quarkCookie,
            );
      case SearchCloudType.cloud115:
        // The 115 client reports missing credentials as unavailable without IO.
        return () => cloud115.validateShareLink(
              shareUrl: result.resourceUrl,
              cookie: config.cloud115Cookie,
              password: result.password,
            );
      default:
        return null;
    }
  }
}
