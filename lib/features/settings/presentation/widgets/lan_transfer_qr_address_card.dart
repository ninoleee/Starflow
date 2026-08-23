import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:starflow/core/widgets/tv_focus.dart';

class LanTransferQrAddressCard extends StatelessWidget {
  const LanTransferQrAddressCard({
    super.key,
    required this.url,
    required this.focusNode,
    required this.focusId,
  });

  final String url;
  final FocusNode focusNode;
  final String focusId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const borderRadius = BorderRadius.all(Radius.circular(16));

    return TvFocusableAction(
      focusNode: focusNode,
      focusId: focusId,
      onPressed: () {},
      onFocused: () {
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      },
      visualStyle: TvFocusVisualStyle.prominent,
      borderRadius: borderRadius,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final qrCode = Semantics(
              image: true,
              label: '手机扫码打开局域网页面',
              child: RepaintBoundary(
                child: Container(
                  width: 176,
                  height: 176,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    key: ValueKey<String>('lan-transfer-qr:$url'),
                    data: url,
                    version: QrVersions.auto,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                    errorStateBuilder: (context, error) => const Center(
                      child: Text(
                        '二维码生成失败',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final address = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '手机扫码打开',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  url,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 480) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: qrCode),
                  const SizedBox(height: 14),
                  address,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                qrCode,
                const SizedBox(width: 18),
                Expanded(child: address),
              ],
            );
          },
        ),
      ),
    );
  }
}
