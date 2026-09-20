import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'text_input_transfer_service_stub.dart'
    if (dart.library.io) 'text_input_transfer_service_io.dart' as impl;

const textInputTransferMaxBytes = 64 * 1024;

final textInputTransferServiceProvider = Provider<TextInputTransferService>(
    (_) => impl.createTextInputTransferService());

abstract class TextInputTransferService {
  Future<TextInputTransferSession> start({
    required String label,
    bool multiline = false,
    bool obscureText = false,
  });
}

abstract class TextInputTransferSession {
  List<String> get urls;
  Stream<String> get errors;
  Future<String?> get received;
  Future<void> close();
}
