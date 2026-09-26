/// Public endpoints of the OpenList authorization service.
///
/// The actual AliYun Open application secret stays on the service. Starflow
/// only receives short-lived authorization data and the device-local refresh
/// token returned after the user confirms the QR login.
class AliyunOpenOAuthConfig {
  const AliyunOpenOAuthConfig._();

  static const serviceBase = 'https://api.oplist.org';
  static const serviceBaseCn = 'https://api.oplist.org.cn';
  static const generateQr = '$serviceBase/alicloud2/generate_qr';
  static const checkLogin = '$serviceBase/alicloud2/check_login';
  static const userInfo = '$serviceBase/alicloud2/get_user_info';
  static const logout = '$serviceBase/alicloud2/logout';
  static const renew = '$serviceBase/alicloud2/renewapi';

  static const serviceBases = [serviceBase, serviceBaseCn];
  static const generateQrPath = '/alicloud2/generate_qr';
  static const checkLoginPath = '/alicloud2/check_login';
  static const userInfoPath = '/alicloud2/get_user_info';
  static const logoutPath = '/alicloud2/logout';
  static const renewPath = '/alicloud2/renewapi';
}
