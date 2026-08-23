import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/presentation/widgets/lan_transfer_qr_address_card.dart';

void main() {
  testWidgets('LAN transfer card renders the complete tokenized URL as QR data',
      (tester) async {
    const url = 'http://192.168.1.20:8765/?token=ABC123';
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LanTransferQrAddressCard(
                url: url,
                focusNode: focusNode,
                focusId: 'test:lan-transfer-url',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final qrCode = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qrCode.key, const ValueKey<String>('lan-transfer-qr:$url'));
    expect(find.text(url), findsOneWidget);
    expect(find.text('手机扫码打开'), findsOneWidget);

    final action = tester.widget<TvFocusableAction>(
      find.byType(TvFocusableAction),
    );
    expect(action.focusId, 'test:lan-transfer-url');
    expect(action.focusNode, same(focusNode));
  });
}
