import 'text_input_transfer_service.dart';

TextInputTransferService createTextInputTransferService() => _Unsupported();

class _Unsupported implements TextInputTransferService {
  @override
  Future<TextInputTransferSession> start({
    required String label,
    bool multiline = false,
    bool obscureText = false,
  }) =>
      Future.error(UnsupportedError('当前平台不支持手机输入'));
}
