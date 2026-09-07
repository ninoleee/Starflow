import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starflow/core/widgets/starflow_logo.dart';

void main() {
  testWidgets('uses the replacement logo with stable bounds', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: StarflowLogo(
            iconSize: 96,
            showWordmark: false,
            showIconPlate: false,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/starflow_logo_primary.png',
    );
    expect(image.fit, BoxFit.contain);
    expect(tester.getSize(find.byType(StarflowLogo)), const Size(96, 96));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
