import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:starflow/core/platform/tv_platform.dart';
import 'package:starflow/core/widgets/tv_focus.dart';
import 'package:starflow/features/settings/data/log_export_service.dart';
import 'package:starflow/features/settings/presentation/log_export_page.dart';
import 'package:starflow/features/settings/presentation/widgets/lan_transfer_qr_address_card.dart';

void main() {
  testWidgets('TV log export uses LAN download instead of a path editor',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = _FakeLogLanExportSession();
    final service = _FakeLogExportService(session: session);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isTelevisionProvider.overrideWith((ref) => true),
          logExportServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: LogExportPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('手机导出日志'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    tester
        .widget<StarflowButton>(
          find.widgetWithText(StarflowButton, '手机导出日志'),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(service.televisionExportStarts, 1);
    expect(find.text('访问码：ABC123'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    final qrCard = tester.widget<LanTransferQrAddressCard>(
      find.byType(LanTransferQrAddressCard),
    );
    expect(qrCard.url, 'http://192.168.1.8:8123/?token=ABC123');
    expect(find.text('手机扫码打开'), findsOneWidget);
    final urlActions = tester
        .widgetList<TvFocusableAction>(find.byType(TvFocusableAction))
        .where(
          (widget) =>
              widget.focusId?.startsWith('settings:logging:lan-url:') ?? false,
        );
    expect(urlActions, hasLength(1));

    tester
        .widget<StarflowButton>(
          find.widgetWithText(StarflowButton, '关闭服务'),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(session.closed, isTrue);
  });
}

class _FakeLogExportService implements LogExportService {
  _FakeLogExportService({required this.session});

  final LogLanExportSession session;
  int televisionExportStarts = 0;

  @override
  bool get isSupported => true;

  @override
  bool get supportsSystemExport => false;

  @override
  String get unsupportedReason => '';

  @override
  Future<String> buildSuggestedExportPath() async => '/tmp/starflow.log';

  @override
  Future<LogExportResult> exportLogs({required String targetPath}) async {
    return LogExportResult(path: targetPath, bytes: 1, sourceFileCount: 1);
  }

  @override
  Future<LogExportResult?> exportLogsWithSystemPicker({
    String? suggestedName,
  }) async {
    return LogExportResult(
      path: suggestedName ?? 'starflow.log',
      bytes: 1,
      sourceFileCount: 1,
    );
  }

  @override
  Future<String?> pickExportPath({String? suggestedName}) async {
    return '/tmp/${suggestedName ?? 'starflow.log'}';
  }

  @override
  Future<LogLanExportSession> startTelevisionExport() async {
    televisionExportStarts += 1;
    return session;
  }
}

class _FakeLogLanExportSession implements LogLanExportSession {
  bool closed = false;

  @override
  String get accessCode => 'ABC123';

  @override
  Stream<LogLanExportEvent> get events =>
      const Stream<LogLanExportEvent>.empty();

  @override
  int get port => 8123;

  @override
  List<String> get urls => const <String>[
        'http://192.168.1.8:8123/?token=ABC123',
      ];

  @override
  Future<void> close() async {
    closed = true;
  }
}
