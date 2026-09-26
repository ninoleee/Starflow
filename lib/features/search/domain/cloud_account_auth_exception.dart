import 'cloud_save_rules.dart';

class CloudAccountAuthException extends CloudSaveException {
  const CloudAccountAuthException() : super('账号登录已失效，请重新登录');
}
